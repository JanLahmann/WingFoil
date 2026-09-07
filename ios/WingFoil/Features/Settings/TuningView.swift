import SwiftUI
import WingFoilKit

// **Dev build only** — the whole file compiles only under the `TUNING` condition, which only
// the "WingFoil Dev" scheme sets (ios/project.yml, `Dev Debug` / `Dev Release`). The app that
// goes to external TestFlight testers has no tuning page, no tuning row in Settings, no chip
// and no banner: `SessionIngestor.tuning` is never assigned there, so the engine can only run
// the published defaults and a `tuningOverrides.v1` left in UserDefaults by a dev build
// installed over the same bundle id is not even read.
//
// A compile-time variant rather than a hidden runtime switch on purpose: a threshold slider
// that *exists* in the shipping binary is a threshold slider that can be reached by accident,
// by a URL, or by a future refactor — and the numbers it moves are the numbers riders compare
// with each other.
#if TUNING

/// **Settings → Tuning** — the published thresholds, on sliders, on this phone.
///
/// Jan, 7 Sep 2026: *"can we make some of the parameters configurable (for now) on a details
/// page in the app? That might speed up tuning the parameters."* Tuning a threshold used to
/// mean editing `TurnConfig`, rebuilding, re-importing a corpus and reading a diff — an
/// afternoon per question, and the question is usually "what would 22°/s have done to *my*
/// sessions". This page answers it in a minute, against the library already on the phone.
///
/// **It is a testing tool and it says so.** Every number in docs/algorithms.md is a contract
/// the watch, the lab and the web all keep; this page is the one place that contract can be
/// broken, so it is broken loudly — the sessions it produces carry a fingerprint in their
/// engine version (`TuningStamp`), and every screen that shows a tuned number wears a chip
/// saying so. Nothing here reaches the watch or the web.
struct TuningView: View {
    @Environment(SessionStore.self) private var store

    /// Seeded by the caller, because the page has to open on the rider's current settings and
    /// a view cannot read the environment in `init`.
    @State private var overrides: TuningOverrides
    /// Whether anything moved while the page was open. What decides if leaving it is worth a
    /// re-analysis — the lazy sweep would get there on its own at the next launch, but a rider
    /// tuning thresholds is a rider who wants to see the effect now.
    @State private var touched = false
    @State private var confirmResetAll = false
    /// Read here only for the row's count — the page itself lives in `TuningLabelsView`.
    @State private var labels = TurnLabelStore.shared

    init(initial: TuningOverrides) {
        _overrides = State(initialValue: initial)
    }

