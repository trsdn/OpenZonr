# OpenZonr — Concept and Architecture

Status: early concept stage. This document describes the model, not a
finished implementation. The Swift types under `Sources/OpenZonrCore/` are
the formal rendering of the same model.

---

## 1. Vision and non-goals

**Goal:** windows land automatically, upon opening, where they belong —
across changing monitor setups, without rules having to be duplicated per
setup.

**Explicitly not the goal:**

- Not a tiling window manager. It does not automatically arrange
  everything, only what the user has explicitly set a rule for.
- Not a replacement for Mission Control or Spaces management.
- No continuous monitoring that permanently pins every window in place.
  Placement happens on open; after that, the window belongs to the user.

The last point is a stance, not a technical limitation: a tool that insists
on its rules fights against the user instead of for them.

---

## 2. The placement pipeline

```
NSWorkspace.didLaunchApplication
        │
        ▼
AXObserver per app  ──  kAXWindowCreatedNotification
        │
        ▼
[1] Window filter        Subrole, minimum size, "first window after launch"
        │
        ▼
[2] Rule evaluation      first matching rule by priority wins
        │
        ▼
[3] Role resolution      role → active profile → display + zone
        │
        ▼
[4] Geometry             RelativeRect × visibleFrame → absolute frame
        │
        ▼
[5] Placement            kAXPositionAttribute / kAXSizeAttribute
        │                with retry loop and read-back of the result
        ▼
   PlacementOutcome      logged for diagnostics and UI
```

### Window source

Two event sources interlock:

- `NSWorkspace.didLaunchApplicationNotification` reports newly launched
  apps. For each one, an `AXObserver` is created and registered for
  `kAXWindowCreatedNotification`.
- When OpenZonr starts, a one-time pass scans the already-running apps and
  attaches observers there as well.

`NSWorkspace` alone is not enough, because an app has no window yet at
launch. The `AXObserver` alone is not enough, because it is bound to a
specific PID and must first be created for new processes.

### The decisive point: timing

A window often exists before it is finally sized. Electron apps and the
Office suite apply their stored window geometry after the first draw,
sometimes repeatedly and asynchronously. Setting position and size once is
therefore overwritten milliseconds later — the window briefly jumps and
ends up in the wrong place after all.

Countermeasure: **place, read back, repeat**. After setting, the frame is
read again via the Accessibility API and compared to the desired frame. If
it deviates beyond the tolerance, the next attempt follows. Default: three
attempts spread over about 500 ms (`initialDelay` 50 ms, `interval` 200 ms,
tolerance 4 points). That is the smallest amount that reliably prevails
against self-resizing apps without windows visibly jittering.

The tolerance is not a detail: terminals enforce size steps in character
widths, and some apps have a minimum size. Without tolerance, the loop
would keep running against a window that is already as close to its target
as it will ever get.

---

## 3. Which window, exactly?

Outlook opens a main window, compose windows, recurring-appointment
dialogs, and reminder popups. Without a filter, every one of them would get
placed.

Three filter stages, in ascending order of effort for the user:

1. **Subrole `AXStandardWindow`.** Excludes dialogs, sheets, palettes, and
   most popups without anything needing to be configured.
2. **Minimum size** (default 400×300 points). Catches what slips through:
   reminder windows, progress indicators, tool palettes.
3. **Title regex** — the sharp weapon, but the last resort. Window titles
   are localized and often change fractions of a second after opening.

### The most important default

**"Only first window after app launch"** is active by default. Dialogs,
compose windows, and popups appear *later* and thus automatically fall
out — without anyone having to write a title regex. This one default saves
a large part of the fine-tuning that would otherwise be needed.

Anyone who wants to specifically place a compose window turns it off for
exactly that rule and adds a title pattern — see the `outlook-compose` rule
in the example configuration.

---

## 4. The rule model: match → action

A rule consists of criteria and an action.

### Match criteria

All optional, all joined with **AND**:

| Criterion | Purpose |
|---|---|
| `bundleIdentifier` | The base case, e.g. `com.microsoft.Outlook`. |
| `titlePattern` | Distinguishes „Posteingang“ (Inbox) from compose windows. |
| `roles` / `subroles` | Standard window vs. dialog. |
| `minimumSize` / `maximumSize` | Filters popups and palettes. |
| `aspectRatio` | Catches the remaining unusual shapes. |
| `onlyFirstWindowAfterLaunch` | See above; overrides the global default. |

An empty match definition matches every window. As a catch-all rule with
the lowest priority at the end, that makes sense; anywhere else, it is
dangerous.

The criteria deliberately map exactly what the Accessibility API cheaply
provides at the time of `kAXWindowCreatedNotification`. Anything requiring
deeper inspection would slow down the placement path — which is already in
a race against the app's own layout code.

### Action

