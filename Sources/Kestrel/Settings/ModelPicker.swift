import SwiftUI

/// Picks a model by name instead of asking anyone to type one.
///
/// The CLI takes an alias — `opus`, `sonnet` — or a full model id, and left alone it picks a sensible
/// default of its own. All three are worth offering, so the list is the aliases plus "whatever the
/// CLI picks", and a value already in the config that is neither stays in the list as itself. A
/// picker that silently dropped a hand-set model id would be worse than the text field it replaced.
struct ModelPicker: View {
    let title: String
    let options: [ModelOption]
    /// Empty means: don't pass `--model` at all.
    @Binding var value: String

    var body: some View {
        Picker(title, selection: $value) {
            Text("Whatever the CLI picks").tag("")
            ForEach(options) { option in
                Text(option.title).tag(option.id)
            }
            if !value.isEmpty, !options.contains(where: { $0.id == value }) {
                Text(value).tag(value)
            }
        }
    }
}

struct ModelOption: Identifiable, Hashable {
    /// What gets passed to `--model`.
    let id: String
    let title: String

    /// `claude --help`: "Provide an alias for the latest model (e.g. 'sonnet' or 'opus') or a
    /// model's full name". Aliases rather than pinned ids, so a new release is picked up without
    /// Kestrel shipping an update.
    static let claude = [
        ModelOption(id: "opus", title: "Opus — the deepest thinker"),
        ModelOption(id: "sonnet", title: "Sonnet — quick and sharp"),
        ModelOption(id: "haiku", title: "Haiku — fastest, lightest"),
    ]
}
