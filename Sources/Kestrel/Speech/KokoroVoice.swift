import Foundation

/// Four of the model's 54 voices — enough to choose from, short enough to read.
///
/// sherpa-onnx selects by index, not name. The indices are not alphabetical; they come from the
/// model's own `speaker2id` metadata, and a wrong one speaks in a stranger's voice.
struct KokoroVoice: Identifiable, Equatable {
    let id: String
    let speakerID: Int
    let title: String
    /// Shown in the picker.
    let note: String

    static let all: [KokoroVoice] = [
        KokoroVoice(id: "af_heart", speakerID: 3, title: "Heart", note: "American, warm"),
        KokoroVoice(id: "af_sarah", speakerID: 9, title: "Sarah", note: "American, even"),
        KokoroVoice(id: "am_michael", speakerID: 16, title: "Michael", note: "American, low"),
        KokoroVoice(id: "am_puck", speakerID: 18, title: "Puck", note: "American, bright"),
    ]

    /// Kokoro's flagship, and its best-tuned voice.
    static let `default` = all[0]

    static func named(_ id: String) -> KokoroVoice {
        all.first { $0.id == id } ?? .default
    }
}