- **`role`** — the semantic target (see section 5). Required.
- **`share`** — optional subdivision of the zone into equally sized slots
  (axis, slot count, slot index). This lets mail and chat share one
  communication zone without a second zone having to be drawn for it.
  Anything more complex belongs in the layout as its own zone.
- **`focus`** — `activate` or `leaveAsIs`. For apps that start in the
  background at login, `leaveAsIs` is the sensible choice.
- **`mode`** — `place` or `suggest`. `suggest` moves nothing but offers the
  placement instead. Useful while breaking in a new rule, and for apps that
  react badly to being moved during startup.

---

## 5. The central indirection: roles instead of zones

Rules point **not** to a zone, but to a **role**. Each profile maps roles to
its own zones:

```
Rule:                Outlook → role "communication"

Profile Office:      communication = Dell U2723,  zone right (50%)
Profile Home:        communication = LG 38",      zone right edge (25%)
Profile On the Road: communication = Builtin,     right half
```

The payoff: app rules are written **once** instead of duplicated per setup.
A new monitor means a new profile with five role bindings — not rewriting
every app rule. And reassigning a role ("communication now belongs on the
left") is a single entry instead of a search through every rule.

The overall data flow:

```
Rule ──match──▶ Role ──Profile──▶ Display + Zone ──Layout──▶ Geometry
```

### Fallback is mandatory

If a role is not mapped in the active profile, the `fallback` binding
stored in the profile applies. It is a required field, deliberately so: an
unmapped role must never mean "somewhere." The window lands at a defined
place, and the event is logged so the gap becomes visible instead of
staying silent.

---

## 6. Monitor identity

The hardest part, because every obvious solution here is wrong.

### What does not work

| Approach | Why it fails |
|---|---|
| Position in the arrangement | Changes when re-plugging or rearranging in System Settings. |
| Index in `NSScreen.screens` | Order is not stable, especially on wake. |
| Resolution alone | Two identical monitor models are indistinguishable. |
| `CGDirectDisplayID` | Assigned per session, not stable across restarts. |

### What works

The EDID data that CoreGraphics provides:

- `CGDisplayVendorNumber`
- `CGDisplayModelNumber`
- `CGDisplaySerialNumber`

With this, a monitor is unambiguous, regardless of which port or in what
order it is connected.

**Special case, the built-in display:** detected via `CGDisplayIsBuiltin`
and treated as its own identity case. It is the only screen present in
every setup and never swapped for a different model without the machine
itself being swapped at the same time.

**Fallback without a serial number:** some monitors report `0` as the
serial number. Then vendor + model + port index (read from
`CGDisplayUnitNumber`) applies. Pixel size is deliberately **not** a
characteristic, since it depends on the current display mode and changes
when switching; it is carried along only for display. This is not globally
unique: identical monitor models without a serial number are distinguishable
only by their port and can be confused when swapped. Whether better public
characteristics exist has not been investigated so far;
`CGDisplayScreenSize` is not established as stable. Mode independence is
justified in the code and covered by a test, but not measured on real
hardware (manual check in [konfiguration.md](konfiguration.md), the
`identity` section). The case is explicitly marked as `fallback` in the
data model so the UI can warn specifically about it.

**The port index drifts — measured on 19.09.2026.** The assumption that
`portIndex` is a usable discriminator because it sticks to a connector is
disproved: the same monitor (C49RG9x, vendor 19501, model 3996, serial
number 0) reported unit number `0` on 29.08.2026 and `1` on 19.09.2026,
without any cable being moved. `CGDisplayUnitNumber` is assigned in
enumeration order, and software displays ("AAA", "Teleprompter Source"),
which come and go, shift everything enumerated after them. The consequence
was no matching profile, and thus a complete failure of the dropzones.

The fix is deliberately narrow and lives in its own pure function
(`DisplayIdentityReconciler`): **a monitor without a serial number is
recognized independently of the port index when its vendor-and-model
combination occurs exactly once, both in the configuration and among the
connected screens.** An exact match wins first; if several candidates or
several contenders are in play, the exact comparison still applies.
**Identical monitor models without a serial number therefore still depend
on the port index and can be confused when swapped** — this limitation is
unchanged. This is explicitly not a claim that the unit number is stable;
it is not — recognition merely manages without it in the unambiguous cases.
`edid` and `builtin` remain untouched and exact.

---

## 7. Setup fingerprint and profiles

The active profile results from the **fingerprint**: the sorted,
order-independent set of all active monitor identities.

```
{builtin}                          → „Unterwegs" ("On the Road")
{builtin, DellU2723-SN1194485571}  → „Büro" ("Office")
{builtin, LG38-SN909876}           → "Home"
```

Order independence matters: whether the external monitor is detected before
or after the dock must not affect profile selection.

**Observation** via `CGDisplayRegisterReconfigurationCallback`. The
callback fires multiple times on plugging and unplugging, while displays
wake and negotiate resolutions. It is therefore debounced before the
fingerprint is recomputed — otherwise the profile would switch several
times during a single docking event.

**Unknown fingerprint → ask, don't guess.** A new setup prompts a question
about whether to create a profile. Guessing a "best similar profile" would
silently place windows on the wrong screen — that is worse than doing
nothing.

In the configuration file, profiles reference displays via a short **alias**
(`"dell-u2723"`) instead of the raw identity. This keeps the file readable;
resolving alias → identity is handled by the display table.

---

## 8. Zones and layouts

**Zones are never stored in pixels**, but as a percentage relative to the
*visible* frame — that is, excluding the menu bar and Dock. The office
monitor is smaller than the home ultrawide; a zone stored in points would
fit on one screen and be useless on the other. Scaling changes and a shown
or hidden Dock also shift the usable area.

Coordinate system of the `RelativeRect`: origin `(0, 0)` top-left, `(1, 1)`
bottom-right. AppKit counts from the bottom left; the conversion happens in
the placement layer, not in the file format — top-left is what people draw
in a zone editor.

**Layouts belong to the display, not the profile.** A 38-inch ultrawide
wants a three-column layout, a 24-incher a two-column layout, and that
stays true regardless of which profile is currently active. A display can
own several layouts; the active profile selects which one is used
(`profile.layouts`), otherwise `defaultLayoutID` applies.

Zones within a layout may overlap. That is a legitimate design — a large
focus zone laid over two halves — so it is not forbidden. Ambiguity is
resolved via role bindings, never by guessing from geometry.

---

## 9. Conflict resolution

Three kinds of conflict, all explicitly handled.

### Multiple matching rules

Evaluated by `priority` descending, and by file order in case of a tie.
**The first matching rule wins**, after which evaluation stops.

It follows that: **specific before generic**. The Outlook-compose rule must
have a higher priority than the general Outlook rule — otherwise the
general one matches first and the specific one never gets a turn. In the
example configuration, this is visible in the priorities 100 versus 50.

### Target zone is occupied

Three configurable strategies (`conflict.occupiedZone`):

- **`stack`** (default) — the new window is added to the zone. Nothing is
  displaced; the zone holds several windows that one can switch between.
  The conservative choice.
- **`replace`** — the new window takes over the zone; the previous occupant
  moves to the profile's fallback zone.
- **`skip`** — the new window stays wherever the system opened it.

### Manual override

If the user drags a window out of its zone themselves, that is a statement.
**The rule must not pull it back.** The window is marked as manually
overridden (`conflict.honorManualOverride`, default `true`) and left alone
for the rest of its lifetime. Optionally, `manualOverrideTimeout` can be
used to specify that the override expires after a period of time.

---

## 10. Pitfalls

### Permissions

Without Accessibility permission, nothing works — neither observing nor
placing. Two consequences:

- The app must guide the user cleanly through granting it and check with
  `AXIsProcessTrustedWithOptions`, instead of silently doing nothing when
  the permission is missing. `PlacementOutcome.missingPermission` exists
  for this.
- **The app must be signed.** The Accessibility grant is tied to the code
  signature. For an unsigned or ad-hoc-signed app, it expires with every
  update, and the user has to remove the entry from System Settings and
  grant it again every time.

### Self-resizing apps

See section 2. Electron builds and the Office suite restore their stored
geometry after opening. The retry loop with read-back is the answer.

### Non-cooperative apps

Java toolkits (AWT/Swing) and individual Electron builds partially ignore
AX positioning or clamp it to their own notion of a valid frame.
`PlacementOutcome.rejectedByApplication` exists for this, carrying the
frame actually achieved: the UI can name the affected app instead of
failing silently. How much further to push beyond that is open — see
`docs/offene-fragen.md`.

### Window titles

Localized, and often only finalized after appearing. Title regex is
therefore used only where there is no other way.

---

## 11. UI in two tiers

**Tier 1 — simple, covers roughly 90% of cases:** right-click a placed
window → *„Diese App immer hier öffnen“* ("Always open this app here"). In
the background, a rule is created for the bundle ID with the role belonging
to the current zone. No rule editor, no form, no explanation needed.

**Tier 2 — advanced:** a rule editor with the match criteria from
section 4, for cases like the Outlook compose window. Whoever doesn't need
it never sees it.

Underneath, in both cases, lies the same **configuration file in JSON
format** — versionable, shareable, editable as text. Anyone who wants to
can bypass the UI entirely.

---

## 12. Build-out stages

1. Data model and configuration format *(current status)*
2. Monitor detection: identity, fingerprint, profile switching
3. Window detection and filtering, logging-only at first
4. Placement with retry loop
5. Rule evaluation and role resolution
6. Menu bar app with tier-1 UI
7. Zone editor and rule editor
8. Signing and distribution

The order follows the risk: monitor identity and placement timing are the
parts where the concept could fail. They come first.
