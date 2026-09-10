import AVFoundation
import Foundation
import Speech
import os

/// The microphone half of live dictation: the tap, the conversion into the format the analyser
/// asked for, and the level the panel draws. Split from `AppleLiveDictation` only for length.
@available(macOS 26.0, *)
extension AppleLiveDictation {
    func startEngine(feeding target: AVAudioFormat?) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw KestrelError.transcriptionFailed("no input device")
        }
        let analysed = target ?? inputFormat
        converter = analysed == inputFormat ? nil : AVAudioConverter(from: inputFormat, to: analysed)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.feed(buffer, as: analysed)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw KestrelError.transcriptionFailed(error.localizedDescription)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.silence.start(seconds: self.silenceSeconds)
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer, as target: AVAudioFormat) {
        if let channel = buffer.floatChannelData?[0] {
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let level = meter.push(samples)
            if level > SilenceWatch.quietBelow { silence.heardSound() }
            if Date().timeIntervalSince(lastLevelSent) > 0.04 {
                lastLevelSent = Date()
                DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
            }
        }
        guard let converted = convert(buffer, to: target) else { return }
        continuation?.yield(AnalyzerInput(buffer: converted))
    }

    func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0 else { return nil }
        return out
    }
}
