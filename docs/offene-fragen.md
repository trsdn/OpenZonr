# Open Questions

Decisions that were deliberately left open at the concept stage, along with
deviations from the originally discussed model. Each question lists the
options and, where one exists, a leaning.

Questions that practice has since answered carry the note *decided* or
*resolved* in the heading. They remain rather than being deleted — the
assumptions that turned out wrong are more instructive than the ones that
turned out right.

---

## 1. Spaces and Mission Control

**Question:** Do zones belong to a Space? What happens when the target zone
is on a different Space than the one the user is currently looking at?

The Accessibility API has no notion of Spaces. There is no official way to
place a window on a specific Space; the private `CGSSpace` functions are
undocumented and regularly break with macOS updates.

Options:

- **Ignore Spaces.** Windows are placed on the current Space. Simple, honest,
  but it cannot express "Outlook always on the second Space".
- **Space as part of the role binding**, implemented via private APIs.
  Powerful, but fragile and a permanent maintenance risk.
- **Simulate a Space switch** via keyboard shortcuts before placing. Visibly
  janky and hard to make robust.

*Leaning:* ignore Spaces for now and reassess only after roadmap stage 6.

**Directly affected:** the originally discussed "On the go" profile called
for "Communication = Builtin, full screen Space 2". Because Spaces remain
unsolved, the example `mobile` profile instead binds the role to the right
half of the built-in display. That is a deliberate deviation, not an
oversight.

---

## 2. Multiple windows of the same app

**Question:** What happens with the second, third, tenth window of the same
app?

The `onlyFirstWindowAfterLaunch` default setting solves the most common case
— it stops dialogs from being placed. But it doesn't answer what should
happen with a legitimate second main window, such as a second VS Code window
for a different project.

Options:

- **Place only the first window**, ignore all further ones. Current state.
- **Place all matching windows**, resolve conflicts via `occupiedZone`.
- **Secondary rule:** the second window goes to a different role (e.g.
  "Editor" → "Reference"). Expressive, but a significant extension of the
  rule model.

Related: should `share` kick in automatically when several windows want the
same zone — i.e. split a zone dynamically instead of stacking?

---

## 3. Full-screen apps

**Question:** Does a full-screen app on the target display suppress the
rule?

Placing a window into a zone on a display that a full-screen app currently
occupies is usually not what the user wants — the new window either
vanishes behind the full-screen window or tears it out of full-screen mode.

Options:

- Skip the rule, the window stays where it is.
- Place it anyway; the window then ends up on the Space underneath.
- Downgrade to `suggest` and let the user decide.

Closely tied to question 1: detecting full-screen state is also Space
territory.

---

## 4. Non-cooperative apps

**Question:** How hard should the tool push back when an app ignores or
overrides AX placement?

Java toolkits (AWT/Swing) and some Electron builds clamp the frame that was
set to their own notion of a valid window. The retry loop detects this via
`PlacementOutcome.rejectedByApplication`, but what then?

Options:

- **Give up and report it.** The user sees which app is refusing. Current
  state.
- **More aggressive retrying** with more attempts over a longer period.
  Risks visibly jumping windows.
- **Continuous monitoring** of the window via `kAXWindowMovedNotification`.
  Conflicts with the non-goal "no continuous monitoring" and violates the
  principle that the window belongs to the user once placed.
- **Maintain a bundled list of known problem apps** and send them straight
  to `suggest`.

---

## 5. Fingerprint matching for unknown setups

**Question:** Should there be a subset mode alongside the exact match?

Today the set of display identities is compared exactly. If an extra
projector shows up in the office, no profile matches and the user is asked.

Options:

- **Stay exact** and ask. Predictable, but tiresome for conference rooms and
  changing projectors.
- **Best subset**: the profile with the largest overlap wins, the unknown
  display stays unused. Convenient, but it places windows without explicit
  consent.
- **Displays can be marked "ignore"**, so they don't enter the fingerprint.
  A compromise, but it requires a one-time decision per display from the
  user.

