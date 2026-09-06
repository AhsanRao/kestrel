import AVFoundation
import Foundation
import os

/// Writes normalised float samples out as the one format whisper.cpp wants, so nothing has to
/// convert the file a second time before transcribing it.
enum WAVWriter {
    /// 16 kHz mono 16-bit WAV — exactly what whisper.cpp wants, with no second conversion.
    static func write(_ samples: [Float], format: AVAudioFormat, log: Logger) -> URL? {
        let url = Paths.temporaryFile(ext: "wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let chunk = 16_000
            var offset = 0
            while offset < samples.count {
                let count = min(chunk, samples.count - offset)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let channel = buffer.floatChannelData?[0] else { break }
                samples.withUnsafeBufferPointer { pointer in
                    channel.update(from: pointer.baseAddress! + offset, count: count)
                }
                buffer.frameLength = AVAudioFrameCount(count)
                try file.write(from: buffer)
                offset += count
            }
        } catch {
            log.error("could not write wav: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}
