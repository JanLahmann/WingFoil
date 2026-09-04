import SwiftUI

/// While riding.
///
/// Two pages, the way every watchOS workout app does it and for the reason it does it: the
/// metrics page is what the rider glances at, and the controls page is a deliberate swipe
/// away so a wet sleeve cannot end a session. Metrics is selected on entry.
///
/// **Horizontal paging**, which is Apple's own Workout layout and therefore the one already in
/// the rider's fingers — controls to the left of metrics. `.verticalPage` was the other option
/// and is tempting because the crown drives it, but it is the Smart Stack's idiom rather than
/// a workout's, and the crown does not help here anyway: while the screen is water-locked the
/// crown's job is to *unlock*, not to page, and once unlocked touch works normally.
///
/// The screen is water-locked from the moment START is pressed, so touch does nothing until
/// the crown is turned — which is the point. Everything here is sized to be read, not tapped.
struct RecordingView: View {
    @Environment(SessionRecorder.self) private var recorder
    @State private var page = Page.metrics

    enum Page: Hashable { case controls, metrics }

    var body: some View {
        TabView(selection: $page) {
            ControlsPage().tag(Page.controls)
            MetricsPage().tag(Page.metrics)
        }
        .tabViewStyle(.page)
    }
}

private struct MetricsPage: View {
    @Environment(SessionRecorder.self) private var recorder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // THE number. Everything else on this watch is arranged around it: a wingfoiler
            // checking speed is doing it at 20 knots with one hand on a wing, and the reading
            // has to survive spray, motion blur and a glance measured in tenths of a second.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WatchFormat.speed(recorder.speedMps))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(recorder.phase == .paused ? Brand.paper.opacity(0.4) : Brand.paper)
                Text("kn")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Brand.green)
            }

            if recorder.phase == .paused {
                Text("PAUSED")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.orange)
            } else if !recorder.hasUsableFix {
                // A session with heart rate and no track is the one failure the rider cannot
                // see from the speed alone — 0.0 kn looks like waiting for wind. Say it.
                Text("NO GPS")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.orange)
            }

            Divider().overlay(Brand.paper.opacity(0.2))

            HStack {
                Metric(icon: "heart.fill",
                       value: WatchFormat.heartRate(recorder.heartRateBpm),
                       tint: .red)
                Spacer(minLength: 4)
                Metric(icon: "timer",
                       value: WatchFormat.duration(recorder.elapsedS),
                       tint: Brand.cyan)
            }
            HStack {
                Metric(icon: "arrow.left.and.right",
                       value: WatchFormat.distance(recorder.distanceM),
                       tint: Brand.lime)
                Spacer(minLength: 4)
                Metric(icon: "gauge.with.dots.needle.100percent",
                       value: "\(WatchFormat.speed(recorder.maxSpeedMps)) max",
                       tint: Brand.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Metric: View {
    let icon: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(Brand.paper)
        }
    }
}

private struct ControlsPage: View {
    @Environment(SessionRecorder.self) private var recorder

    var body: some View {
        VStack(spacing: 10) {
            Button {
                recorder.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                if recorder.phase == .paused { recorder.resume() } else { recorder.pause() }
            } label: {
                Label(recorder.phase == .paused ? "Resume" : "Pause",
                      systemImage: recorder.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Brand.cyan)
        }
        .padding(.horizontal, 2)
    }
}