---

## 6. Configuration storage location and migration — *decided*

**Question:** Where does the file belong?

**Decision:** the default location is
`~/Library/Application Support/OpenZonr/config.json`, with an override via
the `OPENZONR_CONFIG` environment variable and, taking precedence over that,
an explicit path passed in by the caller.

This serves both groups of users: anyone who never touches the file finds it
where Apple expects it, and anyone who versions their dotfiles puts it in
their own repository and sets one variable. The cost is a single environment
variable — considerably less than the argument a single enforced location
would keep generating. Implemented in `ConfigurationLocation`; the
resolution logic reads neither the environment nor the home directory
itself, both are passed in.

**Migration:** automatic on load, without asking, but never silently
destructive. An older `version` is stepped forward incrementally to
`Configuration.currentVersion`; before a *write* migration, the original
file is backed up next to it as `config.json.v<old version>.backup`. A
**newer** version is rejected outright rather than half-interpreted: a newer
schema may have moved fields, and a half-understood configuration places
windows where nobody wanted them.

Still open is explicit import/export in the interface.

---

## 7. Distribution and signing — *partially decided*

**The suspicion has been confirmed, and more starkly than expected.** The
Accessibility grant is tied to the code signature, and without it the tool
isn't merely inconvenient, it's unusable: `AXIsProcessTrusted()` reports
`true`, but every app returns nothing but `AXApplication`-role proxies for
`AXWindows`, and `AXPosition` fails with `-25205`. The checkbox in System
Settings stays checked and, after every rebuild, refers to a different
program.

**The development side is decided.** `Scripts/bundle.sh` builds, packages
and signs with a Developer ID. The designated requirement binds to
identifier and team rather than to the checksum:

```
designated => identifier "com.trsdn.openzonr" and anchor apple generic
  and certificate leaf[subject.OU] = <TEAM>
```

