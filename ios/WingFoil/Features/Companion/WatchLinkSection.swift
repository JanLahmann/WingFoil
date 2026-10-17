// Settings → Garmin watch — a BETA door (docs/channels.md; moved up from dev by Jan on
// 17 Oct 2026). The wind and map rows inside it stay dev.
#if BETA
import SwiftUI
import WingFoilKit

/// The watch link, in Settings (phase 5).
///
/// Everything on this screen is a fact the rider can act on: which watch, whether it is
/// reachable, when a session last came through, and — in the dev build — the buttons that
/// push the wind and the map. There is no "connect" button, because there is nothing to
/// connect — Garmin Connect Mobile owns the Bluetooth link and this app is a guest on it.
struct WatchLinkSection: View {
    @Environment(SessionStore.self) private var store
    /// Opens a help topic in the sheet Settings already owns, the way every other footer
    /// there does (`ExplainedFootnote`).
    var openTopic: (HelpTopicID) -> Void = { _ in }

    private var state: CompanionLinkState { store.companionState }

    var body: some View {
        Section {
            LabeledContent("Watch") {
                Text(state.headline)
                    .foregroundStyle(state.canSend ? .green : .readableSecondary)
                    .multilineTextAlignment(.trailing)
            }

            switch state {
            case .noConnectMobile:
                // Nothing this app can do: no GCM, no link, and no button worth offering.
                EmptyView()
            case .noDevice:
                Button { store.chooseWatch() } label: {
                    Label("Choose your watch…", systemImage: "applewatch.radiowaves.left.and.right")
                }
            default:
                // Back to the watch: dev only, both of them (docs/channels.md).
                #if DEV
                windRow
                mapRow
                #endif
                Button { store.chooseWatch() } label: {
                    Label("Choose a different watch…", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { store.forgetWatch() } label: {
                    Label("Forget this watch", systemImage: "minus.circle")
                }
            }

            if let direct = store.lastDirectTransfer {
                // The session the watch sent straight over (docs/transfer-format.md), in
                // the rider's words: when it was ridden, and whether all of it came.
                LabeledContent("Last session from the watch",
                               value: Self.directLine(direct))
            }
            if let last = store.lastCardAt {
                // `.current` deliberately: when the watch last reached this phone, which is an
                // event on the reader's clock rather than a moment in any session.
                LabeledContent("Last summary from the watch",
                               value: Fmt.date(last, zone: .current))
            }
            linkDetails
        } header: {
            HStack(spacing: 6) {
                Text("Garmin watch")
                BetaChip()
            }
        } footer: {
            // What you get in one line, the how one tap away (pattern K): the watch's own
            // switch and the twenty seconds on the beach are in the help topic.
            ExplainedFootnote(line: state.detail(in: AppChannel.channel),
                              topic: .garminDirect, open: openTopic)
        }
        .task { store.refreshCompanionState() }
    }

    #if DEV
    /// The wind push. A compass picker rather than a free 0–359 field: nobody knows the
    /// wind to the degree, the watch only uses it to decide which side of the axis a turn
    /// happened on, and a wrong 12° costs nothing while a wrong 120° relabels every tack.
    @ViewBuilder
    private var windRow: some View {
        @Bindable var store = store
        Picker("Wind from", selection: $store.windToSend) {
            ForEach(Self.compass, id: \.degrees) { point in
                Text("\(point.name) (\(point.degrees)°)").tag(point.degrees)
            }
            Text("Not set").tag(CompanionWind.clear)
        }
        Button {
            Task { await store.sendWindToWatch(store.windToSend) }
        } label: {
            Label("Send wind to watch", systemImage: "wind")
        }
        .disabled(!state.canSend)
    }

    /// The map push. The row names the ground that is about to go over
    /// (docs/watch-map-snapshot.md) and opens the picker that chooses it: by default the
    /// two most-ridden spots, as it always was, and otherwise up to two of the library's
    /// spots and "Where I am now" — the afternoon at a lake the library has never seen
    /// (Jan, 13 Sep 2026).
    ///
    /// The button exists even though the push is automatic, for the same reason the wind
    /// one does: a link that only ever works silently is a link nobody believes in. It
    /// re-sends unconditionally, which is the point of pressing it.
    @ViewBuilder
    private var mapRow: some View {
        let targets = store.watchMapTargets
        NavigationLink {
            WatchMapChoiceView()
        } label: {
            LabeledContent("Map for the watch") {
                Text(targets.isEmpty ? "No spot with a fix yet"
                                     : targets.map(\.name).joined(separator: " · "))
                    .multilineTextAlignment(.trailing)
            }
        }
        if !targets.isEmpty {
            if let result = store.watchMapStatus {
                LabeledContent("Last map", value: result)
            }
            Button {
                Task { await store.sendMapsToWatch() }
            } label: {
                HStack {
                    Label("Send map to watch", systemImage: "map")
                    if store.isSendingWatchMap {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!state.canSend || store.isSendingWatchMap)
        }
    }
    #endif

    /// **The link's own numbers, folded away** (Jan, dev 106: "1 page · 0 s" is
    /// meaningless to a rider). Pages, seconds and the answer are how a tester proves the
    /// radio (docs/direct-transfer.md), so the beta keeps them one tap away; the probe is
    /// the dev build's alone. Out of the rows a rider reads, and absent when there is
    /// nothing to show.
    @ViewBuilder
    private var linkDetails: some View {
        #if DEV
        let probe = store.lastLinkProbe
        #else
        let probe: String? = nil
        #endif
        let pages = store.directPageLine
        let answer = store.directAnswerLine
        let direct = store.lastDirectTransfer
        if probe != nil || pages != nil || answer != nil || direct != nil {
            DisclosureGroup("Link details") {
                if let direct {
                    LabeledContent("Last transfer", value: Self.directSummary(direct))
                }
                if let pages {
                    // Every page as it lands, before any session is whole: the line that
                    // says whether the radio reached the app at all.
                    LabeledContent("Direct pages", value: pages)
                }
                if let answer {
                    LabeledContent("Answer to the watch", value: answer)
                }
                if let probe {
                    // The watch times the send, the phone confirms what arrived.
                    LabeledContent("Link probe", value: probe)
                }
            }
        }
    }

    /// "Sat 19 Sep 19:42", or "Sat 19 Sep 19:42 · part of it" where the transfer stopped
    /// part way: which session, and whether the whole of it is on the phone. The pages and
    /// seconds are in Link details. The mark is `SessionProvenance.cutShortMark`, the same
    /// words the session's own page says it in since schema v21.
    static func directLine(_ receipt: DirectTransferReceipt) -> String {
        let when = Fmt.date(receipt.sessionStart, zone: .current)
        return receipt.cutShort ? when + " · " + SessionProvenance.cutShortMark : when
    }

    /// "18 Sep 14:07 · 13 pages · 26 s", and "cut short" where the transfer stopped part
    /// way. Three facts on one line, in the order they answer "did it work": which session,
    /// how much of it, how long it took. `.current` deliberately for the date — this row is
    /// about a transfer to this phone, and the clock is the reader's.
    ///
    /// **Which of the two streams** where it was the wrist one: it arrives minutes after the
    /// session it belongs to and takes this row over when it does, and a row that silently
    /// swapped "13 pages" for "8 pages" would read as a transfer that went backwards.
    static func directSummary(_ receipt: DirectTransferReceipt) -> String {
        var parts = [Fmt.date(receipt.sessionStart, zone: .current),
                     "\(receipt.pages) \(receipt.isWrist ? "wrist " : "")"
                        + "page\(receipt.pages == 1 ? "" : "s")",
                     "\(Int(receipt.seconds.rounded())) s"]
        if receipt.cutShort { parts.append("cut short") }
        return parts.joined(separator: " · ")
    }

    #if DEV
    /// Sixteen points, the same ones the watch's own Wind from menu offers
    /// (`RecordingDelegate`, 22.5° steps in integer arithmetic), so a wind set on either side
    /// reads back as the same point on the other. Eight was too coarse for a spot where the
    /// wind is NNE or WSW (Jan, dev 106).
    private static let compass: [(name: String, degrees: Int)] = [
        ("N", 0), ("NNE", 22), ("NE", 45), ("ENE", 67),
        ("E", 90), ("ESE", 112), ("SE", 135), ("SSE", 157),
        ("S", 180), ("SSW", 202), ("SW", 225), ("WSW", 247),
        ("W", 270), ("WNW", 292), ("NW", 315), ("NNW", 337),
    ]
    #endif
}

#endif
