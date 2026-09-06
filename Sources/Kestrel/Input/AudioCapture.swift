import AVFoundation
import Foundation
import os

/// Records the default input to a 16 kHz mono 16-bit WAV — exactly what whisper.cpp wants, so no
/// second conversion step is needed before transcribing (spec §8.2).
final class AudioCapture {
    enum Failure: Error { case permissionDenied, engineFailed(String) }

    /// Anything shorter is an accidental hotkey tap, not speech.
    static let minimumDuration: TimeInterval = 0.3

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "audio")
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputURL: URL?
    private var startedAt: Date?
    private var maxDurationTimer: DispatchWorkItem?

    private(set) var isRecording = false

    /// Called when recording ends on its own: the max duration elapsed, or the input device left.
    var onAutoStop: ((URL?) -> Void)?

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

        let url = Paths.temporaryFile(ext: "wav")
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw Failure.engineFailed("no input device") }

        // Pro interfaces run at 44.1/48/96 kHz; the converter absorbs whatever the device reports.
        guard let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw Failure.engineFailed("unsupported input format \(inputFormat)")
        }
        self.converter = converter

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
        outputURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer, target: target)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
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
        log.debug("recording at \(inputFormat.sampleRate) Hz → \(url.lastPathComponent, privacy: .public)")
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
        file = nil
        converter = nil

        let url = outputURL
        outputURL = nil
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        startedAt = nil

        guard let url, duration >= AudioCapture.minimumDuration else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return url
    }

    // MARK: - Private

    private func append(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter, let file else { return }
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
        guard error == nil, out.frameLength > 0 else { return }
        try? file.write(from: out)
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
