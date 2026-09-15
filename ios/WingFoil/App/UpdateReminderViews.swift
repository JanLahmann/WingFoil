#if BETA
import SwiftUI
import WingFoilKit

/// **The three surfaces of the beta's update reminder** (docs/presentation.md, "The beta's
/// update reminder"). One line, one screen, one row, and nothing else anywhere in the app.
///
/// All three read `UpdateReminder.shared` directly rather than taking it from the
/// environment, and all three draw *nothing* when there is nothing to say — which is what
/// lets each of them be a single line in a file that belongs to another feature. A body that
/// ends in no view is no row in the list and no overlay on the tabs; there is no empty box
/// left behind and no placeholder to explain.
///
/// **Beta and dev only** (`#if BETA`, docs/channels.md).

// MARK: - The line

/// **One dismissable line at the top of the library** — `remind`.
///
/// At the top of the list rather than in an alert, and for the same reason the usage ask is
/// (`UsageAskCard`): an alert interrupts whatever the rider opened the app to do, and being
/// a build behind is not an emergency. It waits where he is already looking, it says which
/// build and why in Jan's own sentence, and one tap on the ✕ takes it away until the number
/// in the file moves again.
@MainActor
struct UpdateReminderBanner: View {
    @Environment(\.openURL) private var openURL

    private var reminder: UpdateReminder { .shared }

    var body: some View {
        if reminder.verdict == .remind {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(UpdateReminderText.line(reminder.message))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = reminder.updateURL {
                        Button("Update") { openURL(url) }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(.teal)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    reminder.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.teal.opacity(0.10), in: .rect(cornerRadius: 12))
            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - The screen

/// **The whole of the app until the newer build is on the phone** — `insist`.
///
/// A screen rather than a louder line, and the third one in the app to be argued for that way
/// (`LibraryNewerThanAppView`, `StartOverRelaunchView`): behind a banner the four tabs would
/// go on inviting the rider to record an afternoon, import it and report on it with a build
/// whose reports are the reason this screen exists. There is one useful thing to do and one
/// button for it.
///
/// **It cannot be dismissed**, which is the only thing that distinguishes it from the line.
/// Nothing on it touches the library either: the sessions are where they were, and the newer
/// build finds them exactly there.
@MainActor
struct UpdateReminderScreen: View {
    @Environment(\.openURL) private var openURL

    private var reminder: UpdateReminder { .shared }

    /// In points rather than a text style because no text style is 44 pt — `@ScaledMetric`
    /// keeps it growing with the rider's setting, the same as the other two screens.
    @ScaledMetric(relativeTo: .largeTitle) private var heroGlyph: CGFloat = 44

    var body: some View {
        if reminder.verdict == .insist {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: heroGlyph))
                        .foregroundStyle(.teal)
                        .padding(.top, 40)

                    Text("Time for a newer CleanJibe.")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(UpdateReminderText.line(reminder.message))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = reminder.updateURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Update", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    Text("This build is \(reminder.runningBuild).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)

                    Text("Nothing has been changed and nothing is lost. Your sessions are "
                         + "still on this phone, and the newer build opens them exactly "
                         + "where they are.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .readableColumn()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - The row

/// **Settings → Beta → *Check for a newer build now***, with the two facts under it: when the
/// switch was last read, and what it said.
///
/// The one place all four verdicts are named, because it is the one place the rider asked.
/// It is also the door for the tester who closed the line and changed his mind — closing it
/// takes the banner away, never the fact.
@MainActor
struct UpdateReminderSettingsRow: View {

    private var reminder: UpdateReminder { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await reminder.checkNow() }
            } label: {
                Label("Check for a newer build now", systemImage: "arrow.down.circle")
            }
            .disabled(reminder.isChecking)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Build 59 · This is the current build. · checked 15 Sep 14:20" — the running build,
    /// the verdict in the kit's words (`UpdateVerdict.label`), and the clock. A check that
    /// has never landed says so rather than showing an empty half-sentence.
    private var status: String {
        var parts = ["Build \(reminder.runningBuild)", reminder.verdict.label]
        if reminder.isChecking {
            parts.append("checking…")
        } else if let last = reminder.lastCheck {
            parts.append("checked \(Self.stamp.string(from: last))")
        } else {
            parts.append("not checked yet")
        }
        return parts.joined(separator: " · ")
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()
}

// MARK: - The one sentence, in one place

/// What the banner and the screen print. Jan's sentence from `version.json` when there is
/// one; the plain fact when the file carries no message, so a half-filled entry still reads
/// as something rather than as an empty box.
enum UpdateReminderText {
    static func line(_ message: String?) -> String {
        let trimmed = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "A newer CleanJibe build is out." : trimmed
    }
}

/// **The three insertions, written out.** This preview is the exact shape the feature takes in
/// `LibraryView`, `RootView` and `BetaSectionView` — the one line each of them carries — so
/// the compiler checks those call sites here rather than in three files that belong to other
/// features. On a machine with no `version.json` to read, all three draw nothing, which is
/// also the thing worth seeing: no empty row, no grey box, no placeholder.
#Preview {
    List {
        UpdateReminderBanner()                                   // LibraryView, inside `#if BETA`
        Section("Beta") { UpdateReminderSettingsRow() }           // BetaSectionView
    }
    .overlay { UpdateReminderScreen() }                           // RootView, inside `#if BETA`
}
#endif
