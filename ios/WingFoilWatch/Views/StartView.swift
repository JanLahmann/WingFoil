import CoreLocation
import SwiftUI

/// Before the session: is the watch ready, and one button to go.
///
/// The GPS line is the whole screen's job. A wingfoiler launches from a beach, and the
/// difference between starting with a fix and starting without one is the difference between
/// a session with speed records and a session with a straight line through the first two
/// minutes. So the state is said in words and colour, and START stays available regardless —
/// a rider who wants to record anyway is not going to be argued with by his watch.
struct StartView: View {
    @Environment(SessionRecorder.self) private var recorder

    var body: some View {
        VStack(spacing: 8) {
            Text("CleanJibe")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Brand.green)

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
