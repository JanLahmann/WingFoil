/* **Send one session to the developer** — the browser's half of the phone's Share page
 * door (Jan, 21 September 2026; ios/WingFoil/Features/Share/SendToDeveloperSheet.swift).
 *
 * A rider who thinks a number is wrong can only be answered on the recording that produced
 * it. This puts that recording, his note and what the browser knows about the run into one
 * place: a share sheet where the platform has one, a download plus a prefilled mail where
 * it does not.
 *
 * **Nothing here uploads.** There is no CleanJibe server and this file opens no connection.
 * `navigator.share` is the operating system's sheet and the rider picks what it goes to;
 * the fallback writes a file to his own downloads folder and opens his own mail client with
 * the text already in it. Both routes end with him pressing send, or not.
 *
 * WHICH ROUTE, PER BROWSER. `navigator.canShare({files})` is the only honest test — the
 * feature is per browser *and* per file type, and a `navigator.share` that exists without
 * file support throws rather than degrading:
 *
 *   * Safari on iOS and macOS, and Chrome/Edge on Android and Windows: the share sheet
 *     carries the file, and the note rides as the sheet's text.
 *   * Firefox everywhere, and Chrome on Linux: no file sharing. The recording downloads and
 *     a `mailto:` opens with the same body, which then says to attach the file by hand.
 *     No mail URL scheme can carry an attachment, so saying so is the whole of it.
 *   * A browser with no `navigator.share` at all takes the same fallback.
 */

import { getFitBlob } from "./store.js";

/** Where a report goes. The kit's `FeedbackReport.recipient`, and the one address on the
 *  site (web/tools/verify_copy.py pins the footers that print it). */
export const RECIPIENT = "info@cleanjibe.org";

/** What the comment field asks. `SessionAnalysisMail.prompt` in the kit, word for word:
 *  the two shells ask one question. */
export const PROMPT = "What looks wrong? Which turns or times?";

/** What the rider is agreeing to. `SessionAnalysisMail.consent` in the kit. */
export const CONSENT =
  "The file holds your track, your heart rate and your times. "
  + "It is used only to improve the detection. It is never published.";

/** "CleanJibe session 30 August 2026 — for analysis", the kit's subject. */
export function subject(dateLine) {
  return `CleanJibe session ${dateLine || ""} — for analysis`;
}

/**
 * The mail body: the rider's note, the consent sentence, then the fact sheet behind a rule
 * that says what it is and that it may be deleted — the shape both of the phone's prefilled
 * mails have (`FeedbackReport.Separator`).
 *
 * `facts` is `{ engine, source, date, duration, distance, tally, wind, file }`, each
 * already a display string, because a mail that spelled a number differently from the page
 * it is about would be describing a different session as far as the reader is concerned.
 */
export function body({ comment, facts, attached }) {
  const lines = ["What looks wrong:", (comment || "").trim(), "", CONSENT, "",
                 "-".repeat(40),
                 "Below is what the browser knows about this session and run. "
                 + "It helps analysis. Delete any line you would rather not send.", ""];
  lines.push("App");
  lines.push(`  CleanJibe in the browser${facts.site ? " " + facts.site : ""}`);
  lines.push(`  Analysis engine ${facts.engine || "unknown"}`);
  lines.push("");
  lines.push("Session");
  for (const [label, value] of [["", facts.date], ["Source class", facts.source],
                                ["Duration", facts.duration],
                                ["Distance", facts.distance],
                                ["Jibes", facts.tally], ["Wind", facts.wind]]) {
    if (value) lines.push("  " + (label ? label + " " : "") + value);
  }
  lines.push("");
  lines.push("Attached");
  lines.push("  " + (facts.file || "the recording"));
  lines.push(attached
    ? "  The original recording, as it was imported."
    : "  Attach the file CleanJibe just downloaded. A mail link cannot carry it.");
  lines.push("");
  lines.push("sent from CleanJibe");
  return lines.join("\n");
}

/** Does this browser share files at all? Asked about the real file, because the answer is
 *  per type as well as per browser. */
export function canShareFile(file) {
  return Boolean(navigator.canShare && navigator.canShare({ files: [file] }));
}

/**
 * Sends, by whichever route this browser has. Resolves with `"shared"`, `"mail"` or
 * `"cancelled"` so the caller can say what happened rather than guess.
 *
 * `bytes` is the recording as it was dropped. It comes from the page when the session is
 * the one just analysed, and out of storage when it was opened from the library — the same
 * two places "Download analysis JSON" reads.
 */
export async function send({ id, bytes, filename, comment, facts }) {
  let blob = bytes ? new Blob([bytes], { type: "application/octet-stream" }) : null;
  if (!blob && id) blob = await getFitBlob(id).catch(() => null);

  const name = filename || "session.fit";
  const file = blob
    ? new File([blob], name, { type: "application/octet-stream" })
    : null;

  if (file && canShareFile(file)) {
    try {
      await navigator.share({ files: [file], title: subject(facts.date),
                              text: body({ comment, facts, attached: true }) });
      return "shared";
    } catch (err) {
      // A rider who closed the sheet has not failed at anything, and must not be handed a
      // second route he did not ask for.
      if (err && err.name === "AbortError") return "cancelled";
    }
  }

  if (blob) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }
  const text = body({ comment, facts, attached: false });
  location.href = `mailto:${RECIPIENT}?subject=${encodeURIComponent(subject(facts.date))}`
    + `&body=${encodeURIComponent(text)}`;
  return "mail";
}
