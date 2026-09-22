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
///
/// **One page, three sets** (13 Sep 2026, Jan: *"for the windsurf analysis, we need to be able
/// to set other parameters (min planing speed, etc) than for wingfoil. Is that possible on the
/// settings/details page?"*). The picker at the top says which rig is being tuned, and every
/// row below it — its value, its "default N" caption, its reset, the count in the chip — is
/// about that rig alone. A fin board planes at 20 km/h where a foil flies at 12, so a single
/// `foilEntrySpeed` slider was always wrong for one of them; and because each set is its own
/// staleness key, moving a fin threshold re-derives fin sessions and nothing else.
struct TuningView: View {
    @Environment(SessionStore.self) private var store

    /// Seeded by the caller, because the page has to open on the rider's current settings and
    /// a view cannot read the environment in `init`.
    @State private var sets: TuningOverrideSets
    /// Which rig the rows below are about. Wingfoil, always, on the way in: it is the
    /// validated one, and a page that opened on a windsurf set would be a page claiming the
    /// windsurf numbers are the ones to argue with.
    @State private var selected: Discipline = Self.initialDiscipline

    /// `UI_TUNING_DISCIPLINE=windsurfFin` — screenshot hook only (docs/testing.md), and
    /// dev-build-only by construction, since this whole file is behind `TUNING`. A segmented
    /// control is a tap `simctl` cannot make, so the one state the picker reaches is staged
    /// from the environment the same way `UI_HELP_TOPIC` stages a help topic.
    private static var initialDiscipline: Discipline {
        ProcessInfo.processInfo.environment["UI_TUNING_DISCIPLINE"]
            .flatMap(Discipline.init(rawValue:)) ?? .wingfoil
    }
    /// Whether anything moved while the page was open. What decides if leaving it is worth a
    /// re-analysis — the lazy sweep would get there on its own at the next launch, but a rider
    /// tuning thresholds is a rider who wants to see the effect now.
    @State private var touched = false
    @State private var confirmResetAll = false
    /// Read here only for the row's count — the page itself lives in `TuningLabelsView`.
    @State private var labels = TurnLabelStore.shared

    init(initial: TuningOverrideSets) {
        _sets = State(initialValue: initial)
    }

    /// The set on screen. Every read below goes through it, so a row can never print one
    /// discipline's value under another one's caption.
    private var overrides: TuningOverrides { sets[selected] }

