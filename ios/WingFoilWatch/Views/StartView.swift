import CoreLocation
import SwiftUI
import WatchKit

/// Before the session: is the watch ready, and one button to go.
///
/// The GPS line is the whole screen's job. A wingfoiler launches from a beach, and the
/// difference between starting with a fix and starting without one is the difference between
/// a session with speed records and a session with a straight line through the first two
/// minutes. So the state is said in words and colour, and START stays available regardless —
/// a rider who wants to record anyway is not going to be argued with by his watch.
///
/// **The mark sits on top of it, and there is no splash.** The phone holds a brand screen for
/// two seconds on a cold start (`SplashView`) because a phone app opens into a library that
/// takes a moment to read. A watch app opens into a button a rider is standing in the
/// shallows waiting to press, and a timed screen in front of that would be two seconds of
/// nothing at the worst possible moment. So the brand is simply *on* the start page — the
/// first thing seen, above its own name — and the page is already the thing the rider came
/// for.
struct StartView: View {
    @Environment(SessionRecorder.self) private var recorder

    /// Big enough to be read as the mark rather than as a bullet, small enough to leave the
    /// screen its GPS line, its button and both of the notes that can appear below it — which
    /// is why it is a fraction of the glass and not a constant. At 34 pt flat, a 40 mm SE
    /// (162 × 197 pt) pushed "Allow Apple Health to record heart rate" off the bottom edge and
    /// truncated it mid-word; this gives that watch 28 pt and an Ultra (205 × 251) its 35.
    private static var markSide: CGFloat {
        min(36, max(26, (WKInterfaceDevice.current().screenBounds.height * 0.14).rounded()))
    }

    var body: some View {
        // The screen scrolls now, and the mark is what made it have to. A 40 mm SE has about
        // 165 pt of usable glass and the page already spent it: on the launch where Health has
        // not been allowed yet, "Allow Apple Health to record heart rate" lost its second line
        // to the mark and truncated mid-word. `FailureView` already scrolls for the same
        // reason. `.basedOnSize` so that the ordinary case — GPS line, button, nothing else —
        // is still a page that does not move under the thumb.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(spacing: 8) {
            // Mark and wordmark tight together — one lockup, not two things in a list.
            VStack(spacing: 3) {
                Image(ChannelArt.brandMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.markSide, height: Self.markSide)
                    // One element with the wordmark below it, so VoiceOver reads "CleanJibe"
                    // once rather than announcing an image it cannot describe.
                    .accessibilityHidden(true)

                Text("CleanJibe")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Brand.green)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(status.color)
                    .frame(width: 8, height: 8)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(Brand.paper.opacity(0.85))
            }

            Button {
                recorder.start()
            } label: {
                Text("START")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.green)
            .foregroundStyle(Brand.navy)
            .disabled(recorder.phase == .starting)

            if !recorder.healthAuthorized {
                Text("Allow Apple Health to record heart rate")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }

            // Nothing is lost while the phone is in a drybag; say so rather than leaving the
            // rider to wonder where an afternoon went.
            if SessionTransfer.shared.pendingCount > 0 {
                Text("\(SessionTransfer.shared.pendingCount) session\(SessionTransfer.shared.pendingCount == 1 ? "" : "s") waiting for iPhone")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Brand.cyan)
            }
        }
        .padding(.horizontal, 4)
    }

    private var status: (label: String, color: Color) {
        switch recorder.locationAuthorization {
        case .denied, .restricted:
            return ("Location is off", .orange)
        case .notDetermined:
            return ("Asking for location", .orange)
        default:
            break
        }
        if recorder.hasUsableFix {
            let accuracy = Int((recorder.fixAccuracyM ?? 0).rounded())
            return ("GPS ready · \(accuracy) m", Brand.green)
        }
        return ("Finding GPS", .orange)
    }
}
