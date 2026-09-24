# Configuration Reference

The configuration is stored as **JSON**: version-controllable, diffable,
shareable, and editable with any text editor. JSON has no comments — which is
why the explanation lives here instead of in the file.

Reference file: [`Examples/openzonr.config.json`](../Examples/openzonr.config.json).
The tests in `Tests/OpenZonrCoreTests/` check it against the data model, so it
is guaranteed to be valid.

> **The example configuration is illustrative, not a template to copy.**
>
> It shows the structure, not a real setup. Specifically:
>
> - **The EDID numbers are made up.** `vendorNumber`, `modelNumber`, and
>   `serialNumber` for "Dell" and "LG" are placeholders. Anyone who copies
>   them gets a profile that never matches.
> - **All three profiles rely on a `builtin` display.** On a desk with the lid
>   closed, or on a desktop Mac, `CGDisplayIsBuiltin` is true for *no* display
>   — the alias hits nothing there. Actually measured on the author's setup:
>   four displays, not one of them built in.
>
> **The authoritative source for real identities is `openzonr displays`.**
> `openzonr displays --config-fragment` prints a ready-made `displays`
> fragment that can be adopted as-is. Only after that should layouts, roles,
> profiles, and rules be added.


---

## Structure

```jsonc
{
  "version":  1,     // schema version, drives migrations
  "displays": [],    // physical displays + their layouts
  "ignoredDisplays": [], // displays that don't affect the fingerprint
  "roles":    [],    // semantic placement targets
  "profiles": [],    // setups: which role sits where?
  "rules":    [],    // match → action
  "defaults": {}     // defaults that rules inherit
}
```

The order follows the chain of indirection:

```
Rule ──match──▶ Role ──Profile──▶ Display + Zone ──Layout──▶ Geometry
```

---

## `displays`

One entry per physical display.

| Field | Type | Meaning |
|---|---|---|
| `alias` | String | Short handle for referencing it, e.g. `"dell-u2723"`. Freely chosen, must be unique. |
| `displayName` | String | Plain-text name for the UI. |
| `identity` | Object | Stable hardware identity, see below. |
| `layouts` | Array | All layouts defined for this display. |
| `defaultLayoutID` | String | Layout to use when a profile doesn't select one. |

### `identity`

Three variants, distinguished by `kind`:

```jsonc
// Built-in display, detected via CGDisplayIsBuiltin
{ "kind": "builtin" }

// Preferred case: full EDID data
{
  "kind": "edid",
  "vendorNumber": 4268,        // CGDisplayVendorNumber
  "modelNumber": 42145,        // CGDisplayModelNumber
  "serialNumber": 1194485571   // CGDisplaySerialNumber
}

// Only when the monitor reports no usable serial number
{
  "kind": "fallback",
  "vendorNumber": 4268,
  "modelNumber": 42145,
  "pixelWidth": 3840,          // display only, doesn't count toward the comparison
  "pixelHeight": 2160,         // display only, doesn't count toward the comparison
  "portIndex": 0
}
```

The `fallback` variant is not globally unique. `vendorNumber`, `modelNumber`,
and `portIndex` are stored and compared. `pixelWidth` and `pixelHeight` are
purely informational for display purposes and **do not** count toward
recognition; changing the resolution should therefore not turn the same
monitor into a different one. This is justified in the code and backed by a
unit test, but not yet measured on real hardware (see the manual check
below).

### The `portIndex` drifts — measured

The `portIndex` comes from `CGDisplayUnitNumber`. The assumption that this
number stays fixed to a port is **disproven**:

| Date | Monitor | Unit number |
| --- | --- | --- |
| 29.08.2026 | C49RG9x (vendor 19501, model 3996, serial number 0) | `0` |
| 19.09.2026 | same monitor, same cable | `1` |

Nothing had changed at the desk. What had changed was that software displays
were present at enumeration time: numbers 0, 1, 2, 3 went, in enumeration
order, to "AAA" (vendor 21252, model 0), C49RG9x, U28E590, and "Teleprompter
Source". Any software display enumerated before a real panel shifts that
panel's number. The configuration held `portIndex: 0`, the machine reported
`1`, no profile matched — and with that the entire dropzone feature was gone
(both the overlay and the right-click menu bail out on "no active profile").

**What follows from this (`DisplayIdentityReconciler`):**