    var body: some View {
        Form {
            statusSection
            ForEach(TuningGroup.allCases, id: \.self) { group in
                Section {
                    ForEach(TuningParameter.all(in: group), id: \.self) { parameter in
                        row(parameter)
                    }
                } header: {
                    Text(group.rawValue)
                } footer: {
                    Text(group.blurb)
                }
            }
            labelsSection
            footerSection
        }
        .navigationTitle("Tuning")
        .navigationBarTitleDisplayMode(.inline)
        // The lazy path would pick this up at the next launch (`reanalyzeStale`, which the
        // fingerprint has just made true of every row). Doing it on the way out is the same
        // trip, taken while the rider is still thinking about the slider he moved.
        .onDisappear {
            guard touched else { return }
            // The workbench's cached default analyses were built against the previous setting.
            // The version key would catch this on its own once the library re-derives; dropping
            // them here means the next session opened cannot show a comparison from before the
            // slider moved even for the instant between the two.
            DevWorkbench.shared.invalidateAll()
            guard !store.sessions.isEmpty else { return }
            Task { await store.reanalyzeTuned() }
        }
        .confirmationDialog("Reset every threshold to its published default?",
                            isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button("Reset \(overrides.changedCount) threshold"
                   + "\(overrides.changedCount == 1 ? "" : "s")", role: .destructive) {
                overrides.resetAll()
                commit()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            if overrides.isEmpty {
                Label("Every threshold is at its published default",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                TunedChip(count: overrides.changedCount)
                Button("Reset all", role: .destructive) { confirmResetAll = true }
            }
            Button {
                Task { await store.reanalyzeTuned() }
            } label: {
                HStack {
                    Text("Re-analyse all sessions now")
                    if store.isBusy { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(store.isBusy || store.sessions.isEmpty)
        } footer: {
            Text("Sessions re-derive themselves whenever a threshold moves — the tuning is "
                 + "part of the analysis' version, so a stale session rebuilds the next time "
                 + "it is opened, and the whole library rebuilds at the next launch. The "
                 + "button is the same trip, taken now.")
        }
    }

    /// **The workbench's one entry point outside a session** (docs/presentation.md, "Dev
    /// workbench"). It belongs here rather than in Settings proper because it is the answer to
    /// the question this page asks: a slider says what a threshold *is*, and this says whether
    /// moving it brought the engine closer to what the rider saw.
    private var labelsSection: some View {
        Section {
            NavigationLink {
                TuningLabelsView()
            } label: {
                LabeledContent("Labels") {
                    Text(labels.totalLabels == 0
                         ? "none yet"
                         : "\(labels.totalLabels) turn"
                            + "\(labels.totalLabels == 1 ? "" : "s")")
                }
            }
        } footer: {
            Text("Your own verdict on a turn — *I flew · I touched · I fell* — left on the "
                 + "turn's page and scored against the engine here. Labels live on this phone, "
                 + "outside the analysis, and survive every re-derivation.")
        }
    }

    private var footerSection: some View {
        Section {
            LabeledContent("Analysis engine", value: AnalysisEngine.version)
            if let fingerprint = overrides.fingerprint {
                LabeledContent("Tuning fingerprint", value: fingerprint)
                    .font(.caption.monospaced())
            }
        } header: {
            Text("Beta · testing tool")
        } footer: {
            Text("These sliders override the published defaults **on this phone only**. They "
                 + "change every number the app shows — foil time, flights, turn counts, "
                 + "scores, outcomes, records and trends — so a session analysed with them is "
                 + "not comparable with one analysed anywhere else.\n\n"
                 + "The watch and the web are not touched: the watch computes live with no "
                 + "way to be told, and the web reads what the phone wrote. While anything "
                 + "here is moved, the session header, Records and Trends carry a *tuned "
                 + "thresholds* chip, and a session's own page says how many thresholds "
                 + "were moved — so a tuned number can never be mistaken for a published one.")
        }
    }

    // MARK: - One parameter

    /// Name · value · unit on the first line, the slider under it, "default N · what it does"
    /// in the caption, and a reset that appears only once the row has something to reset.
    ///
    /// The row is named in the rider's words (`spec.title`), with the parameter's
    /// docs/algorithms.md name printed small under it: the page has to read on its own (Jan,
    /// 7 Sep 2026: "review all descriptions on the tuning page for clarity") *and* line up
    /// with that table for whoever is changing the number the table names.
    private func row(_ parameter: TuningParameter) -> some View {
        let spec = parameter.spec
        let value = overrides.value(for: parameter)
        let overridden = overrides.isOverridden(parameter)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                heading(spec, parameter: parameter, overridden: overridden)
                Spacer(minLength: 8)
                // A switch carries its state in the control itself; printing "on" beside a
                // control that already says on is one reading of the same fact too many.
                if spec.kind == .slider {
                    Text(spec.formatted(value))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(overridden ? Color.accentColor : Color.secondary)
                }
                if overridden {
                    Button {
                        overrides.reset(parameter)
                        commit()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset \(spec.title)")
                }
            }
            control(spec, parameter: parameter)
            Text("default \(spec.formatted(spec.defaultValue)) · \(spec.note)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// The row's name in the rider's words, with the docs/algorithms.md name small under it —
    /// the same two lines whether the control below is a slider or a switch.
    private func heading(_ spec: TuningParameterSpec, parameter: TuningParameter,
                         overridden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(spec.title)
                .font(.subheadline.weight(overridden ? .semibold : .regular))
                .fixedSize(horizontal: false, vertical: true)
            Text(parameter.rawValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    /// **A slider for a quantity, a switch for a rule** (`TuningKind`). The stored value is a
    /// `Double` either way — the override map, the fingerprint and the reset never learn there
    /// are two kinds — so the split lives here and nowhere else.
    @ViewBuilder
    private func control(_ spec: TuningParameterSpec,
                         parameter: TuningParameter) -> some View {
        switch spec.kind {
        case .toggle:
            Toggle(isOn: Binding(
                get: { spec.isOn(overrides.value(for: parameter)) },
                set: { isOn in
                    overrides[parameter] = isOn ? 1 : 0
                    commit()
                })) {
                    Text(spec.title)
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(spec.title)
        case .slider:
            Slider(value: Binding(
                get: { overrides.value(for: parameter) },
                set: { newValue in
                    overrides[parameter] = newValue
                    commit()
                }),
                   in: spec.range, step: spec.step) {
                Text(spec.title)
            } minimumValueLabel: {
                Text(spec.format(spec.range.lowerBound)).font(.caption2).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text(spec.format(spec.range.upperBound)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// Written through on every change rather than on leaving: a page that loses a slider drag
    /// because the app was backgrounded mid-tune is a page nobody trusts twice.
    private func commit() {
        store.tuning = overrides
        touched = true
    }
}

/// "tuned thresholds · N" — the mark that follows a tuned number everywhere it is shown.
///
/// One capsule, one wording, one place: the session header next to the discipline badge, the
/// Records and Trends headers, and the session page's banner line. It is not a warning — a
/// tuned analysis is not wrong, it is measured against different thresholds — so it is a
/// neutral chip and not a red one; what it may never be is absent.
struct TunedChip: View {
    /// How many thresholds stand away from their published default.
    let count: Int
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "slider.horizontal.3").font(.caption2)
            Text(compact ? "tuned · \(count)" : "tuned thresholds · \(count)")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.16), in: .capsule)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysed with \(count) tuned threshold"
                            + "\(count == 1 ? "" : "s")")
    }
}

#endif
