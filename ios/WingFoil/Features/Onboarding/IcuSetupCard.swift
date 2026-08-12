import SwiftUI
import WingFoilKit

/// The first thing a new install shows: the four intervals.icu steps, walked inline, with
/// the key field right there under step 4.
///
/// The steps are `IcuSetupGuide` — the same text the Help topic renders — so the wizard
/// and the manual cannot drift apart. Which of the three faces this card wears is decided
/// by `IcuOnboarding.state`, a pure function in the kit, because the first screen a user
/// sees is exactly the one nobody tests twice by hand.
struct IcuSetupCard: View {
    let state: IcuOnboardingState
    var onImport: () -> Void

    @Environment(SessionStore.self) private var store
    @State private var helpTopic: HelpTopicID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if case .problem(let problem) = state {
                problemBanner(problem)
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(IcuSetupGuide.steps) { step in
                    stepRow(step)
                }
            }

            IcuKeyEntry()

            footer
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
        .sheet(item: $helpTopic) { HelpTopicSheet(id: $0) }
    }

    // MARK: - Pieces

    private var isFailing: Bool { if case .problem = state { true } else { false } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text(isFailing ? "Finish connecting intervals.icu"
                     : "Get set up with intervals.icu")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(IcuSetupGuide.rationaleShort)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The mapped cause of the last failure — never a raw error, always a cause and a fix.
    private func problemBanner(_ problem: IcuProblem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(problem.title, systemImage: problem.kind == .empty
                  ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(problem.kind == .empty ? Color.orange : .red)
            Text(problem.message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text(problem.fix)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("What to check") { helpTopic = problem.helpTopic }
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func stepRow(_ step: IcuSetupStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link = step.link {
                    Link(destination: link.url) {
                        Label(link.title, systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(spacing: 16) {
                Button { helpTopic = .icuSetup } label: {
                    Label("Full setup guide", systemImage: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                }
                Button { helpTopic = .icuTroubleshooting } label: {
                    Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                        .font(.footnote.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Button {
                    Task { await store.syncFromIntervals() }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.semibold))
                }
                .disabled(store.isBusy || store.apiKey.isEmpty)
                Button(action: onImport) {
                    Label("Import a file instead", systemImage: "square.and.arrow.down")
                        .font(.footnote.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            Text("No intervals.icu account? A FIT exported from Garmin Connect, or the "
                 + "whole \"Export Your Data\" ZIP, imports without any of this.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
