import SwiftUI

/// Four questions on first run, which become `KESTREL.md`.
///
/// Kestrel reads that file before every answer, so the difference between a generic assistant and
/// one that knows who it is talking to is four fields filled in once. Every one is optional: an
/// empty profile is no worse than the file we shipped before. The step around it — heading, glass,
/// footer — belongs to `OnboardingSteps`.
struct OnboardingInterview: View {
    @ObservedObject var model: InterviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("What should I call you?", placeholder: "Ash", text: $model.name)
            field("What do you do?", placeholder: "iOS engineer", text: $model.role)
            field("What are you working on?",
                  placeholder: "A voice assistant for macOS", text: $model.project)

            VStack(alignment: .leading, spacing: 6) {
                Text("How much should I say?")
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: $model.style) {
                    ForEach(InterviewModel.Style.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            case .brief: return "Just the answer"
            case .normal: return "Normal"
            case .thorough: return "Talk me through it"
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
