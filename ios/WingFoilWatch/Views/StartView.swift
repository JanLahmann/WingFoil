import CoreLocation
import SwiftUI

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
    /// 40 mm screen its GPS line, its button and both of the notes that can appear below.
    private static let markSide: CGFloat = 34

    var body: some View {
        VStack(spacing: 8) {
            // Mark and wordmark tight together — one lockup, not two things in a list.
            VStack(spacing: 3) {
                Image("BrandMark")
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
