# Review checklist — the patterns behind Jan's feedback

Jan, 16 September 2026: every piece of feedback is checked for the pattern behind it, and a
round ends with the patterns named, not only the cases fixed. This file is the list so far.
Every agent that reviews or changes a rider-facing surface (app, watch, site, stores) runs it
before reporting; a finding names the pattern letter. Two of the patterns are lints
(`docs/copy/check_voice.py` for C, `docs/copy/check_duplicates.py` for F); the rest are read.

| | pattern | the rule | how to check |
|---|---|---|---|
| **A** | A title narrower or wider than its content | A title names what the screen does. | List every screen and page title beside its sections. "What the numbers mean" over ten sections, "Get started with the beta" over App Store routes: both were this. |
| **B** | A page describes an action instead of offering it | Where a text names an action, the control is there. | Grep help bodies and footers for "Menu →", "Settings →", "Import →"; each gets a HelpAction or a link. |
| **C** | Facts that go stale by construction | No date, build or version number in rider text unless a generator writes it. | `check_voice.py` fails them; generated spans carry `data-copy`; dated release notes are the one page marked `dated`. |
| **D** | Channel-blind kit text | Any text that lists doors takes the channel that asks. | A test per channel for every list of doors (getting started, the beta list, the class topic, import footers). |
| **E** | Rules argued from absence | State that must survive a launch is a positive flag; visibility never depends on "has done X before". | Grep `if store.has…`, `hasSeen`, `hasImported…` around rider-facing rows and screens. |
| **F** | Redundancy inside one product | One sentence, one home — in the app as on the site. | `check_duplicates.py` over the Swift literals; `web/tools/verify_unique.py` over the pages. |
| **G** | Affordances that do not show | Every control says what it does and, when off, why; interactive things look interactive. | Grep `.disabled(` without a footer; folds without a label; switches hidden by state (E). |
| **H** | Bare codes the rider must decode | No code without its word within reach. | Route letters, class letters, P/S, a bare rate name, a symbol without a caption — each has its word on the same screen. |
| **I** | Paragraphs ungoverned by the sentence rules | A rider paragraph is at most 40 words; a Settings or Import footer 25; a help summary 20. | `check_voice.py`, strict since the second voice pass; the summary and the body in `HelpBudgetTests`. Split, never compress. **The web is inside it since 19 September 2026:** on a page a paragraph is the block the author typed — `<p>`, `<li>`, `<dd>`, `<figcaption>`, `<summary>`, a table cell, cut again at every `<br>` — and the rider sentences `web/js/*.js` writes at run time are read the same way. |
| **J** | One thing, two orders | The ways in have one order everywhere (docs/guide/getting-started.json): Garmin, Apple Watch, Apple's Workout app, any .fit, Strava; the Garmin ZIP last. | Import, the empty library, Getting started, /start, /watches, Settings sections. |
| **K** | Footers explain the mechanism | A footer says what you get in one line; the how is a help link. | Every Settings and Import footer. |
| **L** | Two taxonomies for one concept | One taxonomy per concept; an extra dimension is a column, never a new letter. | Routes vs classes; class B+ vs "live on the wrist". |
| **M** | App-wide furniture on one tab | App-wide doors (menu, Settings, Help, feedback) sit on every tab in the same place. | The four tab roots share one toolbar item. |

How a round ends: the reply names the patterns of the round in one line each, the rule it
becomes, and where it is enforced; the next work order puts the pattern fixes first so the
single cases fall out of them.