- A monitor without a serial number is recognized **independently of
  `portIndex`** when its combination of `vendorNumber` and `modelNumber`
  occurs **exactly once**, both in the configuration and among the connected
  displays. In that case there is only one candidate and only one claimant;
  nothing needs to be guessed.
- An exact match (vendor, model, **and** port) always wins first.
- **Identical-model monitors without a serial number still depend on
  `portIndex`** and can be mixed up if the connections are swapped. This
  limitation remains exactly as it was; it is explicitly not being guessed
  away.
- `edid` and `builtin` are unaffected and are always compared exactly.
- This is **not a stability guarantee** for the unit number. It drifts;
  recognition only manages to work around it in the unambiguous cases.

When a configuration is present, `openzonr displays` reports such a recovered
case as one line: `konfiguriert als port=0, aktuell port=1: erkannt, weil
eindeutig` ("configured as port=0, currently port=1: recognized, because
unambiguous"). Without a configuration, the report instead says that no such
statement is possible — a configuration can be supplied with `--config
<path>`. The same line appears in the watch diagnostics.

Older configuration files that hold the size of a scaled mode there are meant
to keep matching unchanged. This is backed by the tests
`legacyJSONDecodesEqual` (DisplayIdentityTests) and
`legacyFallbackProfileStillMatches` (ProfileResolverTests); the behavior on
real hardware is not measured. Newly generated fragments (`openzonr displays
--config-fragment`) contain the native size when the driver flags exactly one
mode as native, otherwise `0`.

**Limits:**

- Identical-model monitors without a serial number are distinguished only by
  `portIndex`. It is read from `CGDisplayUnitNumber`, the closest public
  equivalent of a port index, not from an actual connector label. If such
  monitors are swapped between ports, mix-ups should be expected — the
  reconciliation described above changes nothing here, because it does not
  apply in precisely this case.
- The `portIndex` has been shown to change even without re-plugging anything
  (see above), and can additionally change with altered wiring (a different
  port, a different dock, a hub). As long as the monitor stays unambiguous, it
  is still recognized. If it isn't, it counts as unknown: no profile is
  chosen (no guessed assignment), and watch mode prints a hint with the next
  step. Whether the number survives unplugging/replugging, sleep, or a
  restart has still not been systematically investigated.
- Whether the driver sets a native flag for a given monitor is an open
  question. If it's missing, the pixel fields hold `0`. This affects only the
  display information, not recognition.
- Whether better public identifiers exist (such as `CGDisplayScreenSize` or
  IOKit paths) has not been investigated so far and is not documented as
  stable.

**Manual check on hardware (open, for #39):** So far nobody has verified this
on real hardware. To do, and to record in the issue:

- [ ] Connect a monitor without a serial number; run `openzonr displays` and
      record the identity and the fallback note.
- [ ] Print `openzonr displays --config-fragment`: do `pixelWidth`/
      `pixelHeight` hold the native size, or `0`?
- [ ] In System Settings, switch between at least three modes (native,
      scaled, lower resolution) and run `openzonr displays` after each
      switch: do vendor, model, and port stay the same, and does the profile
      stay active?
- [ ] Load a fragment with the pixel dimensions of a scaled mode (an old
      file): does the profile still match?
- [ ] Two identical-model monitors without a serial number, if available: do
      the `portIndex` values differ? Swap the cables and observe whether the
      assignment changes.
- [ ] Unplugging/replugging, sleep, restart: does the `portIndex` stay the
      same?
- [ ] Is the native flag missing (size `0`)? Note it in the issue.

Result (device, observation, date): Partially gathered on 19.09.2026, macOS
26.6.2, C49RG9x (serial number 0, `port=1`), current mode 5120×1440. The mode
list contains exactly one flag for the native size (5120×1440), both with and
without `kCGDisplayShowDuplicateLowResolutionModes`. After switching to
4608×1296 (session only, reverted afterward), the identity in `openzonr
displays` stayed unchanged (`fallback vendor=19501 model=3996 5120×1440
port=1`).

Also gathered on 19.09.2026 — and the reason for the reconciliation described
above: the same monitor carried unit number `0` on 29.08.2026 and `1` on
19.09.2026, without any cable being moved. The cause was the software
displays present in the meantime ("AAA", "Teleprompter Source"), which shift
the number assignment. **Not gathered:** rotation by 90° or 270°, the unit
number's behavior after a restart, unplugging, or a dock change, two
identical-model monitors without a serial number.

> **`serialNumber == 0` is the normal case, not the edge case.**
>
> On the measured setup, it's the main monitor of all things — a Samsung
> C49RG9x — that reports serial number 0. The `fallback` path is therefore
> the *most important* path, not the exception. It is tested accordingly and
> is chosen automatically by `openzonr displays --config-fragment` when the
> serial number is 0.
>
> Note that the fallback deliberately includes **the `modelNumber` too**. On
> the same setup, two Samsung monitors share `vendorNumber` 19501 and differ
> only by model. An identity built from vendor plus resolution alone would
> collide here.

**Not used as identity:** position in the arrangement, index in
`NSScreen.screens`, resolution alone, or `CGDirectDisplayID`. Reasoning in
[konzept.md, section 6](konzept.md#6-monitor-identity).

## `ignoredDisplays`

A list of `identity` objects in the same format as above. Displays that
appear in it are **skipped when building the setup fingerprint**.

The reason is a problem that only became visible on real hardware: **virtual
displays throw off the fingerprint.** Software such as OBS or a teleprompter
tool reports full-fledged displays to the system. They come and go while
nothing physically changes — and under the original design, the fingerprint
changes every time as a result, and the profile switches out from under you.

On the measured setup, this affects two of four displays ("AAA", "Teleprompter
Source"). With `ignoredDisplays`, the fingerprint stays stable across both
physical monitors, regardless of whether OBS happens to be running.

```jsonc
"ignoredDisplays": [
  { "kind": "fallback", "vendorNumber": 21252, "modelNumber": 0,
    "pixelWidth": 1920, "pixelHeight": 1080, "portIndex": 2 },
  { "kind": "edid", "vendorNumber": 21581, "modelNumber": 1, "serialNumber": 1 }
]
```

**Deliberately an explicit list, not a heuristic.** `openzonr displays` flags
suspected cases with `virtuell?` ("virtual?"), but does not remove them from
the fingerprint on its own — the detection is unreliable (see
[offene-fragen.md](offene-fragen.md)), and a tool that ignores displays by gut
feeling is worse than one that asks. `openzonr displays --config-fragment`
suggests the entries; the decision is the user's to make.


### `layouts` and `zones`

```jsonc
{
  "id": "lg-three-columns",
  "name": "Drei Spalten (25 / 50 / 25)",
  "zones": [
    { "id": "left-quarter",  "name": "Links außen",  "frame": { "x": 0.0,  "y": 0.0, "width": 0.25, "height": 1.0 } },
    { "id": "center-half",   "name": "Mitte",        "frame": { "x": 0.25, "y": 0.0, "width": 0.5,  "height": 1.0 } },
    { "id": "right-quarter", "name": "Rechts außen", "frame": { "x": 0.75, "y": 0.0, "width": 0.25, "height": 1.0 } }
  ]
}
```

`frame` is **percentage-based**, `0.0` to `1.0`, relative to the display's
*visible* frame — i.e., excluding the menu bar and Dock. The origin `(0, 0)`
is **top-left**.

Never pixels: the office monitor is smaller than the home ultrawide, and
scaling plus a shown or hidden Dock change the usable area.

Layouts belong to the display, not to the profile — an ultrawide wants three
columns, a 24-inch display wants two, regardless of which setup is currently
active.

### `activationArea` — where you must release, separate from where the window ends up

Optional. The same coordinate space as `frame`: percentage-based, relative to
the display's visible frame, origin top-left. If the field is absent, `frame`
itself counts as the hit area — the previous behavior, unchanged.

```jsonc
{
  "id": "right-quarter",
  "name": "Rechts außen",
  "frame":          { "x": 0.667, "y": 0,   "width": 0.333, "height": 1   },
  "activationArea": { "x": 0.667, "y": 0.4, "width": 0.333, "height": 0.2 }
}
```

The reason for the separation: when several zones overlap, the smallest one
wins while dragging. If a stack of smaller zones covers a larger one without
a gap, the larger one becomes unreachable — with `frame` as the only
rectangle, there is no rule that resolves this. A separate `activationArea`
makes the hit areas disjoint, even when the target frames are not. The full
case — "Rechts außen" ("right edge") underneath two stacked halves — is
covered in [`dropzones.md`](dropzones.md), section "Trefferflächen" ("hit
areas").

`activationArea` does not have to lie within `frame`. That's intentional: it
lets a zone be triggered at the screen edge while the window lands somewhere
else. This edge-triggering is built into the model as a possibility, but has
not been tried so far — see the same section in `dropzones.md`.

Even so, it never reaches beyond its own screen: `DropzoneOverlayPlan.plan`
restricts to the display under the pointer before the hit test, and
`activationArea` is relative to the visible frame of exactly that display —
so a value within the valid range of 0 to 1 can never address a different
screen.

**The zone editor doesn't know about `activationArea`** (deliberately out of
scope). Anyone who drags a zone there only changes `frame` — an
`activationArea` that has been set stays put at its old location and
silently detaches from the target frame as a result. This is exactly what the
`activationAreaDetached` warning exists to catch: it makes this case visible
afterward.

**Consequence for the pin marker:** The pin point sits on the hit area, not
on the target frame — it is the second target of the same mouse movement. A
hit area under `4·2 + 8·2 + 24 + 24 = 72` points on its shorter edge
therefore no longer carries a marker at all. Placement still works there; the
rule then has to be created via the right-click menu.

---

## `roles`

Semantic placement targets. Rules point at roles, never directly at zones.

```jsonc
{
  "id": "communication",
  "name": "Kommunikation",
  "summary": "Mail und Chat — immer sichtbar, nie im Weg."
}
```

`summary` is optional and purely documentary.

The example configuration defines five roles: `communication`, `editor`,
`reference`, `terminal`, `compose`. Five to seven is a good rule of thumb —
more roles mean more bindings that have to be maintained per profile.

---

## `profiles`

A profile answers exactly one question: *Given this screen constellation —
where does each role go?*

```jsonc
{
  "id": "office",
  "name": "Büro",

  // Active when exactly these displays are connected.
  // Order-independent; the set is compared.
  "fingerprint": { "displays": ["builtin", "dell-u2723"] },

  // Which layout each display uses in this profile.
  // If a display is missing, its defaultLayoutID applies.
  "layouts": {
    "builtin": "builtin-full",
    "dell-u2723": "dell-two-columns"
  },

  // The actual role mapping.
  "roleBindings": [
    { "role": "communication", "display": "dell-u2723", "zone": "right-half" },
    { "role": "editor",        "display": "dell-u2723", "zone": "left-half"  },
    { "role": "reference",     "display": "builtin",    "zone": "full"       }
  ],

  // Required field: where to go if a role isn't mapped here.
  "fallback": { "role": "communication", "display": "builtin", "zone": "full" }
}
```

`fallback` is deliberately **mandatory**. An unmapped role must never mean
"somewhere"; the window lands at a defined location and the event is logged.

The fingerprint is compared **exactly**: a setup with one additional, unknown
monitor is not the same profile. An unknown fingerprint prompts the user,
rather than guessing a profile.

### The three example profiles compared

| Role | Büro (Office) | Home | Unterwegs (On the Road) |
|---|---|---|---|
| `communication` | Dell, right half | LG 38", right edge (25%) | Builtin, right half |
| `editor` | Dell, left half | LG 38", center (50%) | Builtin, left half |
| `compose` | Dell, left half | LG 38", center | Builtin, right half |
| `reference` | Builtin, full screen | LG 38", left edge (25%) | Builtin, right half |
| `terminal` | Builtin, full screen | Builtin, full screen | Builtin, left half |

The rules below are **identical** for all three profiles. That is exactly the
point of the role indirection.

In the "Büro" (Office) profile, `reference` and `terminal` share the same
zone. This is not a bug, but the normal case for
`conflict.occupiedZone: "stack"`: both windows sit stacked on top of each
other in the same zone.

---

## `rules`

```jsonc
{
  "id": "outlook-main",
  "name": "Outlook: Hauptfenster",
  "enabled": true,
  "priority": 50,               // higher = checked earlier

  "match": {
    "bundleIdentifier": "com.microsoft.Outlook",
    "subroles": ["AXStandardWindow"],
    "minimumSize": { "width": 800, "height": 600 },
    "onlyFirstWindowAfterLaunch": true
  },

  "action": {
    "role": "communication",
    "share": { "axis": "vertical", "slots": 2, "slotIndex": 0 },
    "focus": "leaveAsIs",
    "mode": "place"
  }
}
```

### `match` — all fields optional, AND-combined

| Field | Type | Purpose |
|---|---|---|
| `bundleIdentifier` | String | The base case. |
| `titlePattern` | String (regex, ICU) | Separates main windows from compose windows. **Use sparingly** — titles are localized and change at runtime, see the warning below. |
| `roles` | [String] | `kAXRoleAttribute`, e.g. `"AXWindow"`. |
| `subroles` | [String] | `kAXSubroleAttribute`. `"AXStandardWindow"` filters out dialogs and popups. |
| `minimumSize` / `maximumSize` | `{width, height}` in points | Filters out popups and palettes. |
| `aspectRatio` | `{minimum, maximum}` as `width / height` | Catches unusual formats. |
| `onlyFirstWindowAfterLaunch` | Bool | Overrides the global default. |

An empty `match` matches **every** window.

### Always active: the layer filter

Independently of `match`, OpenZonr discards every window that isn't at the
application layer (`kCGWindowLayer == 0`, or the AX equivalent). This is
**not an option and cannot be turned off** — it's the very first criterion
applied.

The reason is a measurement of the real window landscape:

```
Layer 20           Dock
Layer 21           Notification Center   5120×1440  ← passes every size filter
Layer 24           Menu bar (4×, per display)
Layer 25           ~130 Control Center items
Layer 3            Overlay of a third-party app
Layer 2147483630   Window Server status indicator
Layer 0            real app windows
```

The Notification Center ("Mitteilungszentrale") is **as large as the entire
main monitor**. Any minimum-size check lets it through; only the layer
distinguishes it from a real window. Subrole and minimum size alone are
therefore not enough.

### Why `titlePattern` is useless for Outlook and browsers

Titles are not an identity marker, they're a state display. Two measurements
of the same Outlook main window, same session, two minutes apart:

```
com.microsoft.Outlook   1708×1344 @ 1706,31
  t₀   "torstenmahr@microsoft.com" wird durchsucht
  t₁   yesterbox • torstenmahr@microsoft.com
```

Same window, completely different title — the first is a *search state* and
additionally contains nested quotation marks. In Edge and Safari, the title
is simply the page title and changes with every click.

On top of that: **the system language is not guaranteed to be English.** A
pattern like `(Message|Compose)` doesn't match on a German system. The
example configuration therefore lists
`(Nachricht|Message|Verfassen|Compose|Termin|Meeting)` — which eases the
problem but doesn't solve it.

**The more robust primary approach is therefore:**

1. `bundleIdentifier` as the base
2. `onlyFirstWindowAfterLaunch: true` for the main window
3. `minimumSize` against popups and palettes
4. `subroles: ["AXStandardWindow"]` against dialogs

Reach for `titlePattern` only when these four aren't enough — and then with
the awareness that the rule will silently stop matching after a language
change or a UI update to the app. `openzonr windows --bundle <id>` shows what
you're actually dealing with.

Why `onlyFirstWindowAfterLaunch` and `minimumSize` are both needed is shown
by the same measurement run:

```
com.corecode.MacUpdater   4× overlapping   420×206 @ 750,230   title ""
```

Four identical windows from the same app, all with an empty title. Without a
minimum size, all four would be candidates; without
`onlyFirstWindowAfterLaunch`, all four would be pushed into the same zone.


### `action`

| Field | Values | Purpose |
|---|---|---|
| `role` | role ID | Required. The semantic target. |
| `share` | `{axis, slots, slotIndex}` | Splits the zone into equal-sized slots. `axis`: `"horizontal"` or `"vertical"`. `slotIndex` is zero-based. |
| `focus` | `"activate"` / `"leaveAsIs"` | Whether the window is brought to the front. |
| `mode` | `"place"` / `"suggest"` | `"suggest"` doesn't move anything, it only offers the placement. |

### Evaluation order

Descending by `priority`; ties broken by file order. **The first matching
rule wins**, then evaluation stops.

It follows that: **specific before generic**. In the example configuration:

| Priority | Rule | Why this order |
|---|---|---|
| 100 | `outlook-compose` | Must take effect before the general Outlook rule, otherwise it never gets a turn. |
| 50 | `outlook-main` | The normal case. |
| 40 | `teams-main` | |
| 30 | `vscode` | |
| 20 | `safari` | |
| 10 | `terminal` | |
| −100 | `catch-all` | Catch-all rule, `"enabled": false` and `"mode": "suggest"` by default. |

### The Outlook example in detail

The compose window is the reason there's more than one match criterion at
all:

```jsonc
{
  "id": "outlook-compose",
  "priority": 100,
  "match": {
    "bundleIdentifier": "com.microsoft.Outlook",
    "titlePattern": "(Nachricht|Message|Verfassen|Compose|Termin|Meeting)",
    "subroles": ["AXStandardWindow"],
    // Explicitly disabled: the compose window is never the first.
    "onlyFirstWindowAfterLaunch": false
  },
  "action": { "role": "compose", "focus": "activate", "mode": "place" }
}
```

And its counterpart, the main window:

```jsonc
{
  "id": "outlook-main",
  "priority": 50,
  "match": {
    "bundleIdentifier": "com.microsoft.Outlook",
    "subroles": ["AXStandardWindow"],
    "minimumSize": { "width": 800, "height": 600 },
    // The default: reminder popups and dialogs fall out automatically.
    "onlyFirstWindowAfterLaunch": true
  },
  "action": {
    "role": "communication",
    // Upper half of the communication zone; Teams takes the lower one.
    "share": { "axis": "vertical", "slots": 2, "slotIndex": 0 },
    // Outlook often starts in the background and shouldn't steal focus.
    "focus": "leaveAsIs",
    "mode": "place"
  }
}
```

The title pattern is a crutch, and it's meant as one: Outlook titles are
localized, so the pattern covers both German and English variants. Anyone
using only one language variant should shorten it.

---

## `defaults`

Defaults that every rule inherits unless it overrides them.

```jsonc
{
  // The single most important default: dialogs, compose windows, and
  // popups fall out automatically without needing a title regex.
  "onlyFirstWindowAfterLaunch": true,

  "allowedSubroles": ["AXStandardWindow"],
  "minimumWindowSize": { "width": 400, "height": 300 },

  "retry": {
    "attempts": 3,        // including the first attempt
    "initialDelay": 0.05, // seconds until the first attempt
    "interval": 0.2,      // seconds between attempts
    "tolerance": 4.0      // points of deviation still counted as success
  },

  "conflict": {
    "occupiedZone": "stack",        // "stack" | "replace" | "skip"
    "honorManualOverride": true,    // leave manually moved windows alone
    "manualOverrideTimeout": null   // null = for the lifetime of the window
  },

  "dropzones": {
    "enabled": true,                              // overlay while dragging
    "activation": {"showsWhile": "command"},      // default since issue #23:
                                                  //   {"showsWhile": "X"}  – zones only while X is held
                                                  //   {"showsUnless": "X"} – zones always, except while X is held
                                                  //   X is "option" | "command" | "control" | "shift" | "none"
    "offerRule": false,                           // ask "always open here?" after dropping (off)
    "minimumDragDistance": 12,                    // points before the overlay appears
    "warnAboutCompetingManagers": true            // warn about Magnet & co.
  }
}
```

### On `retry`

A window often exists before it has its final size; Electron and Office apps
restore their saved geometry after opening. That's why placement is followed
by a read-back and retries. Three attempts over roughly 500 ms is the
smallest amount that reliably takes hold without windows visibly jittering.

`tolerance` prevents endless retries against apps with size increments
(terminals) or minimum sizes.

### On `conflict`

- `stack` — the new window is added to the zone; nothing gets displaced.
- `replace` — the new window takes over; the previous occupant moves to the
  profile's fallback zone.
- `skip` — the new window stays wherever the system opened it.

`honorManualOverride` is the courtesy rule: if the user drags a window out
themselves, the rule must not drag it back.

### On `dropzones`

The whole block is optional; a `config.json` without it loads unchanged and
gets the values shown above. Every individual field is likewise optional.

`activation` says **when** the zones appear. Two forms, one file:

- `{"showsWhile": "command"}` – the default since issue #23. The zones appear
  only while ⌘ is held down. Nothing happens without the key — the old
  "always shown while dragging, suppress with ⌥" gesture was deliberately
  swapped out (cost and reasoning in [dropzones.md](dropzones.md)).
- `{"showsUnless": "option"}` – the older polarity. The zones appear on every
  drag; the named key hides them. Anyone who wants the old gesture switches
  back to this.

`"none"` is allowed in both forms but has no meaningful effect:
`{"showsUnless": "none"}` means "never hide" (so the zones always appear),
while `{"showsWhile": "none"}` would fall back to "never show" — which
`enabled: false` already says. OpenZonr rejects neither; it keeps loading
instead, so that a hand-written or inherited `.none` never leaves anyone
without zones.

**Old configurations keep loading.** A `config.json` with the earlier field
`suppressionModifier: "option"` (instead of `activation`) is mapped on load
to `activation: {"showsUnless": "option"}` — the same polarity it expressed.
Only the new field gets written back out. If both fields happen to be present
in the file, the new one wins.

`offerRule` determines whether the panel „Diese App immer hier öffnen?"
("Always open this app here?") appears after a drop. **Since issue #23 the
default is `false`.** Instead of that follow-up prompt, every visible zone
carries a small pin marker: releasing on the marker writes the rule in the
same motion, releasing next to it is a one-time placement. The menu item
„Aktuelles Fenster festhalten" ("pin current window") writes the same rule
via the same `QuickPin` — this path remains for when the marker was missed.

`minimumDragDistance` prevents a mere click on a title bar from flashing up
the overlay.

`enabled` and `activation` together are what's offered under „Zonen beim
Ziehen" ("Zones while dragging") in the menu: „Aus" ("Off") is
`enabled: false`, „Nur mit gehaltener ⌘-Taste" ("Only while ⌘ is held") is
`{"showsWhile": "command"}`, „Bei jedem Ziehen" ("On every drag") is
`{"showsUnless": "none"}`. A different key can still be entered by hand; the
menu then shows it as its own, checked line instead of putting a checkmark in
the wrong place.

„Fenster automatisch platzieren" ("Place windows automatically") in the menu
also pauses dragging — the pause means everything, not just the automatic
placement.

Everything else — the choice of `CGEventTap` over `kAXMovedNotification` with
numbers, the behavior alongside Magnet, the ⌘ swap, and what about it remains
unmeasured — is covered in [dropzones.md](dropzones.md).

---

## Storage location

The search happens in this order; the first one found wins:

1. a path the caller explicitly passes (a command-line flag, a test),
2. the environment variable `OPENZONR_CONFIG`,
3. `~/Library/Application Support/OpenZonr/config.json`.

A leading `~` is resolved in the first two cases. Anyone who keeps their
configuration in a dotfiles repository would set, for example:

```sh
export OPENZONR_CONFIG=~/dotfiles/openzonr.json
```

If the file is missing, that's not an error but the normal state on first
launch — OpenZonr then asks, instead of showing an error message.

### Writing

Writes are atomic: first a temporary file in the target directory, then the
target file is replaced by it. If the process aborts, the old file remains
untouched. A half-written configuration would be worse than a stale one — the
old one can at least still be loaded.

The output is stable: keys sorted alphabetically, indented, with a trailing
newline. A changed zone therefore produces a short diff, not a reshuffled
file.

### Migration

The `version` field drives migration. On load, an older version is stepped
forward to the current state. Before a *write-back* migration, OpenZonr backs
up the original file alongside it as `config.json.v<old version>.backup`.

A version **newer** than the one the program knows about is rejected
outright, not partially read: a newer schema may have moved fields around,
and a half-understood configuration places windows where nobody wanted them.
In this case, only an OpenZonr update helps.

---

## Errors and warnings

On load, the whole file is checked and **all** findings are reported together
— not just the first one. Someone with three typos in their file should be
able to fix them in one pass, not restart three times.

Every finding names the location in the document where it occurred, e.g.
`profiles[office].roleBindings[2].zone`.

A distinction is made between:

- **Errors** — the configuration is unusable. Examples: a rule references a
  role that doesn't exist; a role binding points at a zone that doesn't exist
  in this display's chosen layout; two profiles share the same fingerprint; a
  `titlePattern` isn't a translatable regular expression.
- **Warnings** — the configuration is usable, but probably not meant this
  way. Examples: a role that no rule uses; a rule that is fully shadowed by a
  higher-priority one and can therefore never fire.

Warnings don't hold up loading.
