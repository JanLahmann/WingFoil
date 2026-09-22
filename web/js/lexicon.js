/**
 * **One lexicon per discipline** — the web's copy of `DisciplineLexicon.swift`
 * (docs/presentation/labels.md, "Discipline lexicon"; docs/algorithms/disciplines.md, "Disciplines").
 *
 * A windsurfer on a fin does not fly and has no foil to lose. Every word here is a word the
 * engine has no opinion about — the numbers, the verdicts and the layer names are identical,
 * and only their spelling changes — so the swap lives in presentation and nowhere near the
 * analyzer.
 *
 * **The wingfoil column is byte-identical to what the page has always said.** `wingfoil` is
 * the default of every function that takes a discipline, so a surface that has not been
 * taught about disciplines prints exactly what it printed before.
 *
 * Deliberately *not* translated: the turn vocabulary. A jibe is a jibe, a tack is a tack,
 * and *flew through* / *clean* / *dry* / *wrist under* mean the same thing on either rig.
 *
 * The web has no per-session settings place to hang an override on, so a session's preset is
 * whatever its `discipline` developer field said — `meta.analysedAs`, written by
 * `web_entry.analyze_bytes`, which is the engine's own statement about how it ran.
 */

const WINGFOIL = {
  discipline: "wingfoil",
  experimental: false,
  pumping: true,
  flying: "flying",
  foilTime: "Foil time",
  foilTimeLower: "foil time",
  onFoil: "On foil",
  onFoilLower: "on foil",
  takeoff: "Takeoff",
  takeoffLower: "takeoff",
  takeoffs: "Takeoffs",
  lostTheFoil: "lost the foil",
  offTheFoil: "off the foil",
  chip: null,
};

const WINDSURF = {
  experimental: true,
  pumping: false,
  flying: "planing",
  foilTime: "Planing time",
  foilTimeLower: "planing time",
  onFoil: "Planing",
  onFoilLower: "planing",
  takeoff: "Planing start",
  takeoffLower: "planing start",
  takeoffs: "Planing starts",
  lostTheFoil: "stopped planing",
  offTheFoil: "off the plane",
  chip: "windsurf · experimental",
};

const TABLE = {
  wingfoil: WINGFOIL,
  windsurfFoil: { ...WINDSURF, discipline: "windsurfFoil" },
  windsurfFin: { ...WINDSURF, discipline: "windsurfFin" },
};

/** The words for a preset name, or the wingfoil column for anything unrecognised. */
export function lexicon(discipline) {
  return TABLE[discipline] || WINGFOIL;
}

/** The rider's word for a preset — the badge, and the "analysed as" line. */
export function disciplineTitle(discipline) {
  return { wingfoil: "Wingfoil", windsurfFoil: "Windsurf foil",
           windsurfFin: "Windsurf fin" }[discipline] || "Wingfoil";
}

/** The whole disclaimer, in the voice, byte for byte what the phone's footnote carries.
    The kit is the author: Presentation/DisciplineLexicon.swift, `experimentalNote`. */
export const EXPERIMENTAL_NOTE =
  "Experimental. Windsurf analysis is untested. Jibes and tacks work. "
  + "Pumping is off and planing thresholds are provisional. "
  + "Send feedback on what you see.";
