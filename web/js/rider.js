/* "Whose session is this?" — the one question the file cannot answer.
 *
 * A .fit that reaches this page can be a friend's: the iOS app scrubs the identifiers out
 * of anything it shares, so a recording sent over a chat is identity-free by design and
 * attribution is the receiver's to state. Nothing in the bytes says who rode it, and
 * nothing could.
 *
 * Getting it wrong is not cosmetic. An unattributed friend's session joins the all-time
 * records and every trend line, and a fast afternoon of his becomes a personal best of the
 * reader's that no later correction can un-set. So the question is asked on the way IN —
 * on the Save press, before anything is written — rather than offered as an edit
 * afterwards, and "Mine", the true answer nearly every time, is the preselected one tap.
 *
 * Not `window.prompt`: a native prompt is a bare text field with no default, no way to
 * offer the names already in the library, and no way to say what answering costs. This is
 * a <dialog> (app/index.html, styles in css/style.css) using the app's own controls, and
 * `showModal()` gives the focus trap, the backdrop and the Escape key for free.
 *
 * Escape / Cancel resolves to null and saves NOTHING. There is no safe default for "whose
 * is it" once the page can be handed a stranger's file — the same call the iOS import
 * sheet makes (ios/…/RiderPromptView.swift).
 */

import { esc } from "./render.js";

const el = (id) => document.getElementById(id);

/**
 * Ask, and resolve with `{ rider }` — `rider: null` for "Mine", a trimmed name for a
 * friend's — or with `null` if the question was dismissed.
 *
 * `known` are the names already in the library (`library.knownRiders`). Offering them is
 * what makes the second file from the same friend land on the same spelling as the first,
 * which in turn is what makes "the distinct rider values" a sufficient address book.
 */
export function askRider({ fileName = "", known = [], initial = null } = {}) {
  const dialog = el("rider-dialog");
  const name = el("rider-name");
  const friendBox = el("rider-friend");
  const knownBox = el("rider-known");
  const save = el("rider-save");
  const buttons = [...dialog.querySelectorAll(".seg-btn")];

  el("rider-file").textContent = fileName;
  name.value = initial || "";
  renderKnown(knownBox, known, name.value);

  // Re-opened for a friend's second file: the prompt starts where the entry it replaces
  // left off, so confirming a replacement cannot silently promote it into the records.
  let friend = Boolean(initial);
  const setWho = (isFriend, focus) => {
    friend = isFriend;
    for (const b of buttons) b.setAttribute("aria-pressed", String((b.dataset.who === "friend") === isFriend));
    friendBox.hidden = !isFriend;
    validate();
    // The text field is the only thing left to do once "A friend's" is picked; making the
    // rider tap it as well is a step for nothing.
    if (isFriend && focus) name.focus();
  };
  const validate = () => {
    // A friend with no name would be a badge with nothing in it.
    save.disabled = friend && !name.value.trim();
  };

  setWho(friend, false);

  return new Promise((resolve) => {
    const done = (value) => {
      dialog.removeEventListener("close", onClose);
      dialog.removeEventListener("click", onClick);
      name.removeEventListener("input", onInput);
      knownBox.removeEventListener("click", onKnown);
      if (dialog.open) dialog.close();
      resolve(value);
    };
    // Covers Escape, the Cancel button and a click on the backdrop: every way out of the
    // dialog that is not the Save button means nothing was answered, so nothing is saved.
    const onClose = () => done(dialog.returnValue === "save"
      ? { rider: friend ? name.value.trim() : null }
      : null);
    const onClick = (ev) => {
      const seg = ev.target.closest(".seg-btn");
      if (seg) { setWho(seg.dataset.who === "friend", true); return; }
      // Cancel is a plain button rather than a second submit, so that Enter in the name
      // field submits *Save* — the implicit-submission target is the first submit button
      // in the form, and a Cancel that answered the Return key would be a trap.
      if (ev.target.closest("#rider-cancel") || ev.target === dialog) dialog.close("");
    };
    const onInput = () => { validate(); markKnown(knownBox, name.value); };
    const onKnown = (ev) => {
      const chip = ev.target.closest("button[data-rider]");
      if (!chip) return;
      name.value = chip.dataset.rider;
      onInput();
      name.focus();
    };

    dialog.addEventListener("close", onClose);
    dialog.addEventListener("click", onClick);
    name.addEventListener("input", onInput);
    knownBox.addEventListener("click", onKnown);
    dialog.returnValue = "";
    dialog.showModal();
  });
}

function renderKnown(host, known, current) {
  const names = [...new Set(known.filter(Boolean))];
  host.hidden = names.length === 0;
  host.innerHTML = names.map((n) =>
    `<button type="button" class="lib-tag rider" data-rider="${esc(n)}">${esc(n)}</button>`).join("");
  markKnown(host, current);
}

/** The chip for the name currently typed reads as chosen — the same one-of-these state the
 *  segmented control has, so the two controls do not disagree about what is selected. */
function markKnown(host, current) {
  const value = String(current || "").trim();
  for (const chip of host.querySelectorAll("button[data-rider]")) {
    chip.classList.toggle("on", chip.dataset.rider === value);
  }
}
