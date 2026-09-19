/* The install offer iOS Safari never makes for itself.
 *
 * Chrome's half of GitHub issue #9 is already answered, inline in app/index.html: Chrome
 * fires `beforeinstallprompt` exactly when an install is available, the page unhides the
 * bar it already has in its markup, and one tap installs. That is the browser volunteering
 * a fact, which is the only kind of install offer worth showing.
 *
 * iOS Safari volunteers nothing. There is no `beforeinstallprompt`, no programmatic
 * install, and no share target — Web Share Target is Android's, and an installed CleanJibe
 * on an iPhone does NOT appear in the iOS share sheet. So this file is a hint and not an
 * offer, and it is careful about which of the two it sounds like: it names the icon and the
 * offline start, and it says nothing about a share sheet, because on this platform there
 * would not be one.
 *
 * It builds its own node rather than asking app/index.html for markup. The Chrome bar is
 * that file's; this is one element appended once, in the same `.update-banner` shape, so
 * the two offers look like one thing and neither owns the other's HTML.
 *
 * WHO SEES IT: an iPhone or iPad running Safari, not already installed, who has not said
 * Later. Chrome and Firefox on iOS are WebKit too but cannot add to the home screen at all,
 * so they are excluded by the same touch-and-Safari test. A Mac is excluded by it as well,
 * which is right: "Add to Dock" is a different gesture with a different name.
 *
 * The iPhone app is a better answer than a home-screen icon for most of these riders, and
 * the page already says so in its own words and links to /invite/. This bar therefore does
 * not mention it: two invitations in one sentence is neither.
 */

const KEY = "cleanjibe.install.ios.dismissed";

/** Remembered "Later", behind try/catch: a preference that cannot be read is not a reason
 *  for a page to misbehave. A private window simply gets asked again. */
function remembered() {
  try { return localStorage.getItem(KEY) === "1"; } catch { return false; }
}
function remember() {
  try { localStorage.setItem(KEY, "1"); } catch { /* private window: ask again */ }
}

/**
 * iOS or iPadOS, in Safari, in a tab.
 *
 * `maxTouchPoints > 1` is what catches an iPad, which has called itself a Mac in its user
 * agent since iPadOS 13. `standalone` is Apple's own flag for "already on the home screen",
 * and `display-mode: standalone` covers the same for anything newer; either one means the
 * offer is already answered. Every other in-app browser on iOS (Chrome, Firefox, the ones
 * inside other apps) carries its own token in the UA and cannot install, so it is out.
 */
function installableOnIos() {
  const ua = navigator.userAgent;
  const iOS = /iPad|iPhone|iPod/.test(ua) ||
              (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  if (!iOS) return false;
  if (/CriOS|FxiOS|EdgiOS|OPiOS|GSA\//.test(ua)) return false;
  if (navigator.standalone === true) return false;
  if (matchMedia("(display-mode: standalone)").matches) return false;
  return true;
}

function bar() {
  const node = document.createElement("div");
  node.id = "install-ios";
  node.className = "update-banner";
  node.setAttribute("role", "status");

  const text = document.createElement("span");
  // Register 1. Three sentences, a verb in each, no dash and no parenthesis. The gesture is
  // named the way Safari names it, because the rider is about to look for those words.
  text.innerHTML = "<strong>Add CleanJibe to your home screen.</strong> " +
                   "It gets an icon and opens with no signal. " +
                   "Tap Share, then <em>Add to Home Screen</em>.";

  const actions = document.createElement("span");
  actions.className = "update-actions";
  const later = document.createElement("button");
  later.type = "button";
  later.className = "ghost";
  later.textContent = "Later";
  later.addEventListener("click", () => { node.remove(); remember(); });
  actions.append(later);

  node.append(text, actions);
  return node;
}

/* Last of the three banners, and under the topbar rather than over it. Prepending to the
   body put this one hint above the sticky header while Chrome's identical bar sat below
   it; sitting last also makes it the one that stands down when another banner is up
   (css/app.css, "one banner"). */
if (installableOnIos() && !remembered()) {
  const after = document.getElementById("install-banner");
  if (after) after.after(bar());
  else document.body.prepend(bar());
}
