import Foundation

/// The Kokoro voices Kestrel offers.
///
/// The model carries 53 of them across nine languages. Kestrel ships four: enough that a voice you
/// dislike is not the only option, few enough that the picker is a choice rather than a catalogue.
/// The speaker ids are the model's own indices — sherpa-onnx selects a voice by number, not name,
/// so these must match `kokoro-multi-lang-v1_0`'s ordering exactly. They are not guessable and
/// not alphabetical: they come from the `speaker2id` table in the model's own ONNX metadata.
struct KokoroVoice: Identifiable, Equatable {
    let id: String
    let speakerID: Int
    let title: String
    /// What it sounds like, for the picker.
    let note: String

    static let all: [KokoroVoice] = [
        KokoroVoice(id: "af_heart", speakerID: 3, title: "Heart", note: "American, warm"),
        KokoroVoice(id: "af_sarah", speakerID: 9, title: "Sarah", note: "American, even"),
        KokoroVoice(id: "am_michael", speakerID: 16, title: "Michael", note: "American, low"),
        KokoroVoice(id: "am_puck", speakerID: 18, title: "Puck", note: "American, bright"),
    ]

    /// Kokoro's flagship voice, and the one the model is best tuned for.
    static let `default` = all[0]

    static func named(_ id: String) -> KokoroVoice {
        all.first { $0.id == id } ?? .default
    }
}
