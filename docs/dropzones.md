# Dropzones — Dragging Windows into Zones with the Mouse

The half that was assumed from the start. The project began with the
sentence: *"Could you build a window manager that has dropzones like most
others do — but what bugs me is that a newly opened app doesn't land in the
zone automatically."* Only the second part had been built so far. This is
the first.

Implemented in issue #10, then extended in issue #23. In short:

- While dragging a window with **⌘** held down, the zones of the active
  profile appear on the display under the pointer; the zone the pointer is
  over is highlighted.
- On release, the window is placed into that zone — **through the same
  code path as the automatic placement**, not through a second path.
- Releasing on a zone's **pin badge** additionally writes a rule via the
  existing `QuickPin`, in the same motion. Releasing elsewhere remains a
  one-off placement.
- The old prompt „Diese App immer hier öffnen?" ("Always open this app
  here?") is **off** by default; anyone who wants it turns on
  `defaults.dropzones.offerRule`.
- The activation rule `defaults.dropzones.activation` has two forms: the
  default `{"showsWhile": "command"}` — zones appear only with ⌘ held — and
  the older `{"showsUnless": "option"}` — zones on every drag, ⌥ silences
  them. An existing `config.json` with `suppressionModifier: "option"`
  still loads and maps automatically to the older form (see *Migration*
  below).

---

---

## The switch to ⌘ as the enabler, measured

Since issue #23 the default has been: **the zones appear only while ⌘ is
held**, instead of "on every drag, except with ⌥". The reversal is
deliberate and has a cost, which is measured.

**Three runs on 2026-08-29:** A drag on the title bar of a background
window brings it to the front. **The same drag with ⌘ held leaves the
frontmost app in front.** ⌘ is therefore already in use on window drags,
and there it means *move without activating*.

Consequence: with ⌘ as the enabler, the zones appear exactly when
activation is *not* wanted — filing a background window away without
losing focus. But it also means the old gesture no longer exists *without*
the new one: anyone who just wants to drag a window without zones lighting
up doesn't press anything (that's now the normal case) — anyone who wants
to see the zones presses ⌘.

*Not measured:* whether ⌘-dragging actually **moves** a background window.
In no run did a background window move, not even without ⌘ — the
synthetic drag cannot answer that. What is established is only the
difference in activation.

*Also not measured:* whether holding ⌘ while dragging feels comfortable
and whether the pin badge is easy to find. That needs a hand on the mouse;
see the table "What is measured and what isn't" further below.

## Migrating existing configurations

A `config.json` written before issue #23 carries
`defaults.dropzones.suppressionModifier: "option"`. Without migration, a
user would be left after the update with the new default — zones appear
only with ⌘ — and would have no way to know that an unmodified second of
dragging now means exactly the *opposite* of what it meant yesterday.

The codec keeps reading the old key and maps it onto
`activation: {"showsUnless": "option"}` — the same polarity the old file
expressed. **Only the new key is written back.** Both names in the same
file would contradict each other the next time someone edits it by hand,
so the codec has to establish a precedence: it does (`activation` wins
over `suppressionModifier`), so that a hand-edited new file isn't
overridden by a leftover old field. `DropzoneSettingsDecodingTests`
records both cases.

## The pin badge — the rule set during the drag instead of a prompt afterward

As long as the zones are visible, every zone carries a small badge, top
right. Release normally: a one-off placement, no rule, no prompt. Release
on the badge: the same placement, and `QuickPin` writes the rule — in the
same motion.