    var body: some View {
        Form {
            disciplineSection
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
        // Thirty sliders. A slider stretched to 950 pt is a slider whose thumb moves a
        // centimetre per degree; the column keeps it the size the numbers were chosen at.
        .readableColumn()
        .navigationTitle("Tuning")
        .navigationBarTitleDisplayMode(.inline)
        // The lazy path would pick this up at the next launch (`reanalyzeStale`, which the
        // fingerprint has just made true of every row). Doing it on the way out is the same
        // trip, taken while the rider is still thinking about the slider he moved.
        .onDisappear {
            let selected = selected
            guard touched else { return }
            // The workbench's cached default analyses were built against the previous setting.
            // The version key would catch this on its own once the library re-derives; dropping
            // them here means the next session opened cannot show a comparison from before the
            // slider moved even for the instant between the two.
            DevWorkbench.shared.invalidateAll()
            guard !store.sessions.isEmpty else { return }
            Task { await store.reanalyzeTuned(for: selected) }
        }
        .confirmationDialog("Reset every " + selected.title.lowercased()
                            + " threshold to its default?",
                            isPresented: $confirmResetAll, titleVisibility: .visible) {
            Button("Reset \(overrides.changedCount) threshold"
                   + "\(overrides.changedCount == 1 ? "" : "s")", role: .destructive) {
                sets.resetAll(selected)
                commit()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    /// **Which rig is being tuned.** A segmented picker rather than three pages, because the
    /// question a rider asks here is comparative — *what does the fin need that the wing does
    /// not* — and the answer is only readable if the same row sits in the same place under
    /// both. The page never jumps: every row is drawn for every discipline, and the ones a
    /// windsurf preset does not ask are disabled rather than removed.
    private var disciplineSection: some View {
        Section {
            Picker("Tuning for", selection: $selected) {
                ForEach(Discipline.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tuning for")
        } header: {
            Text("Tuning for")
        } footer: {
            Text(selectedFooter)
        }
    }

    /// What the set on screen stands against: its preset, in one line, and the other sets'
    /// counts where there are any — so a rider tuning the fin can see at a glance that the
    /// wing is carrying overrides of its own.
    private var selectedFooter: String {
        let name = selected.title.lowercased()
        var line = selected.isWindsurf
            ? "Each discipline has its own set of overrides, over its own preset. "
                + name + " starts above " + preset(.foilEntrySpeed)
                + " and ends below " + preset(.foilExitSpeed) + ". "
                + DisciplineLexicon.experimentalNote
            : "Each discipline has its own set of overrides, over its own preset. These rows "
                + "are the published wingfoil contract. It is the only validated one."
        let others = sets.tuned.filter { $0 != selected }
        if !others.isEmpty {
            line += "\n\nAlso tuned: "
                + others.map { $0.title.lowercased() + " · " + String(sets.changedCount($0)) }
                    .joined(separator: " · ")
                + ". Those sets are untouched by anything on this screen."
        }
        return line
    }

    private var statusSection: some View {
        Section {
            if overrides.isEmpty {
                Label("Every " + selected.title.lowercased()
                      + " threshold is at its preset default",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                TunedChip(count: overrides.changedCount)
                Button("Reset all \(selected.title.lowercased())", role: .destructive) {
                    confirmResetAll = true
                }
            }
            Button {
                Task { await store.reanalyzeTuned(for: selected) }
            } label: {
                HStack {
                    Text("Re-analyse stale sessions now")
                    if store.isBusy { Spacer(); ProgressView().controlSize(.small) }
                }
            }
            .disabled(store.isBusy || store.sessions.isEmpty)
        } footer: {
            let name = selected.title.lowercased()
            // Built in locals: one `+` chain long enough to carry the whole footer is what
            // the type checker gives up on inside a ViewBuilder.
            let rule = "Sessions re-derive whenever a threshold moves. The tuning is part "
                + "of the analysis' version.\n\n"
                + "A stale session rebuilds the next time you open it, and the rest at "
                + "the next launch.\n\n"
            let sweep = "The button takes that trip now. It sweeps every session whose "
                + "stored version is no longer the one its own discipline produces. "
            Text(rule + sweep + "After a move on this screen that is the "
                 + name + " sessions and no others.")
        }
    }

    /// **The workbench's one entry point outside a session** (docs/presentation/channels-tuning.md, "Dev
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
            Text(markdown: "Your own verdict on a turn: *I flew · I touched · I fell*.\n\n"
                 + "Leave it on the turn's page. It is scored against the engine "
                 + "here.\n\n"
                 + "Labels live on this phone, outside the analysis, and survive every "
                 + "re-derivation.")
        }
    }

    private var footerSection: some View {
        Section {
            LabeledContent("Analysis engine", value: AnalysisEngine.version)
            LabeledContent("Tuning set", value: selected.title)
            if let fingerprint = overrides.fingerprint {
                LabeledContent("Tuning fingerprint", value: fingerprint)
                    .font(.caption.monospaced())
            }
        } header: {
            Text("Beta · testing tool")
        } footer: {
            Text(markdown: "These sliders override the published defaults **on this "
                 + "phone only**.\n\n"
                 + "They change every number the app shows: foil time, flights, turn "
                 + "counts, scores, outcomes, records and trends.\n\n"
                 + "A session analysed with them is not comparable with one analysed "
                 + "anywhere else.\n\n"
                 + "The watch and the web are not touched.\n\n"
                 + "The watch computes live with no way to be told, and the web reads "
                 + "what the phone wrote.\n\n"
                 + "While anything here is moved, the session header, Records and Trends "
                 + "carry a *tuned thresholds* chip.\n\n"
                 + "A session's own page says how many thresholds were moved. A tuned "
                 + "number can never be mistaken for a published one.\n\n"
                 + "The fingerprint above is this discipline's set alone. It rides inside "
                 + "that discipline's stamp in the analysis' version.\n\n"
                 + "Moving a windsurf threshold therefore re-derives windsurf sessions. "
                 + "Every wingfoil session stays on the numbers it was analysed with.")
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
    ///
    /// **The caption says the selected discipline's default**, which is the preset's number
    /// and not always the published one: on the fin set the flight rows read "default 20.0
    /// km/h" and "default 15.0 km/h", because that is what the slider is standing away from
    /// and what dragging it home will clear it to.
    private func row(_ parameter: TuningParameter) -> some View {
        let spec = parameter.spec
        let value = overrides.value(for: parameter)
        let overridden = overrides.isOverridden(parameter)
        let available = spec.available(in: selected)
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
                        update { $0.reset(parameter) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Reset \(spec.title)")
                }
            }
            control(spec, parameter: parameter)
                .disabled(!available)
            Text(available
                 ? "default " + spec.formatted(spec.presetDefault(for: selected))
                    + " · " + spec.note
                 : "off for windsurf. There is no pump channel to corroborate against, so "
                    + "the rung is refused rather than merely unreachable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .opacity(available ? 1 : 0.55)
        .accessibilityElement(children: .contain)
    }

    /// One parameter's preset default, in the words the slider prints it in.
    private func preset(_ parameter: TuningParameter) -> String {
        parameter.spec.formatted(parameter.spec.presetDefault(for: selected))
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
                    update { $0[parameter] = isOn ? 1 : 0 }
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
                    update { $0[parameter] = newValue }
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

    /// **Every change to the set on screen goes through here**, so the selected discipline is
    /// read in exactly one place and a row can never write into another rig's set.
    private func update(_ change: (inout TuningOverrides) -> Void) {
        var set = sets[selected]
        change(&set)
        sets[selected] = set
        commit()
    }

    /// Written through on every change rather than on leaving: a page that loses a slider drag
    /// because the app was backgrounded mid-tune is a page nobody trusts twice.
    private func commit() {
        store.tuning = sets
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
        let noun = count == 1 ? " tuned threshold" : " tuned thresholds"
        return HStack(spacing: 4) {
            Image(systemName: "slider.horizontal.3").font(.caption2)
            Text(compact ? "tuned · " + String(count) : "tuned thresholds · " + String(count))
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.secondary.opacity(0.16), in: .capsule)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysed with " + String(count) + noun)
    }
}

#endif
