import SwiftUI

/// Four questions on first run, which become `KESTREL.md`.
///
/// Kestrel reads that file before every answer, so the difference between a generic assistant and
/// one that knows who it is talking to is four fields filled in once. Every one is optional and the
/// whole thing is skippable: an empty profile is no worse than the file we shipped before.
struct OnboardingInterview: View {
    @ObservedObject var model: InterviewModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Tell Kestrel who it's talking to")
                    .font(.system(size: 19, weight: .semibold))
                Text("This goes in a file on your Mac that Kestrel reads before it answers. "
                     + "Skip anything you'd rather not say — you can edit it later from the menu.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            field("What should I call you?", placeholder: "Ash", text: $model.name)
            field("What do you do?", placeholder: "iOS engineer", text: $model.role)
            field("What are you working on right now?",
                  placeholder: "A voice assistant for macOS", text: $model.project)

            VStack(alignment: .leading, spacing: 6) {
                Text("How should I answer?")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $model.style) {
                    ForEach(InterviewModel.Style.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Button("Skip") { onDone() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Save") {
                    model.save()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// What the interview collects, and how it becomes the memory file.
final class InterviewModel: ObservableObject {
    enum Style: String, CaseIterable {
        case brief, normal, thorough

        var title: String {
            switch self {
            case .brief: return "Short"
            case .normal: return "Normal"
            case .thorough: return "Thorough"
            }
        }

        var line: String {
            switch self {
            case .brief: return "Answer style: as short as possible, one or two sentences"
            case .normal: return "Answer style: concise, no filler, spoken out loud"
            case .thorough: return "Answer style: explain the reasoning, not only the conclusion"
            }
        }
    }

    @Published var name = ""
    @Published var role = ""
    @Published var project = ""
    @Published var style: Style = .normal

    var isEmpty: Bool {
        [name, role, project].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func save() {
        MemoryStore.write(InterviewModel.memory(name: name, role: role, project: project,
                                                style: style, existing: MemoryStore.read()))
    }

    /// Rewrites the profile section, leaving everything else in the file alone — the user may have
    /// edited it by hand before ever reaching this window.
    static func memory(name: String, role: String, project: String, style: Style,
                       existing: String) -> String {
        let clean = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var profile = ["## Profile", ""]
        if !clean(name).isEmpty { profile.append("- Name: \(clean(name))") }
        if !clean(role).isEmpty { profile.append("- Role: \(clean(role))") }
        profile.append("- Machine: macOS, Apple Silicon")
        profile.append("- \(style.line)")
        if !clean(project).isEmpty {
            profile += ["", "## Current project", "", "- \(clean(project))"]
        }

        let body = profile.joined(separator: "\n")
        // Everything from the first heading after the profile onward is the user's own.
        guard let start = existing.range(of: "## Profile") else {
            let head = existing.isEmpty ? "# Kestrel memory\n" : existing
            return head + "\n" + body + "\n"
        }
        let head = String(existing[..<start.lowerBound])
        let rest = existing[start.upperBound...]
        let tail = rest.range(of: "\n## ").map { String(rest[$0.lowerBound...]) } ?? "\n"
        return head + body + tail
    }
}