Both the drop and the zoom-button menu place using `Dropzone.placement`
(with the layout margin subtracted, identical to the automatic placement,
#43); the hit test uses `Dropzone.activationFrame` — the **activation
area**, no longer necessarily the full zone. What that is and why is in
the next section.

The hit test is a **pure function** alongside `DropzoneMap`
(`DropzoneMap.pinBadgeFrame(for:)` and `DropzoneMap.isOnPinBadge(_:of:)`),
so it can be tested without the Accessibility permission — the same
separation that runs through the rest of the dropzones half. The code path
in the controller is two lines: if the pointer is on the badge at release,
a `QuickPin.Request` is built and applied directly through the
`DropRuleOffer.pin(...)` factory (no panel gate) — otherwise the existing
*offer-the-panel* branch, which stays silent by default.

**Why the badge sits top right and not in the center.** On a small zone, a
centered badge would cover the whole zone; the one-off placement
*without* a rule would become unreachable. The safety test
`theBadgeNeverSwallowsTheWholeZone` sweeps zone sizes from 60 to 4000
points and confirms that the center of every zone that gets a badge drawn
at all is never a badge hit. If a zone is too small for the badge plus a
remaining strip, no badge is drawn at all — then every drop is one-off,
without the controller needing to know a second path.

## Activation areas — two rectangles instead of one

Every zone has recently gained a second, optional rectangle:
`activationArea`. `frame` still says where the window ends up;
`activationArea` says where you have to release. If it's absent, it
defaults to the target frame — every configuration that doesn't know the
field behaves unchanged, and `Configuration.currentVersion` stays at `1`.

The reason for the split is a case that a single rectangle cannot solve,
and it isn't contrived — it sits on the maintainer's own machine. A layout
there (`C49RG9x`, 5120×1440) carries a full-height zone „Rechts außen"
("Right, full") with two half-height zones stacked on top of it, „Rechts
oben" ("Right, top") and „Rechts unten" ("Right, bottom"):

| Zone | rel. area |
|---|---|
| Rechts außen | 0.333 |
| Rechts oben | 0.167 |
| Rechts unten | 0.167 |

The hit test lets the smallest containing zone win — without that rule the
two halves would never be reachable, because „Rechts außen" contains every
one of their points too. But „Rechts oben" and „Rechts unten" between them
cover „Rechts außen" without a gap, and **that's exactly** what makes
„Rechts außen" unreachable: every point inside it also lies in one of the
two smaller zones. Not hard to hit — unreachable. No other rule fixes
this: as long as a rectangle is both the target frame and the trigger, the
points of a stack are indivisible, and whichever rule wins, the other
layer loses completely.

`activationArea` solves this by separating target from trigger: „Rechts
außen" gets its own activation area, independent of the two halves,
without its target frame changing. The JSON field is documented in
[konfiguration.md](konfiguration.md), section `activationArea`.

Two warnings belong to the check (`ZoneReachabilityCheck`), both warnings,
not errors — the configuration stays loadable:

- **Zone unreachable** — when the **union** of the preferred activation
  areas (smaller area wins, earlier zone ID on a tie) fully covers a zone.
  The maintainer's own case is exactly why this check exists as a test: no
  single half covers „Rechts außen", only both together — a check that
  only compared pairs would never have found it.
- **Activation area detached** — when a declared `activationArea` doesn't
  touch its own target frame at all. Allowed (see below), but more often a
  typo than intent.

The activation area doesn't have to lie inside the target frame — it's
screen-relative, not zone-relative. That makes **edge triggering
possible**: release at the screen edge, and the window lands in a distant
zone. Explicitly *possible*, not *tried*: so far nobody has released at
the screen edge and observed whether that holds up in use or hits what was
intended. The table "What is measured and what isn't" further below
carries no row for this — there's nothing to report yet, only the
possibility.

Since then the overlay draws in two parts: the activation areas of every
zone on the layout as a thin outline, so it's visible where you can aim,
and the target frame of the zone under the pointer filled in, so it's
visible where the window lands. The pin badge has likewise moved onto the
activation area instead of the target frame — consistent, since it's the
second target of the same mouse movement; with edge triggering it would
otherwise sit at the opposite end of the screen. One consequence that
isn't obvious by hand: an activation area whose shorter edge is under
`4·2 + 8·2 + 24 + 24 = 72` points no longer carries a badge (see above,
"The pin badge"). Placement still works there; the rule then has to be
created through the right-click menu.

## Right-click on the green button — menu instead of dragging (issue #27)

Some drags the user can skip entirely. A right-click on the green window
button opens its own menu naming the zones of the screen the window mostly
sits on. A click places the window once; ⌥ + click turns that into a rule
— through **the same `QuickPin`** as the menu-bar entry and the pin badge.
No second bookkeeping.

How it gets there:

- The existing `EventTapDragTracker` now also listens for
  `rightMouseDown`. A separate callback (`onRightClick`) passes the event
  through independently of the drag. It's the same tap, because two taps
  would require the same permission twice — pure duplication.
- **Important for the error class from #26/#29:** the AX query does *not*
  sit in the tap callback. `scheduleZoomButtonLookup` kicks it off in a
  `Task.detached`; only once the result is ready does the path jump back
  to the MainActor and call `onRightClick`. Otherwise both the AX query
  (spikes up to 970 ms) *and* the modal `NSMenu.popUp` would block exactly
  the thread that services the tap — with the same consequences that #29
  just closed.
- `ZoomButtonLookup.read(atAccessibilityPoint:primaryTopY:)` in
  `OpenZonrMac` determines the window and zoom-button frames.
  `nonisolated`, so it's allowed to run in the background task. Three
  outcomes: `found`, `zoomButtonUnavailable`, `noWindow` — each
  distinction is deliberate.
- `zoomButtonHitTest(point:zoomButtonFrame:)` in `OpenZonrCore` checks the
  geometry. A pure function, testable headless — a hit test that doesn't
  need the Accessibility permission was the requirement from the issue.
- `ZoomButtonMenu` in `OpenZonrApp` builds the `NSMenu` at the button
  position and routes the click through
  `WatchEngine.place(dropped:application:into:)` (one-off placement) and
  optionally through `AppModel.apply(_:to:)` (`QuickPin` writes the rule).

**Two pitfalls, named honestly (from the issue):**

- **`.listenOnly` can't swallow anything.** If an app does show its own
  menu on right-click at the zoom button, two appear. Measured are two
  apps (TextEdit, Safari) with no menu of their own, **not all of them**.
  A workaround (only react if briefly no foreign menu window appears) is
  only due once a counterexample is measured — not on suspicion.
- **`kAXZoomButtonAttribute` is missing on some windows.** While measuring
  for issue #27, a Finder window returned none. `ZoomButtonMenu` stays
  **silent** in that case: the attribute is missing for the whole window,
  not for one spot in it — the click was, for all practical purposes,
  almost certainly not meant for the button at all. A visible message here
  would speak up on *every* right-click for apps like Finder and would
  just be noise. The code still keeps the case as its own branch
  (`ZoomButtonLookup.Result.zoomButtonUnavailable`), so it can be reported
  later without restructuring, once a way is found to show it only when
  the click is plausibly near the button.

## What is deliberately not built — and why

Three obvious ways to set the rule *during the drag* were measured and
ruled out. Without this list, someone will build them again.

**Right-click on the title bar — collides.** Instrument: click and
detection in *one* program (a context menu can close between two
invocations), menu window detected via `CGWindowList` at layer 101.
Positive control passed, 3/3.

| Clicked where | App menu? | Runs |
|---|---|---|
| TextEdit — text area *(positive control)* | **yes**, 290×543 | 3/3 |
| TextEdit — empty title bar | no | 3/3 |
| TextEdit — title text / proxy icon | **yes**, 197×82 | 1/1 |
| TextEdit — green button, right-click | no | 1/1 |
| **Safari — unified toolbar, empty spot** | **yes**, 206×34 | 3/3 |
| Safari — same spot with ⌥ / ⌘ / ⇧ | **yes, every time** | 1 each |

In modern apps the title bar *is* the toolbar — Safari, Finder, Mail.
TextEdit was the exception, not the rule. Modifier keys don't suppress the
app menu.

**An active event tap to swallow the right-click — too expensive.**
`EventTapDragTracker.swift:74` creates the tap with `options: .listenOnly`;
it can't swallow anything. With `.defaultTap` it would work, but then
**every right-click on the machine** would run through our callback before
any app saw it. If it's too slow, macOS disables the tap — and drag
detection stops too, without it being noticed. Exactly the error class
this project otherwise hunts down.

**A panel under the green button — someone else's territory.** The button
can be located (measured: `AXButton … AXZoomWindow` at `3894,39 16×16`),
and a right-click on it shows no app menu. But macOS shows its own menu
there on *hover*. Two menus at the same pixel.

**Asking only after repeated occurrences** ("you've done this three times
now") — stretches out the annoyance instead of fixing it, and needs state
across sessions.

The actual answer instead is the pin badge: no new intervention in the
system, no collision with other apps, no active event tap.

---

## The two measured questions

### 1. `kAXMovedNotification` or `CGEventTap`?

Both paths are built (`AXMovedDragTracker`, `EventTapDragTracker`) and are
measured side by side by `openzonr dragprobe`. Three 3 s runs on the
user's machine, events generated synthetically (see below for why):

| Metric | `CGEventTap` | `kAXMovedNotification` |
|---|---|---|
| Setup | succeeds | succeeds |
| Permission | Accessibility | Accessibility — **the same one**, no extra permission |
| Received out of 40 sent | 40 (+ Down + Up = 42) | 40 |
| Loss | 0 of 40, in 3 of 3 runs | 0 of 40, in 3 of 3 runs |
| Rate | 44.3 / 50.3 / 53.7 per s | 52.6 / 52.5 / 50.8 per s |
| Largest gap | 55.7 / 38.1 / 39.2 ms | 39.9 / 37.1 / 38.5 ms |
| Release | **1 event per drag**, exact | **0** — detectable only by polling |
| Latency | not measurable (reasoning below) | fundamentally not measurable |

**The rate is the rate of the generator, not the upper bound of the
path.** The measurement driver emits one event per run-loop pass (timer,
8 ms). That both paths deliver, at around 50 events per second, exactly
what was sent, is the claim — not that 50 would be the maximum.

**The first version of this measurement was wrong, and that belongs
here.** It sent the 40 events in a `usleep` loop and then reported 753
events per second with a largest gap of 51.5 ms. Both were artifacts of a
queue that drained all at once after being blocked. Whoever blocks the
main thread while measuring the main thread is measuring the blocking.
That's why generation now runs through the run loop (`SyntheticDriver`).

**The decision was for `CGEventTap`, and specifically because of a single
row in the table: the release.** The tap reports it as an event.
Accessibility doesn't report it at all — there, the mouse button has to be
polled, 60 times per second, for as long as the drag lasts
(`AXMovedDragTracker.startPolling`). For a feature whose whole point is
the moment of release, that's the difference between measuring and
guessing. On top of that, Accessibility also reports movements that
aren't drags at all — other tools, the app itself, OpenZonr's own
placement — so the same polling is needed not just for the end but for
correctness.

The second path stays in the code. Not as a fallback in case the tap
stops working, but as a benchmark: if someone questions the decision
later, they can re-measure it instead of just reading about it.

### 2. Magnet

`com.crowdcafe.windowmagnet` runs on this machine. In
[`tracer-bullet.md`](tracer-bullet.md), Magnet was a measurement
disturbance; here it's a design problem, because both programs show an
overlay while dragging and listen to the same events.

**OpenZonr detects it and says so. Nothing more.**
`CompetingWindowManagers` knows 15 bundle identifiers, reports a match in
the menu, and distinguishes whether the other program also shows an
overlay while dragging (Magnet, Rectangle, BetterSnapTool …) or merely
uses the same API (AltTab, Bartender …). The former is a conflict over the
same gesture, the latter is just proximity.

Rejected were:

- **Fighting for supremacy** — setting the placement a second time on
  release, later than the other program. That's a race with no finish
  line: whoever writes last wins, and both programs can always get
  faster. The user would see a window that jumps after release.
- **Quitting Magnet** — not a window manager's job to close other
  programs.
- **Silently disabling itself** — then OpenZonr would do nothing while
  dragging, without saying why. Exactly the class of bug this project has
  already paid for three times.

The warning can be turned off via
`defaults.dropzones.warnAboutCompetingManagers`; it doesn't disable
dragging. That answers point 11 from
[`offene-fragen.md`](offene-fragen.md) for the drag case.

---

## What is measured and what isn't

| Item | Status | Reasoning |
|---|---|---|
| Pointer → display → zone mapping | **Proven**, headless | 10 tests in `DropzoneMapTests`, including the real 5120×1440 arrangement with a 1920×1080 display stacked above it |
| Overlapping zones: smaller wins | **Proven**, headless | without this rule, the halves under a focus zone would be unreachable by mouse |
| A shared edge belongs to exactly one zone | **Proven**, headless | left/bottom inclusive, right/top exclusive |
| Equal area → deterministic choice | **Proven**, headless | by display and zone identifier, never by array order |
| Zones stay visible in a gap | **Proven**, headless | the display decides, not the hit zone |
| Overlay decision (show/hide) | **Proven**, headless | `DropzoneOverlayPlanTests` |
| Suppression via ⌥ (`showsUnless` form) | **Proven**, headless | `DropzoneActivationTests`, including "⌘ does not suppress under `showsUnless(.option)`" |
| Enabling via ⌘ (`showsWhile` form, new default) | **Proven**, headless | `DropzoneActivationTests`; without ⌘, activation returns `awaitingModifier(.command)` with a German-language reason |
| Migration of old configurations (`suppressionModifier` → `showsUnless`) | **Proven**, headless | `DropzoneSettingsDecodingTests`, with a precedence rule for old and new keys present at once |
| Hit test on the pin badge | **Proven**, headless | `DropzonePinBadgeTests`, including the invariant "the badge never swallows the whole zone" across zone sizes from 60 to 4000 points |
| Hit test on the zoom button | **Proven**, headless | `ZoomButtonHitTests`; three-valued (`hit`/`missed`/`buttonUnavailable`), so a missing `AXZoomButton` isn't confused with "missed" |
| The badge path bypasses the `offerRule` switch | **Proven**, headless | `DropRuleOfferPinTests`; otherwise, with the panel switched off, every badge would silently do nothing |
| Minimum travel distance before showing | **Proven**, headless | prevents flicker on a mere click |
| Window drag vs. content drag (#37): classifier and state machine | **Proven**, headless | `WindowMoveEvidenceTests` (unchanged size and frame follows the pointer → `moved`; content drag, jitter, opposite direction, cross-axis shift → `notMoved`; edge drag → `resized`; boundary values of `minimumTravel` and size tolerance) and `EventTapDragTrackerTests` (`contentDragNeverBegins`, `evidenceArrivingLaterStillBegins`, `resizeAndUnreadableFrameDoNotBegin`, `stallWithinBudgetStillBegins`, `samplingStopsAfterBudget`, `budgetRestartsWithEachPress`, `samplerRunsOffMainThread`); tested with replayed frames, not with real apps |
| Presses that never become a `.began` report their reason | **Proven**, headless | `EventTapDragOutcomeTests`; `onOutcome` delivers `noWindowFound`, `noMovementEvidence(.budgetExhausted/.resizedInstead)`, `releasedBeforeEvidence` — at most once per press, never for an ordinary click, and without an AX call in the tap callback (#26) |
| Menu sentence for the outcome of a drag | **Proven**, headless | `DragOutcomeWordingTests`; every wording is tested individually, because a wrong sentence sends troubleshooting in the wrong direction |
| **Whether the zones appear with ⌘ on the maintainer's machine** | **Not measured** | The open bug. The "Last drag" line in the menu is the apparatus meant to collect the answer — it says which of the four spots it's stuck at. Until someone makes a drag with a hand on the mouse and reads off the sentence, nothing is measured. |
| Deriving drop → rule | **Proven**, headless | `DropRuleOfferTests`; dropping twice doesn't duplicate the rule |
| An old configuration without `dropzones` loads | **Proven**, headless | otherwise it wouldn't just be the key that's broken, but the whole file |
| Pausing also disables dragging | **Proven**, headless | `DropzoneActivator.suspension`; the decision lives in one place, not split between the controller and the menu text |
| No offer when the rule already points there | **Proven**, headless | `DropRuleOffer` asks `QuickPin` whether a yes would change anything; a test also covers the converse (different zone → it does ask) |
| Zone geometry identical to the rule path | **Proven**, headless | `ZoneGeometry` is the only conversion, a test compares both results |
| Event rate and loss of both paths | **Measured**, synthetic | three runs, table above; 0 of 40 lost |
| Release as an event vs. polling | **Measured** | the reason for the decision |
| Whether both paths can be set up | **Measured** | both succeed, both with the same permission |
| **Latency of an event** | **Not measured** | Even self-posted `CGEvent`s are only timestamped on delivery; the difference against `mach_absolute_time()` is not positive and is therefore reported as "not measurable" rather than as 0.0 ms. Accessibility notifications carry no timestamp at all — there, latency is fundamentally not measurable even with real drags. |
| **A real, hand-driven drag** | **Not measured** | The Accessibility permission for `~/Applications/OpenZonr.app` has been granted since 2026-08-29 — so that's **no longer** the reason. What's missing is a hand on the mouse: a drag can't be automated, and synthetic events only establish receipt, not usability. |
| **Overlay on screen** | **Not measured** | Drawing needs a visible window during a real drag — so the same hand, not the same permission. The *decision* of what gets drawn is tested; the drawing itself is deliberately kept thin. |
| **Behavior with Magnet running during a drag** | **Not measured** | Requires a real drag. Detection is tested; the behavior under conflict is designed and justified, not observed. |
| **Stability of the highlight on a zone edge** | **Not measured** | The mapping is unambiguous but stateless: right on an edge, the highlight flips with a single point of jitter. Whether that's disruptive in use and what dead zone would be right can't be judged without a real drag — so no hysteresis was built; instead point 13 in [`offene-fragen.md`](offene-fragen.md) was opened, along with the pitfall a first attempt at this has already run into. |
| **Placement after the drop** | **Not measured for the drop itself**, but for the same code | The drop calls `WatchEngine.place(dropped:application:into:)`, which uses the private `place(…)` with `rule: nil` — the same function whose placement is by now also measured against a running app in [`tracer-bullet.md`](tracer-bullet.md), including a case where Outlook resists the first write and a second attempt is needed. |
| **The offer panel in actual use** | **Not measured** | Appears only after a real drop. That it doesn't steal focus follows from `.nonactivatingPanel`; it isn't established by observation. Since issue #23 the default is *off* anyway — the path only remains because it's reliable without extra state. |
| **Discoverability of the pin badge** | **Not measured** | Whether a 24-point badge in a zone's top-right corner is understood in use as *hold here* — or whether it disappears unnoticed between title bars and window edges — needs a hand on the mouse and several users. What's checkable headless (does it sit in the corner, does it never cover the whole zone) is checked. |
| **Behavior of ⌘-dragging by hand** | **Not measured** | Whether it's comfortable to hold ⌘ for the duration of a drag, and whether the reversal "pressing nothing means no zones" feels right to the user, can't be judged without a real drag. What is measured is the cost: ⌘-dragging already doesn't bring background windows to the front today, and that side effect carries over. |
| **Duplicate menus at the green button** | **Not measured for all apps** | Measured are TextEdit and Safari (no app menu on right-click at the zoom button, positive control passed). For **all other apps** it is not measured. The tap is `.listenOnly` and can't swallow anything — if an app does show its own menu there, two appear. A workaround is only built once a counterexample is measured. |
| **Appearance and usability of the on-screen menu** | **Not measured** | Whether the `NSMenu` opens at the computed position, whether it shows the right zones, and whether the ⌥ modifier is read correctly at the moment of *click* needs a hand on the mouse — not checkable headless. Zone lookup and hit testing are tested headless; the AppKit display is not. |
| **Behavior on windows without `kAXZoomButton`** | **Measured for one Finder window** | A Finder window returned no `AXZoomButton`. The code separates the case (`ZoomButtonLookup.Result.zoomButtonUnavailable`) and handles it **silently**: the attribute is missing for the whole window, and every incidental right-click would otherwise produce a message. Whether **every** Finder window (and other AXScrollArea-like windows) behaves the same way is not measured. |
| **System hover menu with macOS window tiling enabled** | **Not measured** | On this machine `EnableTilingByEdgeDrag = 0`. Whether macOS window tiling's hover menu collides with the right-click menu (different gestures, but at the same pixel) needs a machine with tiling enabled and a positive control for the hover menu — both are missing. |
| **Window drag vs. content drag (#37) in real apps** | **Measured for TextEdit, Finder, Chrome, VS Code, Safari (synthetic events), otherwise Not measured** | In TextEdit, title-bar drags trigger `began` after 143 to 175 ms; text drags, drags at the window edge, and resizing at an edge or corner trigger nothing (table under "Manual check #37"). Title-bar drags with and without ⌘ trigger `began` in all five apps after 123 to 175 ms; content drags (including a file drag in Finder) trigger nothing. Not measured: Terminal (only the title-bar drag from 09-19), Xcode, text selection in real text, Ctrl+Cmd drag on window content, the screen edge and two displays, the overlay itself, and any hand-driven use. Apps that weren't tried are never carried as proven. |

In short: everything provable without a real drag is proven. Everything
that needs one is marked as unmeasured. The line between the two was the
actual design work.

> **As of 2026-08-29:** The Accessibility permission has been granted, and
> placement against a running app is measured
> ([`tracer-bullet.md`](tracer-bullet.md)). The remaining rows in this
> table now depend **no longer on a permission, but on a hand on the
> mouse**. Anyone who reads the rows otherwise and goes looking in System
> Settings for a missing checkbox will search in vain.

### Manual check #37

Unit tests establish the classifier and the state machine with replayed
frames. They don't establish how real apps report the AX frame during a
drag, nor that content gestures really leave the frame alone. Except for
the TextEdit rows below, this is **Not measured** and has to be worked
through by hand.

**Setup.** `swift build`, launch the app, Accessibility granted, dropzones
on. `openzonr dragprobe` confirms that the tap exists. Check activation in
both forms: the default `showsWhile(.command)` and the old form
`showsUnless(.option)`.

**Tunable parameters, in case a positive case fails.**
`WindowMoveEvidence.minimumTravel` (6 pt), `WindowMoveEvidence.minimumAlignment`
(0.5, cosine between window displacement and pointer travel), and
`EventTapDragTracker.frameSampleBudget` (2500 ms wall-clock from the first
frame query of a press, clock injectable). A failed positive probe is
tracked as a follow-up issue; the negative cases are not loosened in
exchange.

**Negative cases.** In each: no overlay, no placement, and no pinning on
release over a zone or badge.

1. Finder: drag a file out of a window onto a zone/badge; rubber-band
   select in icon view; the window's scroll bar.
2. TextEdit: select text over more than 3 pt and release over a zone; drag
   already-selected text; the vertical scroll bar.
3. Safari: select page text; drag a link; drag an image; the page's
   scroll bar, including on a long page.
4. Terminal: select text; drag the scroller.
5. Chrome: select page text; drag a link; scroll bar.
6. Preview or Xcode / VS Code (Electron, custom title bar): select text in
   the editor; drag the minimap or scroll bar.
7. Edge and corner drags to resize, in TextEdit and Safari (classifier:
   `resized`).

**Positive cases.** In each: overlay in the first moments of the drag,
placement on drop, pinning on drop over the badge.

1. Title-bar drag in TextEdit, Finder, Safari (native bar), Terminal.
2. An empty area of the Chrome/Safari toolbar that moves the window;
   Chrome tab drag on a window with a single tab.
3. VS Code and Xcode, custom title bar. Electron apps may report the frame
   late: note the delay until the overlay appears.
4. Window drag via modifier key: Ctrl+Cmd + drag on window content (system
   gesture), as well as the configured activation key on a title-bar drag
   (both forms, see setup).
5. Drag a window all the way to the top (menu-bar clamp) and across two
   displays: overlay stays, drop places.
6. **Clamped at the screen edge:** drag a window mostly straight up into
   the menu bar, with barely any horizontal movement. **Known limit, to be
   measured:** the classifier requires a cosine of at least 0.5 between
   window displacement and pointer travel. If the window stays put at the
   top while the pointer keeps moving, the value can drop below that and
   the evidence check fails. The outcome then is **no overlay; the window
   moves normally**. Whether and for which apps this happens is open.
7. Slow app (spinning beachball or sluggish AX): the overlay is allowed to
   come later, but neither the mouse nor the tap may freeze. In the log
   (`Log.detail`), the line „Ereignis-Tap wegen Timeout kurz abgeschaltet;
   Zug wird fortgesetzt." ("Event tap briefly disabled due to timeout;
   drag continues.") must not appear more often than before.

**Results.** Measured are TextEdit (2026-09-19), as well as Finder,
Chrome, VS Code, and Safari (2026-09-22); all other apps and cases remain
open. The measurements ran the real `EventTapDragTracker` against real
windows, but with **synthetic** mouse events (`CGEvent`, no human on the
mouse), without the app and without the overlay. So what's measured is the
tracker's events (`began`/`moved`/`ended`) and the window's AX frame
before and after the drag, not the drawing of the overlay. The "delay" is
the time from the first mouse movement to `began`.

Machine: macOS 26.6.2, display C49RG9x (5120×1440).

Measurement from 2026-09-22 (each with a new, empty window; a drag of
300 pt right and 60 pt down, 40 steps; each without and with ⌘ in the
events; the draggable spot on the title bar was located per app first
without ⌘):

| Case | App | Version | Result | Delay until `began` |
|---|---|---|---|---|
| Title bar without / with ⌘ | Finder | 26.4 | passed, `began`, `moved`, `ended` both times, window moved | 128 / 128 ms |
| Dragging file „Testdatei.txt" in the icon window, without / with ⌘ | Finder | 26.4 | passed, no events, window unchanged | – |
| Title bar without / with ⌘ | Chrome | 153.0.8010.53 | passed | 125 / 135 ms |
| Dragging the window center (blank page), without / with ⌘ | Chrome | 153.0.8010.53 | passed, no events | – |
| Title bar without / with ⌘ (custom title bar, Electron) | VS Code | 1.138.0 | passed | 136 / 139 ms |
| Dragging the window center (welcome page), without / with ⌘ | VS Code | 1.138.0 | passed, no events | – |
| Title bar without / with ⌘ (draggable spot at 15 % of width) | Safari | 26.6.2 | passed | 129 / 123 ms |
| Dragging the window center (start page), without / with ⌘ | Safari | 26.6.2 | passed, no events | – |

Dragging content in Chrome, VS Code, and Safari happened on blank pages,
not on selectable text; what's established is that a content drag in
which the window doesn't move never triggers `began`, not text selection
itself. The Terminal drag (09-19) was not repeated.

| Case (no.) | App | Version | Passed / not passed | Measured delay until `began` |
|---|---|---|---|---|
| Positive 1, title bar fast, 300 pt | TextEdit | 1.20 | passed (`began`, `moved`, `ended`, window moved) | 175 ms |
| Positive 1, title bar slow, 200 pt (30 ms per step) | TextEdit | 1.20 | passed | 153 ms |
| Positive 1, title bar purely vertical, 120 pt | TextEdit | 1.20 | passed | 143 ms |
| Positive 1, title bar short, 20 pt in about 80 ms | TextEdit | 1.20 | **not detected**: window moved, but no `began` | ends before the first frame response |
| Negative 2, select text, 300 pt | TextEdit | 1.20 | passed (no events, window unchanged) | – |
| Negative 2, drag vertically in text, 250 pt | TextEdit | 1.20 | passed (no events, window unchanged) | – |
| Negative 2, drag at the right window edge (7 pt from the edge), 200 pt | TextEdit | 1.20 | passed (no events, window unchanged); **whether a scroll bar was hit there is not checked** | – |
| Negative 7, corner drag bottom right, 80 pt | TextEdit | 1.20 | passed (no events, size changed) | – |
| Negative 7, edge drag right, 80 pt | TextEdit | 1.20 | passed (no events, size changed) | – |

The short, fast drag shows the flip side of the evidence check: it needs
an AX frame response, and here that takes about 140 to 175 ms. A
title-bar movement that ends before that offers no zones. For a dropzone
drag that's not critical, but it is a consequence of the "closed instead
of open" decision.

**Known limits.**

- If the AX frame isn't readable, the evidence check fails closed: no
  overlay, no drop (the "closed instead of open" decision).
- Edge and corner drags count as resizing and never offer zones.
- Apps whose windows only start moving after the time budget (2.5 s) are
  missed.
- Windows at the edge that only follow on one axis can fall below the
  direction threshold (positive case 6).
- All thresholds are rule-of-thumb values until the list has been worked
  through.

---

## Structure

```
Sources/OpenZonrCore/
  Placement/ZoneGeometry.swift        Zone → points. The only conversion.
  Dropzone/DropzoneMap.swift          Zones of the profile, zone under the pointer.
  Dropzone/DropzoneSettings.swift     Settings, modifier, activation.
  Dropzone/DropzoneOverlayPlan.swift  What the overlay should show.
  Dropzone/DropRuleOffer.swift        Drop → QuickPin.Request.
  Dropzone/ZoomButtonHit.swift        Hit test at the green button (issue #27).
  Dropzone/CompetingWindowManagers.swift
  Dropzone/WindowMoveEvidence.swift   Window drag or content drag? Pure classifier (#37).

Sources/OpenZonrMac/
  Dropzone/WindowDragTracker.swift    Shared types of both paths.
  Dropzone/EventTapDragTracker.swift  The chosen path. Since #27 also rightMouseDown.
  Dropzone/AXMovedDragTracker.swift   The comparison baseline.
  Dropzone/DragMeasurement.swift      The statistics of the measurement.
  Dropzone/ZoomButtonLookup.swift     AX query for window and zoom button.
  CommandLine/DragProbeCommand.swift  openzonr dragprobe.

Sources/OpenZonrApp/
  Dropzone/DropzoneController.swift   Wiring, nothing else.
  Dropzone/DropzoneOverlay.swift      A transparent window per display.
  Dropzone/DropOfferPanel.swift       „Immer hier öffnen?" ("Always open this app here?")
  Dropzone/ZoomButtonMenu.swift       Right-click menu at the green button.
```

This separation is the answer to the missing permission: nothing in
`OpenZonrCore` needs an event, and that's why everything there is
testable.

---

## Decisions that aren't obvious

**Pausing also stops dragging.** The menu item is called „Fenster
automatisch platzieren" ("Place windows automatically") (before the menu
rework: „Platzierung pausieren", "Pause placement"), and the log says, in
the off state, „es wird nichts mehr platziert" ("nothing is placed
anymore") — a drop that still places would make both statements a lie.
That an explicit mouse gesture keeps working while the automatic mode
rests would be defensible on its own; claiming both at once is not. The
usual reason to pause argues for the stricter variant: a second window
manager fighting back — exactly the situation in which a second overlay
while dragging is most disruptive. During the pause, the menu shows
„Ziehen ist nicht aktiv: Die Platzierung ist pausiert" ("Dragging is not
active: placement is paused"), and `WatchEngine.place(dropped:)`
additionally refuses on its own. Two locks, because the promise belongs to
the engine that makes it, not to a caller who has to remember it. This was
only decided during the review of PR #15; the first version kept
listening during the pause and said the opposite.

**It only asks when an answer would change something.** Whether a rule
already points at this zone is not decided by the offer itself but by
`QuickPin`: `DropRuleOffer.request` has it derive the configuration a yes
would produce, and stays silent when that's the configuration already
there. A separate comparison would be a second opinion about rules, and
two opinions drift apart. Without this check, dragging an already-pinned
app into its own zone would lead to the prompt, a yes into the retarget
branch, saving an unchanged file, and `Log.success` — a success message
with no effect. The same call also catches the case where the drop
couldn't produce a rule at all; then it never asks in the first place.

**An unreadable window frame is not invented.** `place(dropped:)`
originally substituted it with `0×0 at 0,0`, and that value traveled
unchanged into the rejection message as „Ist:" ("Current:") — a
measurement that was never actually measured. Now nothing is set, and the
message states that the frame wasn't readable.

**⌘ as the enabler, since issue #23.** The earlier default had ⌥ as the
*silence* key; zones appeared on every drag, and ⌥ suppressed them. The
new default is the reversal: press nothing → no zones, press ⌘ → zones.
The swap is deliberate — the cost is measured in the opening section —
and the old polarity lives on in `activation: {"showsUnless": "option"}`.
Anyone who wants can switch back. Migrating existing configurations
automatically maps the old `suppressionModifier` onto `showsUnless`;
without it, users would find their zones silently gone after the update,
for no apparent reason.

**Pin badge instead of a prompt.** The panel „Diese App immer hier
öffnen?" ("Always open this app here?") interrupts a gesture that has
just finished; the pin badge moves the decision to *before* the release.
The panel path remains (via the menu entry and a switch that can be
turned on), so no capability is lost that users might want to arrange
differently. The badge factory `DropRuleOffer.pin(...)` and the panel
path `DropRuleOffer.request(...)` build the same `QuickPin.Request` — two
entry points, one computation, no second kind of rule.

**The modifier is checked continuously, not just at the start of the
drag.** Anyone who presses ⌘ mid-drag means it. (With `showsWhile` the
overlay then appears; with `showsUnless` it disappears.)

**Only the display under the pointer.** On this desk, the main monitor is
5120 points wide. Lighting up all displays at once turns a drag into a
light show and obscures the very window it's about.

**The smallest containing zone wins.** The concept allows overlapping
zones. If the larger one won, the smaller ones would be unreachable by
mouse — the feature would be broken for exactly the layouts it exists
for.

**The offer names the zone.** „Diese App immer hier öffnen?" leaves open
what "here" has become with overlapping zones. A rule born from a
misunderstanding is worse than no rule.

**The offer is a `.nonactivatingPanel`, not an `NSAlert`.** An alert
activates the app and thereby takes focus away from the window that was
just placed — right after the user deliberately put it somewhere.

**A bug the tests found belongs here too.** `ModifierState` had an
overload `contains(_ modifier: DropzoneModifier)` that internally called
`contains(.shift)`. The compiler resolved that to the new overload instead
of `OptionSet.contains`: infinite recursion, a SIGBUS in every test that
touched the settings — and a crash that says nothing about the cause. The
method is now called `holds(_:)`, so the mistake can't happen again.

**No AX query in the tap callback, since issue #26.** The first bug
report from real use: the overlay appeared and was immediately gone
again, even though ⌘ was held. The cause was an
`AXUIElementCopyElementAtPosition` chain **inside** the `CGEventTap`
callback — median 0.3 – 76.7 ms, maximum 970 ms (measured 2026-08-30, four
points, five repeats each, four runs). macOS disabled the too-slow tap
with `kCGEventTapDisabledByTimeout`, the handler re-enabled it — and
reported `.cancelled`, which hid the overlay. The fix breaks this down
into three guarantees:

1. **The query runs outside the callback — and outside the main thread.**
   On `leftMouseDown`, the window lookup is kicked off as a
   `Task.detached`; the callback has long since returned by the time it
   runs, and the spike lands on a background thread instead of the run
   loop that services the tap. The maintainer re-measured that the AX
   query delivers the same result on a background thread as on the main
   thread (identical PIDs, three of three runs; equally fast once warmed
   up). What matters isn't the speed, but who the spike hits. Time passes
   anyway until the minimum travel distance is covered — by then the
   result is usually already in. If it isn't there yet, the tracker
   waits quietly; once it completes, it delivers `.began` after the fact.
2. **A timeout doesn't end the drag.** The tap is re-enabled, `dragging`
   and the press point are retained. The next `leftMouseDragged` keeps
   delivering `.moved`. Only `kCGEventTapDisabledByUserInput` — the real
   end of observation — ends the drag. And if the `mouseUp` itself was
   lost during the outage, that's reported cleanly on the next
   `mouseDown`, instead of getting stuck in the drag forever.
3. **An abort is no longer silent.** The controller sends the reason
   through `AppModel.reportPinFailure(…)` — the same channel as the menu
   paths — instead of hiding it only in `Log.detail`. If the overlay
   disappears, the user learns why.

The state machine is testable headless, because it sits behind an `Input`
enum and the lookup is injectable as a closure. The test that establishes
that a timeout does **not** end a running drag is
`EventTapDragTrackerTests.timeoutDoesNotCancelDrag`.

---

## Usage

Menu bar → „Zonen beim Ziehen" ("Zones while dragging"), three lines:
„Bei jedem Ziehen" ("On every drag"), „Nur mit gehaltener ⌘-Taste" ("Only
with ⌘ held"), „Aus" ("Off"). The choice writes
`defaults.dropzones.enabled` and `defaults.dropzones.activation` through
the same `ConfigurationDocument` as any other change, so it survives a
restart and shows up in the file the user edits. The checkmark reflects
the **effective** state from the loaded configuration; a hand-entered rule
that matches none of the three gets its own, checked line.

Turning off „Fenster automatisch platzieren" ("Place windows
automatically") switches off dragging with it — below the lines it then
reads „Ziehen ist nicht aktiv: Die Platzierung ist pausiert" ("Dragging is
not active: placement is paused"), so nobody presses expecting an overlay
that won't come.

Below that is a gray line about the most recently observed drag
(„Letzter Zug: keine Zonen — ⌘ war nicht gedrückt." — "Last drag: no
zones — ⌘ wasn't held."). It's a diagnostic for when the zones don't show
up, naming the point where things are stuck.

For configuration, see [`konfiguration.md`](konfiguration.md), section
`defaults.dropzones`.

Measuring:

```
openzonr dragprobe --seconds 5 --synthesize --out /tmp/dragprobe.txt
```

Without `--synthesize`, the command expects a window to be dragged by
hand during the measurement window. If both paths then show zero events,
nothing was measured — either the permission is missing or nothing was
dragged, and no number in the report carries any meaning. The report says
so itself.