This means the grant usually survives a rebuild; that is not guaranteed
(issue #35, observed on 30.08.2026). An ad-hoc certificate is not enough —
it has no such chain.

**The path matters regardless.** A freshly built, identically signed bundle
in a new location is not granted — launched via LaunchServices it reports
"not trusted". The grant applies to the program at its location, not to the
identifier alone. `Scripts/bundle.sh` therefore places the bundle under
`~/Applications/OpenZonr.app` instead of in `.build`, where the first
cleanup would cost it.

Practical consequence for contributors: **without a Developer ID
certificate, meaningful work on placement is not possible.** The
computational half in `OpenZonrCore` stays testable headless; the
integration does not.

**Distribution to others remains open:**

- **Notarized direct distribution** (Developer ID) — the obvious path,
  requires the paid developer membership, which already exists here.
  Notarization is not yet set up.
- **App Store** — effectively ruled out: the Accessibility API is
  incompatible with the App Sandbox.
- **Self-built from source** — only works with your own certificate, see
  above.

Tied to this: whether and how an automatic update mechanism gets built.
Since the requirement binds to identifier and team, an update should not
cost the grant — that has not been checked yet.

---

## 8. Zone configuration and editor — *decided*

**Question:** How are zones actually drawn — free-form drawing, a grid with
snapping edges, bundled templates? And: should zone margins and gaps be
configurable?

**Decision: all three approaches at once, templates as the starting point.**
The editor ships templates for halves, thirds, quarters, 25/50/25 and
fifths; beyond that, it snaps to a twelfths grid that stays visible *during*
the gesture, and additionally snaps to the edges of neighbouring zones on
release. The grid's visibility is the point: since the prototype, a zone has
snapped to twelfths without anyone seeing it happen, and the rectangle would
jump on release for no apparent reason. Twelfths, because halves (6/12),
thirds (4/12) and quarters (3/12) all land exactly on it. On a 5120 px
window, a fifth is 1024 px; a third there is 1706 px — the two templates
cover two edge cases that raise the same rounding question.

Templates replace a layout's zones entirely. **Beforehand**, the app reports
which bindings would then point nowhere — the validation already reports
this case as
[`unknownZoneInBinding`](../Sources/OpenZonrCore/Validation/), but only
*after* applying it. `Configuration.previewApplying(template:…)` supplies
the preview beforehand, `applying(template:…)` carries out the change; both
are pure functions and proven headless (`LayoutTemplateTests.swift`).

Uncovered area is hatched in the canvas. Overlap is explicitly permitted per
`Zone.swift` (a large "focus" field spanning two halves) and must not be an
error. Uncovered area, by contrast, is nearly always an oversight and was
previously invisible; hatching instead of an error message — an
observation, not a claim. The computation lives in `LayoutCoverage` and is
proven against the same templates, for which it must yield exactly zero.

**On the gap question: no per-zone spacing, but a single margin value per
layout.** `Layout.margin` sits alongside `zones`; the default value of `0`
preserves prior behaviour, and the field is omissible when decoding and
encoding.

**And the actual rule, without which someone would build it plausibly and
wrong:**

- **When placing: subtract the margin.** `DefaultZoneResolver` shrinks the
  zone by `margin` on every side; the window gets its breathing room.
- **When hit-testing: don't.** `DropzoneMap.zones(in:…)` keeps computing
  with the unshrunk zones. Those tile the screen without gaps, every point
  belongs to exactly one zone, no flicker when dragging across a seam.

Anyone who subtracted the margin in both places would get the visually same
result and an overlay that flickers at every seam — and the connection
would be hard to find, because the windows are, after all, positioned
correctly. A test pins this down: a point exactly on the seam between two
zones with `margin > 0` still resolves to exactly one zone
(`DropzoneMapTests`), while the resolved window carries the margin as
breathing room (`ZoneResolverTests`).

**Rejected alternative — gaps per zone.** Two drawbacks weigh equally: the
number duplicates at every zone and drifts apart as soon as someone touches
a zone. But that weighs less than the second one: zones tile the screen
without gaps today, and the dropzones depend on that. With real gaps in the
model, the question *which zone is under the pointer* would only have an
answer where there is no gap — and dragging a window across a three-column
layout would produce highlight — nothing — highlight — nothing — highlight.
That hits exactly the spot that already wobbles under point 13: there, an
oversized dead zone; here, one nobody intended as such.

---

## 9. Virtual displays throw off the setup fingerprint — *decided*

**The finding.** On the author's setup, four displays report, but only two
are physical. "AAA" (presumably OBS) and "Teleprompter Source" are software
displays. They appear and disappear while nothing changes at the desk.

Under the original concept, this means **the fingerprint changes every
time**, the profile jumps, and windows land somewhere else — triggered by
someone starting OBS. That is not an edge case, it's a design flaw.

**Approaches considered:**

- **Check `CGDisplayIsOnline` / `CGDisplayIsAsleep`.** Doesn't help: virtual
  displays are online and awake.
- **Detect via physical size** (`CGDisplayScreenSize`). Tested and
  **disproven**: "AAA" reports 677.3 × 381.0 mm, "Teleprompter Source"
  478.1 × 268.9 mm — both entirely plausible monitor sizes. The common
  assumption that "virtual displays report 0 × 0" does not hold here.
- **Guess via implausible EDID identifiers** (`modelNumber <= 1`, serial
  number 0). Catches both cases, but is demonstrably unreliable: the *real*
  main monitor also reports serial number 0.
- **An explicit ignore list in the configuration.**

**Decision: an explicit `Configuration.ignoredDisplays` list.** Displays in
it don't enter the fingerprint. `openzonr displays` visibly flags suspected
cases with `virtuell?` (virtual?) and
`openzonr displays --config-fragment` suggests them as `ignoredDisplays`
entries — **the user has to decide.**

Rationale: any heuristic strong enough to catch both virtual displays would,
on other setups, also catch real monitors. A tool that silently drops a
connected screen from the profile is worse than one that asks for one line
of configuration. The heuristic therefore stays a *display*, never an
*action*.

**Newly raised:** the `virtuell?` marker is a guess and labelled as such.
Whether there is a reliable public API to distinguish the two remains open
— the obvious candidates have been disproven.

---

## 10. `AXIsProcessTrusted()` is not a reliable permission test — *resolved*

**The finding.** While building the tracer bullet, a state occurred that
the concept had not anticipated:

```
AXIsProcessTrusted()                                     → true
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)  → .success
  … delivers an element with role AXApplication, without position or size
AXObserverAddNotification(kAXWindowCreatedNotification)  → .success
  … and the notification is actually delivered
```

So the API consistently reports success, but no real windows come back.
Reproduced with `openzonr` **and** with an independently compiled probe
program in the same process context — it's not the tool.

**The cause is now largely understood, and the first guess wasn't wrong,
just incomplete.** The assumption was that the grant is tied to the
launching program (Terminal, editor, agent process). On top of that comes
the code signature: an unsigned binary gets a new checksum on every
rebuild, and TCC doesn't recognize it again. Both mechanisms act together,
and the degraded state is exactly their interplay — `AXIsProcessTrusted()`
inherits the trust of the launching terminal, window access does not. With
a granted, signed bundle, the same call returns 19 real `AXWindow` elements
with a readable frame. Details in question 7.

**Consequence for the implementation:** `openzonr` does not rely on
`AXIsProcessTrusted()`, but runs a real self-test
(`Accessibility.probeWindowAccess()`): does *any* app return an element
with role `AXWindow` **and** a readable frame? Only then does access count
as working. The three outcomes — granted, not trusted, degraded — each get
their own German-language walkthrough. Under `--dry-run`, "degraded" is
only a warning, so that configuration and profile selection can still be
checked.

**This self-test remains correct regardless.** The degraded state occurs
with every unsigned build, i.e. for every contributor without a
certificate. A tool that only checks `AXIsProcessTrusted()` would silently
do nothing there and give no indication of the reason.

**Addendum:** retry behaviour has since been measured. The first addendum
here read "both tested apps settle on the first write" — that held for two
cases where the window barely had to move. As soon as a window actually has
to travel across the screen, Outlook needs a second attempt; the retry loop
is load-bearing. See [tracer-bullet.md](tracer-bullet.md), "Verified:
placement while the app is running".

---

## 11. Competing window managers — *decided: detect and warn*

On the measurement machine, Magnet (`com.crowdcafe.windowmagnet`) runs in
parallel and places windows via the same Accessibility API.

Two consequences:

- **For measurement.** A discrepancy between the intended and actual frame
  in the retry log is not automatically the app's own resize. It can just
  as easily come from Magnet. Anyone who doesn't know this measures Magnet
  and mistakes the result for Outlook's. For clean measurements, quit
  competing tools temporarily.
- **For operation.** Two tools reacting to the same event can overwrite
  each other — in the worst case alternately, until one gives up. OpenZonr
  gives up after `RetryPolicy.maximumAttempts` and logs it; a tool without
  an upper bound would not.

**Decided together with the dropzones (#10), because there the measurement
disturbance turned into a design problem: Magnet and OpenZonr both showed
an overlay while dragging.** OpenZonr recognizes 15 common tools by their
bundle ID (`CompetingWindowManagers`), reports a match once in the menu,
and distinguishes whether the other tool also draws while dragging or
merely uses the same API. It doesn't fight: no re-setting position after
release, no quitting other programs, no silently switching itself off. The
warning can be turned off via
`defaults.dropzones.warnAboutCompetingManagers`; dragging itself is
unaffected. Rationale and rejected alternatives are in
[dropzones.md](dropzones.md).

---

## 12. Window layer as a filter criterion — *decided*

The concept stage filtered by subrole and minimum size. Measurement against
the real window landscape shows that isn't enough: the **Notification
Center is 5120 × 1440** in size and thereby passes any minimum-size check.
Only its window layer (21) distinguishes it from a real window.

**Decision:** `kCGWindowLayer == 0` is a **standalone, on-by-default and
non-optional** filter criterion — and it's the first one, ahead of subrole
and size. It is deliberately *not* an option in `WindowMatch`: a rule that
wants to place windows on layer 24 actually wants to move the menu bar.

---

## 13. No hysteresis at the zone edge — *open, deliberately left open*

`DropzoneOverlayPlan.plan(…)` decides the highlighted zone purely from the
current pointer point; the function holds no previous state. The word
"hysteresis" doesn't occur anywhere in `Sources/`.

This makes the assignment **unambiguous** — half-open rectangles, every
shared edge belongs to exactly one zone, which
[`dropzones.md`](dropzones.md) documents as proven. But unambiguous is not
the same as stable: if the pointer sits right on an edge, the highlight can
flip back and forth from a single pixel of jitter. This only becomes
visible with an actual hand-drag.

**Why this stays open and unbuilt.** A stabilization can't be judged
without an actual drag: how many pixels of dead zone are right, whether it
needs a time threshold instead of a distance threshold, whether the problem
is even noticeable — without the Accessibility grant there is no
observation for any of this, only a guess. An unmeasured stabilization
would be exactly the kind of unbacked assurance this project otherwise
avoids, and it would be worse than none: a dead zone that ends up too large
makes small zones unreachable, and nobody notices that a supposed usability
fix is the cause. **To be decided after the first session with an actual
drag, not before.**

**The trap, should someone build it anyway.** A session run in parallel on
#10 had already built a hysteresis, and its own test found a logic error in
it: the condition required that the previously highlighted zone still be
**among the candidates** of the current point — **at the moment of crossing
the edge, it never is.** So the hysteresis failed to engage in the one case
it exists for. The condition looks entirely plausible; anyone rebuilding it
will rebuild the same bug. The correct form must hold on to the previous
zone *independently* of the current hit, and only give it up once the
pointer has crossed the edge by more than the dead zone.

Provenance: that session's work never landed on `main` (#10 was merged from
the other branch in PR #15); the finding and the logic error come from it
and are recorded here so the lesson isn't paid for twice.

---

## 14. The role layer with only one profile — *decided: keep visible*

**Question:** In the actually existing configuration, the chain
rule → role → zone is strictly 1:1:1 — three rules, three roles, three
zones. One role is named `links-aussen`, carries the label "Links außen"
(outer left) and the note "Automatisch angelegt für „Systemeinstellungen""
(automatically created for "System Settings"). It's named after the zone it
points to: `QuickPin` had to give it a name and had nothing to say. Should
the role layer be hidden in the interface until a second profile makes it
necessary?

**Decision: no, the role stays visible. The overview from #19 has already
made the intermediate layer tolerable without hiding it.**

Since #19, the editor opens on the "Übersicht" (overview) tab
(`EditorWindow` with `@State private var tab: Tab = .overview`). It shows a
to-scale picture of the display arrangement, with zone names in the zones
and rule labels plus bundle identifier underneath. The word "role" does not
appear **once** in the drawing — the computation
(`PlacementOverview.build`) collapses the chain rule → role → binding →
zone in Core, and the interface shows only the result. Opening the editor
therefore immediately shows "TextEdit → Rechts außen" (outer right),
"Outlook → Mitte" (middle), "Systemeinstellungen → Links außen" (outer
left). The everyday path no longer encounters the role at all. It only
appears on the "Rollen & Profile" (roles & profiles) tab, and anyone who
lands there wants to see the data model.

Hiding it would have a cost in three places that outweighs the gain:

- **There's no reveal point.** The issue itself names the risk: having
  roles in the data model while hiding them in the interface forces **one**
  clearly named moment at which they appear — creating the second profile.
  That moment doesn't exist today. `RoleEditor` iterates
  `document.configuration.profiles`; the editor has no way to create a
  profile. Hiding the layer without building the path there first is
  exactly the "Advanced" toggle the issue warns against.
- **`QuickPin` labels roles after their zone.** That's the cause of "Links
  außen"; hiding the layer only cures the symptom in everyday use and
  leaves it for whoever opens the roles tab. `QuickPin`'s benefit — that
  the user never has to learn the word "role" — already holds today
  (`Outcome.summary` talks about rule and zone, not role). The mismatch the
  issue describes only becomes real once a second profile exists and the
  "Links außen" role on the laptop suddenly needs to sit somewhere else.
  From that moment on, the role is no longer superfluous but the answer to
  a real question.
- **Today's cost is low.** Three roles, three rules, three zones — the
  roles tab is a short note next to the overview, which already answers
  "where does what go?". Keeping the data format unchanged and
  re-surfacing the layer at the second profile would be more expensive
  than leaving it visible: hiding it would have to remain backward
  compatible, and the moment it reappears would need explaining.

The core point: **the overview makes the role layer tolerable without
hiding it.** That was exactly the thesis in the issue's last paragraph. It
held up.

**Rejected alternative — hide it with a three-stage reappearance.** The
issue proposed: with one profile, the role stays invisible (identifier =
zone identifier, file format unchanged), on creating the second profile the
question "Where does 'E-Mail' live in this setup?", and visible from then
on, plus a hint in `FindingIndex` when a role is named like its zone.
Cleanly thought through, but:

- The reveal point "creating the second profile" doesn't exist in the
  editor and would first have to be built. Without it, the reveal becomes
  an "Advanced" toggle — exactly the mistake the issue names in its own
  proposal.
- `QuickPin` would have to reword its output even though its current
  messages already avoid the word "role". The effort would come from the
  constraint of never producing a visible role, not from a user need.
- A `FindingIndex` hint saying "this name will become misleading with a
  second setup" is a finding about a hypothetical setup. Findings are
  otherwise statements about the configuration as it is. This hint would
  be an outlier.

**What follows if the layer should be hidden later after all.** The
prerequisite is then the path to a second profile in the editor (creation
with a question per existing role, "Where does it live here?"). Before
that, hiding it is a half-step and makes things worse, not better.

---

For the record:

| Deviation | Rationale |
|---|---|
| **SwiftPM package instead of an Xcode project** | The starting point was a pure data model and could be checked headless with `swift build` / `swift test`; the manifest is text and thus reviewable. The assumption at the time — that signing requires an Xcode target — turned out to be wrong: `Scripts/bundle.sh` builds a signed `.app` from the package, and the Accessibility grant holds. An Xcode project only becomes necessary once the menu bar target needs more than SwiftPM can deliver. |
| **The "Unterwegs" (on the go) profile without Space 2** | Spaces aren't addressable via the public API, see question 1. The `communication` role instead sits on the right half of the built-in display in the example. |
| **`fallback` is a required field in the profile** | The concept called for a defined default zone for unmapped roles. As an optional field it would, in practice, have stayed empty — exactly the state it's meant to prevent. |
| **JSON instead of YAML** | A deliberate choice: `Codable` with no external dependency. The cost is the lack of comments, which is why the commented explanation lives in `docs/konfiguration.md`. |
| **`share` only as an even slot split** | The concept mentioned "optionally split a zone" without fixing how expressive that should be. Anything beyond equal-sized slots belongs in the layout as its own zone, otherwise a second, parallel layout system emerges inside the rules. |
| **Zones may overlap** | Not explicit in the concept. Overlap is allowed because a large focus zone spanning two halves is a legitimate design. Ambiguity is resolved by the role binding, not by the geometry. |
| **`RuleEngine` takes a prepared `CompiledRuleSet` instead of `[PlacementRule]`** | The sketch passed the rules per window. That would only satisfy the requirement "regular expressions are compiled once" via a cache that guesses at array equality. An explicitly prepared rule set instead makes visible that compiling a pattern can fail, and forces that case to be handled at one defined spot — rather than mid-evaluation. A rule with an invalid pattern ends up in `unusableRules` and is skipped; a run never fails because of one broken rule. |
| **`ZoneResolver` computes in AppKit coordinates, not AX coordinates** | The model describes zones from the top left, AppKit measures from the bottom left, and the Accessibility API again from the top left. The conversion model → AppKit happens exactly once, right here; the conversion back to AX belongs in the layer that actually writes `kAXPositionAttribute`. A dedicated `VisibleFrame` type makes the convention visible at every call site instead of leaving it to be inferred from a `WindowFrame`. |
| **Rounding per edge instead of rounding origin and size** | Two adjacent zones must touch exactly. Rounding origin and size separately would, depending on display width, produce a one-point gap or overlap. Instead, the four edges are rounded and width and height derived from them. |
| **`WindowFilter` knows the rules that opt out of `onlyFirstWindowAfterLaunch`** | The sketch treated the filter as a pure pre-filter ahead of global defaults. But a filter that enforces the default unconditionally makes exactly the rules that opt out of it unreachable — the example configuration's Outlook compose window is, by definition, never the first window. The filter therefore derives its exceptions once from the rule set: every enabled rule that sets the flag to `false` exempts windows of its bundle ID (or all windows, if it names none). |
| **`Displacement` and `SkipReason` as their own result types** | `PlacementOutcome` describes what *did* happen to a window. The purely computational half lacked a type describing what *should* happen — including a reason when nothing does. `PlacementDecision` fills that gap; without it, "not placed" would be a catch-all answer for very different situations. |
| **`ZoneResolver.resolveFallback` alongside resolution via the role** | Resolving a profile's fallback binding via its role would be wrong: if that role has its own binding, its regular zone would come out. A displaced window would then land in exactly the zone it had just had to make way for. |

---

## Tracer-bullet design decisions

Made while building `openzonr`, without the concept dictating them:

| Decision | Rationale |
|---|---|
| **Enumerate displays via `NSScreen.screens` instead of `CGGetActiveDisplayList`** | `CGGetActiveDisplayList` returns **zero** displays in a plain command-line process — reproducibly measured. The `CGDirectDisplayID` instead comes from `NSScreen.deviceDescription["NSScreenNumber"]`; all EDID queries afterward run unchanged through the `CGDisplay*` functions. |
| **Hand-written argument parsing instead of `swift-argument-parser`** | Three subcommands with five options between them don't justify an external dependency. `swift build` stays runnable without network access. |
| **The conversion to AX coordinates happens at exactly one spot** | `ZoneResolver` returns AppKit coordinates, the Accessibility API wants the origin top left. The flip lives solely in `WatchCommand.place(…)` via `ScreenArrangement.flipVertically`. Two conversion spots would be two chances to lose the sign. |
| **Write sequence position → size → position** | Setting only position and then size lets an app that clamps the size move the window again. The second position assignment corrects that within the same attempt, before anything is even read back. |
| **Success means: maximum edge deviation ≤ `tolerance`** | Not area, and not the distance between origins. An app that only ignores the width would otherwise pass despite the window visibly sitting wrong — or vice versa. |
| **No further observation after successful placement** | A window that gets moved after placement was moved by the user. A tool that undoes that is a prison. |
| **Already-running apps never count as "first window after launch"** | Their counter starts at `Int.max / 2`. Otherwise `onlyFirstWindowAfterLaunch` would apply to any pre-existing window when `watch` starts. |
| **`AXObserverAddNotification` retries up to 20× at 150 ms intervals** | A freshly launched process is briefly unreachable via the Accessibility API. A single attempt right after `didLaunchApplicationNotification` regularly fails — and that's exactly when you'd miss the first window, the most interesting one. |
| **`mode: "suggest"` is only logged** | A suggestion without an overlay isn't a suggestion. The rule, the role and the target frame are logged in full so it's visible what *would have* happened; nothing gets moved. `share`, by contrast, is fully implemented via `DefaultZoneResolver` and merely logged in addition. |
