# Editing rules without touching JSON

This document describes the rule editor from
[#9](https://github.com/trsdn/OpenZonr/issues/9): what it can do, why it is
built the way it is, where it deviates from the issue — and, separately,
what is measured and what is not.

## Two tiers

The starting pain point is one sentence: "Outlook should always open in
Zone 2." Nobody needs an editor for that sentence, which is why there are
two tiers.

**The 90-percent case** is a menu item: **„Aktuelles Fenster festhalten“**
("Pin current window"). The user drags the window to where it belongs and
clicks the entry. In the background, a rule is created, along with a role
and a binding in the active profile if needed. None of these three terms
ever appears. Feedback is a single sentence in the menu, something like
„Regel „Safari → Mitte“ angelegt, Priorität 10.“ ("Rule 'Safari → Mitte'
created, priority 10.").

**The editor** is for the rest: three areas in one window — Regeln (Rules),
Rollen & Profile (Roles & Profiles), Zonen (Zones).

## Deviation from the issue: no right-click on the window

The issue describes the 90-percent case as a **right-click on a placed
window**. That is not achievable with public APIs, for two independent
reasons:

1. A context menu inside another app's window would have to hook into that
   app's own event handling. macOS offers no supported way to add a menu
   entry to another process; the Accessibility API can read and move
   windows, but cannot contribute menus.
2. The workaround would be a transparent window over all screens that
   intercepts right-clicks. It would swallow clicks meant for the app
   underneath, and would need a Screen Recording permission in addition to
   the Accessibility grant.

The chosen approach yields the same result with the same input — this app,
this location — and costs one extra mouse movement. The reasoning is also
present as a comment in the source
(`Sources/OpenZonrMac/Accessibility/FrontmostWindow.swift`), so it doesn't
have to be hunted down when reading the code.

## Where the logic lives

The entire editing logic lives as **pure functions** in `OpenZonrCore`
(`Sources/OpenZonrCore/Editing/`), not in the interface. That is not a
matter of style but the condition for this part being provable at all: the
Accessibility grant cannot be automated, whereas loading, changing,
validating, writing, and reloading a configuration can be, completely.

| File | Responsibility |
|---|---|
| `ConfigurationEditing.swift` | All changes to the configuration as `Configuration -> Configuration` |
| `QuickPin.swift` | The 90-percent case: app + target become a rule, role, and binding |
| `PinTargetResolver.swift` | Geometry for "here": window frame → screen + zone |
| `FindingIndex.swift` | Makes validation findings addressable by `ConfigurationPath` |
| `Identifiers.swift` | Readable, collision-free identifiers from German names |

The interface (`Sources/OpenZonrApp/Editor/`) only calls these functions
and writes exclusively through `ConfigurationStore.save(_:to:)` —
atomically and with migration. There is no second write path.

## Decisions that aren't obvious

### The list is the truth, not its image

The engine evaluates rules by `priority` descending, and by file order in
case of a tie. The editor shows exactly this order. When a rule is moved,
priorities are **reassigned** in steps of 10 — otherwise the list would
show an order the engine does not actually follow.

Merely opening the file explicitly does **not** trigger this. Opening a
window must not produce a diff.

### Deletion is deliberately asymmetric

When a **role** is deleted, its bindings disappear along with it — the
validator does not check a binding to an unknown role; it would just be
dead weight. The **rules** that name that role remain: for that there is
the check `unknownRoleInRule`, which shows the user exactly the rules that
now need a decision. Likewise, bindings to a deleted **zone** remain and
produce `unknownZoneInBinding`.

In short: what can vanish silently is deleted; what gets reported stays.

### Priority when pinning

Competition consists of all **enabled** rules **without a title pattern**
that could match the same app. The new rule gets their highest priority +
10; with no competition, 10.

Rules **with** a title pattern do not count. A hand-written rule like
"Outlook window with title `^Verfassen`" is more specific than "Outlook,"
and it should keep its precedence. Rules for other apps don't count
either, so the numbers don't grow with every use.

### Pinning twice reassigns instead of duplicating

An existing rule is reused when it matches **exclusively** via the bundle
identifier — no title pattern, no roles, no sizes, no aspect ratio. That is
the shape this function writes itself. If it was disabled, it gets
re-enabled: answering „hier festhalten“ ("pin here") on a disabled rule
with "nothing happens" would be a silent failure.

A rule the user has refined by hand is never overwritten.

**And it rises, when it would otherwise stay shadowed.** A review turned up
the finding that reassignment left the priority untouched. If a catch-all
rule with a higher priority was added after the first pin, the pinned rule
was shadowed and never fired — the user read „zeigt jetzt auf Zone 2“
("now points to Zone 2"), but the window kept opening elsewhere. The same
happened when re-enabling a disabled rule. When reassigning, the priority
is therefore raised whenever a competing rule sits at the same level or
higher.

A tie deliberately counts as competition: at equal priority, file order
decides, and the user can neither see nor influence that through a menu
entry. Without competition, the number stays unchanged — otherwise it
would grow by 10 with every click.

### The quick command validates too

The menu entry initially bypassed `ConfigurationDocument` straight into the
store when the editor window was closed — so the most common case ran
through the one unvalidated path and still reported success. It now
**always** runs through a document; if the editor is closed, that document
is a short-lived one.

Unlike the editor, the quick command has no field to attach a finding to:
it says one sentence and disappears. So it must be able to refuse.
`QuickPin.objection(to:report:)` decides that, in the core rather than the
interface — which makes the refusal provable without an Accessibility
grant. Exactly two things trigger an objection: any error anywhere, and a
`shadowedRule` warning on exactly this rule. Refusing on every warning
would make the feature unusable.

### Errors are attached to their field

`ConfigurationValidator` delivers every finding with a `ConfigurationPath`
and a severity. `FindingIndex` indexes them by **path components**, not by
rendered strings — `rules[a]` is a character prefix of `rules[ab]`, but a
different rule. This way the message sits under the field it concerns, and
the row in the list carries a badge for everything contained within it.

There is one exception: the uniqueness checks report by **position**
(`rules[2].id`), because with two identical identifiers, the identifier is
precisely what cannot address one of them. No field claims such findings.
They therefore sit in a narrow bar above the save row — determined via
`findings(notUnder:)`, not maintained by hand, so that no finding stays
invisible.

### Zones are dragged, not typed

Zones are fractions of the visible area. That is the right model and the
wrong input field: `0.5 / 0 / 0.5 / 1` is a statement about the right half
that no one reads as such. The editor shows a thumbnail of the screen with
the zones as rectangles.

On release, it snaps to **twelfths** and clamps into the unit square.
Twelfths, because halves, thirds, and quarters all fall on that grid — so
the usual divisions line up without gaps. A two-pixel gap between two zones
is invisible in the editor and very visible on the screen. The numeric
fields remain alongside, for cases where a zone must match exactly a zone
on a different screen.

The thumbnail's aspect ratio is **no longer fixed at 16:10**. If the screen
belonging to the alias currently being edited is connected, the ratio comes
from its **visible frame** (`visibleFrame`, not `frame`) — because zones
are resolved against the visible area anyway (`DefaultZoneResolver`). If
the screen isn't currently present, 16:10 remains the placeholder — but the
preview then visibly shows **„Bildschirm nicht angeschlossen,
Seitenverhältnis geschätzt“** ("Screen not connected, aspect ratio
estimated"). An unlabeled estimate that looks like a measurement was the
bug class from [#18](https://github.com/trsdn/OpenZonr/issues/18): an
ultrawide with a 3.81:1 ratio was drawn as 1.6:1, `left-quarter` looked
like a narrow column and was in truth nearly square. The choice of "real
dimensions or estimate" lives as the pure function
`canvasAspect(for:snapshots:)` in `OpenZonrCore/Display/`, and is therefore
testable without a connected screen.

As long as real dimensions are available, the zone form shows the
corresponding point measurement next to each fraction — `0.25` becomes
`≙ 1280 pt`. With an estimate, that addition is omitted: an estimated
point figure next to a stored number would claim more than it can support.

## What is measured and what is not

| Claim | Status |
|---|---|
| `swift build` and `swift test` are green | **measured** — 281 tests in 31 suites, headless (most recently 274 in 30) |
| The editing functions do what they should | **measured** — 51 new tests in 4 suites, including ordering, deletion semantics, identifier uniqueness |
| The preview aspect ratio comes from `visibleFrame` when the screen is present | **measured** — 7 tests on `canvasAspect(for:snapshots:)` against an ultrawide fixture (5120×1344), including cross-checks "not `frame`", "wrong screen connected ≠ silent substitute", and "a directly constructed `NaN` value is forced to `.estimated`" |
| **Whether the preview then actually matches the real screen** | **not measured** — the arithmetic is checked, the picture needs a hand on the mouse |
| A reassigned rule wins against a catch-all rule added later | **measured** — cross-checked against `DefaultRuleEngine`, with the bug deliberately reproduced beforehand (see below) |
| The quick command refuses instead of promising an effect that doesn't happen | **measured** — 4 tests on `QuickPin.objection(to:report:)`, headless |
| **Whether the quick command actually refuses at the real menu** | **not measured** — what is checked is the decision, not its display; what's missing is a hand on the mouse, no longer the permission as of 29.08.2026 |
| `PinTargetResolver` is the inverse of `DefaultZoneResolver` | **measured** — round-trip test against the real resolver, not against hand-computed numbers |
| The 90-percent case creates a rule that the engine actually selects | **measured** — cross-checked against `DefaultRuleEngine` in the test and against the real configuration, see below |
| Round trip against the user's **real** configuration | **measured** — on a copy, original unchanged; numbers below |
| Findings land on the right field | **measured** — `FindingIndex` against real validator output, including the case "a finding that no field claims" |
| **Whether the editor is usable on screen** | **not measured** — reasoning below |
| **Whether „Aktuelles Fenster festhalten“ works on a real window** | **not measured** — reasoning below |
| **Whether a dragged zone sits correctly on the real screen** | **not measured** — same reasoning |

### The reproduced bug

A green test proves little if it would also be green without the fix. For
the finding from the review, the fix in `QuickPin` was therefore
temporarily disabled once. Result, before it came back:

```
✘ Eine umgehängte Regel steigt über eine dazugekommene Auffangregel
    (rule.priority → 10) > 500
    (after?.id → catch-all) == (outcome.rule → editor-rule)
    (shadowed → [warning shadowedRule at rules[editor-rule]:
     Die Regel editor-rule wird vollständig von Regel catch-all überdeckt.])
✘ Auch bei Gleichstand steigt die umgehängte Regel
✘ Eine wiedereingeschaltete Regel, die überdeckt war, greift danach wirklich
```

The third line is the crux: `RuleHygieneCheck` knew about the finding the
whole time; it just was never raised on this path.

### The measured round trip

A throwaway program against a **copy** of
`~/Library/Application Support/OpenZonr/config.json`, without any
permission granted:

```
1 geladen: 2 Regeln, 2 Rollen, 1 Profile, 2 Displays
2 Validierung vorher: 0 Befunde, nutzbar=true
3 Ziel: Profil Schreibtisch, Display c49rg9x, Zone center-half (Mitte)
4 QuickPin: Regel „Safari → Mitte“ angelegt, Priorität 10. |
  Regel=safari Rolle=mail neueRolle=false wiederverwendet=false
5 Validierung nachher: 0 Befunde, nutzbar=true
  Befunde an rules[safari]: 0
6 zurückgelesen: identisch=true, Regeln=3
7 Regelauswahl für Safari: safari
8 Bindung: mail → c49rg9x/center-half
9 Quelle unverändert: true
```

Notable is line 4: `neueRolle=false`. The role `mail` already pointed to
exactly this zone in the „Schreibtisch“ ("Desk") profile, so it was reused
instead of creating a second role for the same spot. Line 7 is the actual
cross-check — the engine really does select, for a Safari window, the rule
that was created.

### Why the interface was not re-measured

> **Partially superseded on 29.08.2026.** The Accessibility grant has been
> given, and the app reads windows — established in
> [docs/tracer-bullet.md](tracer-bullet.md). The original blocking reason
> therefore **no longer applies**. What remains is a different, smaller
> one: opening the menu, pressing the button, dragging a zone — that
> requires a hand on the mouse, not a permission. Anyone reading this
> section and looking in System Settings for a missing checkbox will
> search in vain. The checklist at the end is unchanged and valid, and now
> **executable**.

The original reason was the same as in
[docs/menueleisten-app.md](menueleisten-app.md): the user has to grant the
Accessibility permission for `~/Applications/OpenZonr.app` by hand, and the
„Bedienungshilfen“ ("Accessibility") pane of System Settings delivers
neither an accessibility tree nor a screenshot — both stay black. That has
been checked and is not something you can work around.

Without this grant, the app reads not a single window. That means
„Aktuelles Fenster festhalten“ ("Pin current window") cannot be triggered,
and the effect of a dragged zone cannot be checked on the real screen. The
editor itself could be opened, but without loaded windows that would be a
half-measurement that suggests more than it shows.

Verification is therefore deliberately placed where it is complete without
the grant: in the pure layer underneath. What lies between `QuickPin` and
the pixel on screen — reading Accessibility, rotating the frame, setting
the window — is the chain from [docs/tracer-bullet.md](tracer-bullet.md),
and it is measured there against a real window.

What would be the first thing to check after granting permission:

1. Open the menu, bring a Safari window to the front, „Aktuelles Fenster
   festhalten“ ("Pin current window") — does the expected message appear,
   is the rule in the file?
2. Quit and restart Safari — does the window land in the zone?
3. Drag a zone in the editor, save, restart the app — does the window sit
   in the new spot?

These steps must be run from the bundle that was granted permission —
`~/Applications/OpenZonr.app`, built via `Scripts/bundle.sh`. Not from
`swift run`: the grant binds to the bundle at its path, and an unsigned
rebuild gets a new checksum and is no longer recognized. The checkbox
would stay checked and be ineffective — that is measured in
[docs/menueleisten-app.md](menueleisten-app.md). Anyone who overlooks this
measures nothing for an hour and mistakes it for a bug in the editor.

## Boundary with #10

The zone editor draws zones and lets you drag them. That is **not** the
dropzone feature from
[#10](https://github.com/trsdn/OpenZonr/issues/10): that one is about
dragging a window with the mouse into a displayed zone. Here, only the
configuration is edited; no window is moved and nothing is displayed.
Nothing about #10 was preempted.

**Addendum:** #10 has since been built — [dropzones.md](dropzones.md). It
continues to use `QuickPin` from this issue unchanged: the offer „Diese App
immer hier öffnen?“ ("Always open this app here?") after a drop routes its
rule through the same `QuickPin.Request` that the „Aktuelles Fenster
festhalten“ menu item also produces. This means there is still exactly one
path from a window to a rule.

## Dry-run line and overview (from #19)

[Issue #19](https://github.com/trsdn/OpenZonr/issues/19) added two things: a
line that tells an edited rule what would currently happen, and an overview
that shows which app lands in which zone — without having to mentally
assemble the chain rule → role → binding → zone. Both are built, with a
different evidentiary basis for each.

### The line in the rule editor

Below every selected rule sits a line with either an arrow icon (a
measurement) or a question mark (a conditional statement). The text comes
from `DryRunPreviewFormatter.line(for:subject:configuration:)` in
`OpenZonrCore/Placement/`, the evaluation itself from
`DryRunPreview.evaluate(...)`. Both are pure, testable headless, and are
covered by `Tests/OpenZonrCoreTests/DryRunPreview{,Formatter}Tests.swift`.

The two cases are deliberately kept separate:

- **A window of the app is open** — the line is a **measurement**. The
  snapshot is run through the same chain that placement itself uses
  (`DefaultWindowFilter` → `CompiledRuleSet` → `DefaultRuleEngine` →
  `DefaultZoneResolver`). The line names zone, screen, rule name, priority,
  and target frame in points.
- **The app is not running** — the line is **conditional**. It names the
  rule and role, and below it sits a small list headed „Nicht geprüft — die
  Regel prüft es, aber es steht erst am offenen Fenster fest:“ ("Not
  checked — the rule checks it, but it is only determined once the window
  is open:") with the criteria that cannot be decided without a window. In
  the real, existing configuration, all three rules check the bundle
  exclusively; the list is then empty, but the statement is still marked
  conditional whenever window title, role, sizes, aspect ratio, or "only
  first window" could influence the selection.

The real value lies in `RuleCriteria.report(for:defaults:)` — the function
that looks at a `WindowMatch` together with the global defaults and
determines which criteria are *decidable* and which are *undecidable*. It
is the reason this statement stays honest: a naive dry run would be
accidentally exact in today's configuration and would quietly turn wrong
the moment someone adds the first title rule or size condition. The line in
the editor names exactly this "quietly wrong" — and that is therefore the
crux of the addendum from the issue comment.

The editor's only Accessibility read happens here: the editor queries
`WindowInventory.allWindows(bundleIdentifier:)` to distinguish case A from
case B. The call is limited to the one currently selected rule and does not
happen while idle.

### The „Wohin geht was?“ ("Where does what go?") overview

As the first tab in the editor (before Regeln (Rules), Rollen & Profile
(Roles & Profiles), Zonen (Zones)) sits a picture of every screen in the
selected profile, each in its own aspect ratio. Inside each zone are the
rules that land there — cutting across the profile's bindings.

This immediately makes visible:

- Zones that *nothing* points to are drawn and carry the label „keine Regel
  zeigt hierher“ ("no rule points here"). In the real, existing
  configuration, this affects e.g. `u28e590-full`; without the overview,
  that was visible only by looking at the configuration itself, and even
  then only if someone traced the chain all the way there.
- The profile's fallback zone is labeled „(Auffang)“ ("(fallback)") — you
  can see at a glance whether unrecognized windows land in the same zone as
  a named rule (in today's configuration, the fallback shares its zone with
  the TextEdit rule).
- Disabled rules appear with a strikethrough in their name: they are
  present but have no effect. Leaving them out would mean showing a
  configuration that doesn't actually exist.

The mapping itself is a pure function, `PlacementOverview.build(for:
configuration:)`, and is measured in
`Tests/OpenZonrCoreTests/PlacementOverviewTests.swift`.

### What was deliberately not built here

- **Dragging an app label into a different zone.** That would reach into
  the rule or role binding, and into the very zone editor that a parallel
  session is working on. The boundary was kept. Without it, the overview is
  a *picture*, not an editor — which needs to be called out in the PR.
- **Spatial arrangement (left/right/top/bottom) in the picture.** The
  overview shows the screens *side by side*, each in its own *ratio*, with
  a note „Nicht gemessen: die räumliche Anordnung“ ("Not measured: the
  spatial arrangement"). The reason: the real arrangement would come from
  the AppKit frames of the `DisplaySnapshot`s and would have to be mapped
  onto a picture. That mapping lives in `Sources/OpenZonrCore/Geometry/`,
  which is the responsibility of a parallel session (issue #21). For this
  feature, the *rule-to-zone* question is the more pressing one; the
  spatial arrangement can be added later without reworking the file.

### Not measured

- How the tab looks on screen with four screens and three profiles — which
  zones become too small for their label and how SwiftUI wraps text in
  cramped rectangles. Without a hand on the mouse, this cannot be
  established; the file therefore contains no UI test target for this tab.
- Whether the question-mark marker for the conditional dry-run line reads
  better on screen than an alternative symbol. The choice follows the
  pattern of the editor's other `Image(systemName:)` calls, not a
  measurement.
- The behavior for a configuration without a profile (no fallback, no
  bindings) is implemented as a „kein Layout beschrieben“ ("no layout
  described") message, but unverified on screen.
