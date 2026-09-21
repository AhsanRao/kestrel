import AVFoundation
import Foundation
import os

/// Records the default input to a 16 kHz mono 16-bit WAV — exactly what whisper.cpp wants, so no
/// second conversion step is needed before transcribing (spec §8.2).
final class AudioCapture {
    enum Failure: Error { case permissionDenied, engineFailed(String) }

    /// Anything shorter is an accidental hotkey tap, not speech.
    static let minimumDuration: TimeInterval = 0.3
    /// Below this peak the take is silence, not quiet speech.
    static let silenceFloor: Float = 0.004
    static let targetPeak: Float = 0.92
    static let maximumGain: Float = 12

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "audio")
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    /// Samples are held rather than streamed to disk so the whole take can be normalised at the
    /// end. Quiet input is the single biggest cause of whisper mishearing words.
    private var samples: [Float] = []
    private let samplesLock = NSLock()
    private var meter = LevelMeter()
    private var lastLevelSent = Date.distantPast
    private var startedAt: Date?
    private var maxDurationTimer: DispatchWorkItem?

    private(set) var isRecording = false

    /// Called when recording ends on its own: the max duration elapsed, or the input device left.
    var onAutoStop: ((URL?) -> Void)?
    /// Smoothed input level, 0…1, delivered on the main thread while recording. Drives the panel's
    /// waveform, so what the user sees is their own voice rather than a canned animation.
    var onLevel: ((Float) -> Void)?

    static func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start(maxDuration: TimeInterval) throws {
        guard !isRecording else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Failure.permissionDenied
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw Failure.engineFailed("no input device") }

        guard let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw Failure.engineFailed("cannot make a 16 kHz format")
        }
        self.converter = nil
        self.target = target
        samplesLock.lock(); samples.removeAll(keepingCapacity: true); samplesLock.unlock()
        meter.reset()

        // No format is named for the tap, and the converter is built from the first buffer that
        // arrives, not from what the node reports here. After the engine has been stopped and the
        // microphone used by something else — the live dictation engine, or AirPods coming and
        // going — `outputFormat` can lag the hardware, and naming it raises an uncatchable
        // "Failed to create tap due to format mismatch" that took the whole app down. Pro
        // interfaces run at 44.1/48/96 kHz; the converter absorbs whatever actually comes in.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.append(buffer, target: target)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.engineFailed(error.localizedDescription)
        }

        isRecording = true
        startedAt = Date()
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
                                               name: .AVAudioEngineConfigurationChange, object: engine)

        let timer = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.log.info("max duration reached, stopping")
            self.onAutoStop?(self.stop())
        }
        maxDurationTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration, execute: timer)
    }

    /// Returns the WAV, or nil when the press was too short to be speech.
    @discardableResult
    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        maxDurationTimer?.cancel()
        maxDurationTimer = nil
        NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        samplesLock.lock()
        var captured = samples
        samples.removeAll(keepingCapacity: false)
        samplesLock.unlock()
        let format = target
        converter = nil
        target = nil

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil
        guard duration >= AudioCapture.minimumDuration, let format else { return nil }

        // Nothing above the noise floor: silence, or a muted input. Whisper would invent a
        // sentence for it, so stop here instead.
        let peak = captured.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > AudioCapture.silenceFloor else {
            log.info("recording peaked at \(peak, format: .fixed(precision: 4)) — treating as silence")
            return nil
        }

        // Lift a quiet take to a healthy level. Capped so room tone in a long pause is not
        // amplified into something whisper tries to transcribe.
        let gain = min(AudioCapture.targetPeak / peak, AudioCapture.maximumGain)
        if gain > 1.01 {
            for index in captured.indices { captured[index] *= gain }
            log.debug("normalised: peak \(peak, format: .fixed(precision: 3)) × \(gain, format: .fixed(precision: 2))")
        }
        return WAVWriter.write(captured, format: format, log: log)
    }

    // MARK: - Private

    private func append(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            log.debug("recording at \(buffer.format.sampleRate) Hz")
        }
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let channel = out.floatChannelData?[0] else { return }
        let incoming = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))

        // Roughly 25 updates a second: enough to look alive, few enough to cost nothing.
        let level = meter.push(incoming)
        if Date().timeIntervalSince(lastLevelSent) > 0.04 {
            lastLevelSent = Date()
            let block = onLevel
            DispatchQueue.main.async { block?(level) }
        }

        samplesLock.lock()
        samples.append(contentsOf: incoming)
        samplesLock.unlock()
    }

    /// AirPods disconnecting mid-sentence changes the engine configuration. Keep what was captured
    /// rather than throwing the recording away.
    @objc private func configurationChanged() {
        guard isRecording else { return }
        log.info("input device changed mid-recording, stopping and keeping audio")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.onAutoStop?(self.stop())
        }
    }
}
