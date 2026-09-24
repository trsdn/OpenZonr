# OpenZonr

[![License](https://img.shields.io/github/license/trsdn/OpenZonr)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)](Package.swift)
[![CI](https://github.com/trsdn/OpenZonr/actions/workflows/ci.yml/badge.svg)](https://github.com/trsdn/OpenZonr/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/trsdn/OpenZonr)](https://github.com/trsdn/OpenZonr/releases/latest)
[![Conformance](.github/badges/conformance.svg)](docs/self-assessment.md)

**Status: a working command-line tool and a menu bar app.**
The data model, configuration store, rule engine, and the Accessibility and
CoreGraphics integration are built and tested.

**The core works, and it's measured.** On a real four-display desk, TextEdit
and Outlook land in their zone at launch — even with the menu bar app running
as a live process and against the target app's own position memory. Outlook
resists on the first write and only settles on the second attempt; the retry
loop is therefore load-bearing, not decoration. The numbers, the cross-checks,
and how they were obtained are in
[`docs/tracer-bullet.md`](docs/tracer-bullet.md).

Two limitations worth knowing before trying it:

1. **It needs a signed bundle.** `Scripts/bundle.sh` handles that. An
   unsigned binary loses its Accessibility permission after every rebuild —
   it launches, but sees no windows. Without a Developer ID certificate,
   OpenZonr is currently unusable.
2. **The interface is a menu bar app, nothing more.** It hosts the watcher,
   shows status, profile, and recent placements, and can start at login on
   request — [`docs/menueleisten-app.md`](docs/menueleisten-app.md). Rules
   are still edited as JSON, and there are no drag-and-drop dropzones.

OpenZonr is a window manager for macOS with dropzones. What sets it apart
from everything else out there fits in a single sentence:

> **Apps open by themselves in the zone meant for them.**

## The Problem

Existing tools solve moving, not opening:

> "I want Outlook to always open in Zone 2. Today it opens wherever, unless I
> drag it into the dropzone myself."

That dragging is exactly the sore spot. Every app, every day, after every
restart, after every monitor change. Defining zones is a solved problem —
getting windows to land there automatically is not.

## The Approach

1. **Detect windows** — `NSWorkspace.didLaunchApplication` plus an
   `AXObserver` per app on `kAXWindowCreatedNotification`.
2. **Find a rule** — match criteria such as bundle ID, title regex, subrole,
   window size.
3. **Resolve the role** — rules point to a *role* (e.g. "Communication"), not
   a zone. The active profile translates the role into display + zone.
4. **Place the window** — `kAXPositionAttribute` / `kAXSizeAttribute`, with a
   retry loop against apps that resize themselves again right after opening.

Everything else is in **[docs/konzept.md](docs/konzept.md)**.

## Comparison

| Tool | What it does | What's missing |
|---|---|---|
| **Rectangle / Rectangle Pro** | Places windows into halves, thirds, or custom zones via shortcut or drag. Rectangle Pro can apply app rules on launch. | No role indirection: rules are tied to concrete screen regions and have to be maintained per setup. No EDID-stable monitor identity. |
| **yabai** | A full-featured tiling window manager with a scripting language; very powerful. | Partially requires disabling SIP. Automatic tiling instead of fixed, hand-drawn zones. Rules are script code, not shareable configuration. |
| **Amethyst** | Automatic tiling via layout algorithms, app rules mostly as float exceptions. | You pick a layout, not freely placed zones. No "this app belongs here, regardless of what else is open." |
| **FancyZones (Windows)** | The direct conceptual model, including app-to-zone assignment. | Doesn't exist for macOS — and its layout assignment depends on resolution and monitor order rather than a stable monitor identity. |
| **Moom, Magnet, Swish** | Convenient manual arranging. | Explicitly manual. |

OpenZonr is deliberately **not** a tiling window manager. It doesn't
automatically arrange everything; instead it reliably places the handful of
apps you have a clear idea about where they belong — and leaves the rest
alone.

Two things are at the core of it:

- **Roles instead of zones.** App rules are written once, not duplicated per
  setup. Each profile maps roles onto its own zones.
- **Monitor identity via EDID.** A profile is recognized by the actual set of
  connected monitors, not by position, index, or resolution. Replugging
  changes nothing.

## Project Structure

```
Package.swift                 SwiftPM manifest (macOS 14+)
Package.resolved              Checked in: the notarization broker builds
                              against it (see "Updates and Publishing")
Sources/OpenZonrCore/
  Geometry/                   RelativeRect, Zone, Layout
  Display/                    DisplayIdentity, SetupFingerprint, arrangement
  Roles/                      ZoneRole, RoleBinding
  Rules/                      WindowMatch, PlacementAction, PlacementRule
  Profiles/                   Profile
  Configuration/              Configuration, storage, atomic writes
    Migration/                Step chain between schema versions
  Validation/                 Validation with document paths
    Checks/                   The individual checks
  Placement/                  Filter, rule engine, profile and zone
                              resolution, retry loop
Sources/OpenZonrMac/          The macOS integration, used by both interfaces
  Accessibility/              AXObserver, window inventory
  Displays/                   CGDisplay, screen identity
  Watch/                      WatchEngine — observation and placement
  CommandLine/                The subcommands
  Support/                    Logging, configuration path, signature status
Sources/OpenZonrApp/          Menu bar app (MenuBarExtra, LSUIElement)
  Info.plist                  The bundle's Info.plist — the broker expects
                              it exactly here
  Update/                     In-app updates (AppUpdater), due-date logic
                              and menu text as a pure decision
Sources/openzonr/             `swift run openzonr` for development
Tests/OpenZonrCoreTests/      Unit tests; Support/ holds fixtures
Tests/OpenZonrMacTests/       The purely computational parts of the macOS layer
Resources/AppIcon.icns        The app icon, generated from Scripts/make-icon.swift
Scripts/bundle.sh             Builds and signs the bundle
Scripts/make-icon.swift       Draws the app icon (see "Building")
Examples/                     Example configuration (Office / Home / On the go)
docs/                         Concept, configuration, tracer bullet, open questions
```

`OpenZonrCore` is the platform-independent, tested half. `OpenZonrMac`
contains everything that talks to macOS — and is shared between both
interfaces instead of being rewritten by each: the observation and placement
logic in it is measured at a real desk, and three of its details could only
be found by measuring.

**Why Swift Package Manager and no Xcode project?** The manifest is text, so
it's diffable and reviewable, and there are no `.pbxproj` merge conflicts.
Above all, `swift build` and `swift test` stay the whole truth — two build
systems would be two truths, one of which drifts out of date unnoticed.
`Scripts/bundle.sh` produces the signed bundle without Xcode. Full detail in
[docs/menueleisten-app.md](docs/menueleisten-app.md).

**The bundle contains exactly one binary**, and it's both: with no
arguments, the menu bar app; with a subcommand, the command-line tool. The
reason is how macOS grants permissions — they apply to a program at its
path, and two binaries would mean two separate grants.

## Building

```bash
swift build
swift test
```

Minimum requirement: macOS 14, Swift 6. The APIs used (Accessibility,
`CGDisplay*`, `NSWorkspace`) are considerably older; macOS 14 is set for the
later UI layer (Observation, `MenuBarExtra`).

### Regenerating the App Icon

`Resources/AppIcon.icns` ships ready-made in the repo, but it's generated
from code rather than from a graphics file that nobody can open anymore:

```bash
swift Scripts/make-icon.swift
```

The script draws with CoreGraphics, writes every size from 16 to 1024 px
(each also @2x) into an `.iconset`, and has `iconutil` build the `.icns`
from that. It needs nothing that doesn't ship with macOS. Anyone who wants
to change the artwork edits `drawArtwork` and reruns the script; the
generated `.icns` belongs in the commit, because `Scripts/bundle.sh` reads
it.

**macOS remembers icons.** A bundle that has already shown up in the Finder
with the placeholder icon can keep showing it even though the `.icns` is in
the bundle — LaunchServices and the icon cache don't catch up immediately.
`killall Finder` usually helps; otherwise logging out helps. What's actually
measured here is only that `NSWorkspace.icon(forFile:)` returns the correct
icon immediately for a bundle freshly built at a new path; how stubborn the
cache is at an old path was not checked.

## The `openzonr` Command-Line Tool

Four subcommands: three for diagnostics, one for the tracer bullet.

```bash
swift run openzonr --help
```

### Unlocking Accessibility

Without permission, no tool can read or move windows. **And without a
signature, the permission doesn't take effect** — that's the stumbling
block that cost the most time while building this tool.

```bash
Scripts/bundle.sh
```

The script builds, packages `~/Applications/OpenZonr.app`, and signs it with
the first Developer ID certificate it finds (overridable via
`CODESIGN_IDENTITY`). Then, once:

1. System Settings → Privacy & Security → **Accessibility**
2. Add `~/Applications/OpenZonr.app` and enable it
3. Verify — the same way the app will actually launch later:

   ```bash
   open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
   cat /tmp/openzonr.txt      # must report "granted"
   ```

   Launched from the shell, the same binary measures something different:
   there it inherits the terminal's trust, and `AXIsProcessTrusted()` reports
   `true` without any window actually being readable. `selftest` therefore
   reports the launch path.

Why the detour through a bundle:

- **An unsigned binary gets a new checksum on every `swift build`.** The
  checkbox stays checked but now refers to a different program. The
  signature instead binds to the bundle identifier and team, and normally
  survives a rebuild. That's not guaranteed: on 30.08.2026 the entry went
  invalid after a rebuild even though the path and signature stayed the
  same. If `openzonr selftest` then reports „degradiert" ("degraded"),
  **remove and re-add** the entry in Accessibility; just unchecking and
  rechecking the box isn't enough. Why, is not settled (Issue #35).
- **The grant applies to the bundle at its path.** That's why
  `Scripts/bundle.sh` places it under `~/Applications` rather than in
  `.build`: there it survives `swift package clean`, a second clone of the
  repo, and moving the working directory. A bundle at a new path has to be
  re-granted, even with an identical signature.
- **`AXIsProcessTrusted()` can report `true` without access actually
  working.** Every app then returns, for `AXWindows`, only a proxy element
  with role `AXApplication` and no position or size. Launched from the
  shell, the process inherits the terminal's trust, but window access
  doesn't inherit it. `openzonr` detects this state and explains it,
  instead of silently doing nothing. Details in
  [docs/tracer-bullet.md](docs/tracer-bullet.md).
- For an existing entry from an unsigned run: **remove and re-add it.** Just
  re-checking the box isn't enough.

### `openzonr displays` — which monitors are there?

Shows every connected display with its stable identity, resolution, backing
scale, `frame`, and `visibleFrame`, plus the setup fingerprint computed from
them.

```bash
swift run openzonr displays
```

```
Display 1 von 4  — C49RG9x
  Identität   fallback  vendor=19501 model=3996 5120×1440 port=1
              ⚠ Seriennummer ist 0 — Identität über Vendor, Modell,
                Auflösung und Port-Index
  Auflösung   5120×1440 @1.0x
  frame       (0, 0, 5120, 1440)
  visibleFrame (0, 65, 5120, 1344)
```

Virtual displays are flagged as such. With `--config-fragment`, the command
instead outputs a ready-made `displays` fragment in configuration format
that can be adopted directly:

```bash
swift run openzonr displays --config-fragment
```

**This is the authoritative way to get real identities.** The numbers in
`Examples/openzonr.config.json` are made up.

### `openzonr windows` — what do the windows look like?

Lists the windows of running apps with bundle ID, title, subrole, position,
size, and the display they occupy. This is how you find match criteria for
rules — for example, how Outlook's main, compose, and reminder windows
differ.

```bash
swift run openzonr windows
swift run openzonr windows --bundle com.microsoft.Outlook
```

### `openzonr watch` — the tracer bullet

Watches newly opened windows and places them according to the
configuration's rules. Runs in the foreground and logs every step.

```bash
swift run openzonr watch
swift run openzonr watch --config ~/my-config.json
swift run openzonr watch --dry-run     # computes and logs, moves nothing
```

Configuration path, in this order: `--config`, then `OPENZONR_CONFIG`,
otherwise `~/Library/Application Support/OpenZonr/config.json`.

### `openzonr dragprobe` — which path reports a drag better?

Measures `CGEventTap` and `kAXMovedNotification` side by side: event count,
rate, largest gap, latency, and whether release arrives as an event. This
was the basis for deciding on dropzones — the numbers are in
[docs/dropzones.md](docs/dropzones.md).

```bash
swift run openzonr dragprobe --seconds 5            # drag a window by hand
swift run openzonr dragprobe --seconds 3 --synthesize   # without a hand on the device
swift run openzonr dragprobe --seconds 5 --out /tmp/dragprobe.txt
```

Without `--synthesize`, you actually have to drag during the measurement
window. If the report then shows zero events for both paths, nothing was
measured — either the Accessibility grant is missing, or nothing was
dragged.

### One Run from Start to Finish

```bash
# 1. Build, sign, and grant access (see above — without a signature
#    the tool sees no windows)
Scripts/bundle.sh
OZ=~/Applications/OpenZonr.app/Contents/MacOS/OpenZonrApp

# 2. Determine the real displays and print them as a fragment
"$OZ" displays --config-fragment > /tmp/displays.json

# 3. Create the configuration: adopt the fragment, add layouts, roles,
#    profiles, and rules. Examples/openzonr.config.json serves as a
#    template — but with your own identities.
#    Suspected virtual displays are probably already listed in the
#    fragment under ignoredDisplays; that list should be checked,
#    not adopted blindly.
mkdir -p ~/Library/Application\ Support/OpenZonr
$EDITOR ~/Library/Application\ Support/OpenZonr/config.json

# 4. Dry-run: is the right profile chosen?
"$OZ" watch --dry-run

# 5. Verify the match criteria for the rules
"$OZ" windows --bundle com.microsoft.Outlook

# 6. Go live, then restart the target app
"$OZ" watch
```

## The Menu Bar App

The same binary, launched without arguments: an icon in the menu bar that
hosts the watcher instead of running it in the foreground of a terminal.

```bash
Scripts/bundle.sh
open -n ~/Applications/OpenZonr.app
```

In the menu, top to bottom:

- **`OpenZonr <version>`** — name and version, first in every state
  ([#56](https://github.com/trsdn/OpenZonr/issues/56)), not clickable.
- **A status line** in plain language, with at most one button:
  „Bereit — Setup „Schreibtisch"" ("Ready — Setup "Desk""), „Zugriff fehlt —
  ohne ihn kann OpenZonr keine Fenster bewegen" ("Access missing — without
  it, OpenZonr can't move any windows") with „Zugriff freigeben …" ("Grant
  access…"), „Kein Setup passt zu den angeschlossenen Bildschirmen" ("No
  setup matches the connected screens") with „Was ist zu tun? …" ("What now?
  …"), „Pausiert" ("Paused").
- **Fenster automatisch platzieren** (Automatically place windows) — halts
  placement without quitting the app.
- **Zonen beim Ziehen** (Zones while dragging) — „Bei jedem Ziehen" ("On
  every drag"), „Nur mit gehaltener ⌘-Taste" ("Only while holding ⌘"), „Aus"
  ("Off"). The checkmark sits on the state actually in effect from the
  configuration.
- **Letzter Zug** (Last drag) — a grey sentence describing how the most
  recently observed drag turned out („keine Zonen — ⌘ war nicht gedrückt"
  ("no zones — ⌘ wasn't held"), „kein Fenster unter dem Zeiger erkannt" ("no
  window detected under the pointer")). Diagnostics for when zones don't
  appear.
- **Aktuelles Fenster festhalten** (Pin current window) and **Zonen und
  Regeln bearbeiten …** (Edit zones and rules…).
- **Mehr** (More) — choose a setup by hand (applies for the session and is
  deliberately not saved), recent placements with the full log stream,
  reload configuration, status and permission, start at login (via
  `SMAppService`), **Nach Updates suchen …** (Check for updates…) and
  **Automatisch nach Updates suchen** (Automatically check for updates)
  (see [Updates and Publishing](#updates-and-publishing)).
- **OpenZonr beenden** (Quit OpenZonr).

If an update is ready, it appears — along with „Installieren" ("Install")
and „Später" ("Later") — at the **top** of the menu, even without anyone
having checked; it demands a decision.

If permission is missing, a window opens once at launch that explains the
specific state and offers the way to resolve it. That's the most common
hurdle and is described in detail in
[docs/menueleisten-app.md](docs/menueleisten-app.md) — which also states
what about the app is measured and what is not.

## Updates and Publishing

OpenZonr updates itself from this repository's GitHub Releases
([#47](https://github.com/trsdn/OpenZonr/issues/47)). Underneath sits
[mxcl/AppUpdater](https://github.com/mxcl/AppUpdater) 4.1.2, pinned exactly,
with a checked-in `Package.resolved`.

### What the App Does

It wakes up hourly and checks at most once a day. If it finds a newer
release, it downloads and verifies it in the background, then offers
**Installieren und neu starten** ("Install and restart"). Before the swap,
it halts its own work: window observation off, pending placements
discarded, drag tracker off — otherwise a half-finished job could still be
moving windows while the bundle is being replaced.

The **Automatisch nach Updates suchen** ("Automatically check for updates")
toggle is on by default and is saved in preferences.

An update is only adopted if the Developer ID team, signature identifier,
and bundle identifier match the running app. A GitHub attestation
(`GitHubAttestationPolicy`) is deliberately **not** required: the release is
produced in the notarization broker's repository, so there is no
provenance from `trsdn/OpenZonr` at all — and for `swift build` products,
AppUpdater's attestation check ends in a `fatalError` anyway
([OpenWritr#31](https://github.com/trsdn/OpenWritr/issues/31)).

### Cutting a Release

Building, signing, notarizing, and uploading is done by the
[notarization broker](https://github.com/trsdn/macos-notarization-broker).
It's triggered **from inside the broker repository** with its own script —
on the operator's instruction, not necessarily by their own hand:

```bash
cd ../macos-notarization-broker-release
scripts/request.sh openzonr vX.Y.Z --publish
```

The script requires `gh` and `python3`, a logged-in `gh` session, and the
broker's `main` branch — from any other branch it refuses to run. Without
`--publish`, the verified files land only locally in `broker-artifacts`;
with `--publish`, it creates the GitHub release for the tag if it doesn't
exist yet, and attaches to it. It uses the caller's own login for that; the
broker workflow itself never writes to a source repository.

Two copies of the broker exist side by side. Only
`macos-notarization-broker-release` knows the `openzonr` profile; the older
`macos-notarization-broker` aborts with a usage message, because `openzonr`
isn't on its allowlist.

The broker profile is called `openzonr`. It builds from this repository,
uses `Sources/OpenZonrApp/Info.plist`, checks `Package.resolved` byte for
byte against its own verified copy (`dependency_lock`), and copies
`AppUpdater_AppUpdater.bundle` to `Contents/Resources`
(`nested_resource_bundles`). Among the artifacts, exactly one has to be
named `OpenZonr-{version}.dmg` — AppUpdater only picks up an attachment
with that exact name.

If `Package.resolved` has changed here, the broker's copy has to be updated
first; otherwise the run aborts before it even builds.

### The First Two Releases

- **The first release is installed by hand.** What's installed today has no
  updater yet and therefore can't get itself there.
- **Only from the second release on** can the path through the menu even be
  observed. Before that, there's nothing to check against — a full run is
  therefore **not measured** until then.
- **The Accessibility grant only survives** if the release is signed with
  the same Developer ID and the same Designated Requirement as what was
  installed:

  ```
  identifier "com.trsdn.openzonr" and anchor apple generic
    and certificate leaf[subject.OU] = <TEAM>
  ```

  Switching from an ad hoc signature to Developer ID doesn't satisfy
  that — anyone who has been using an ad hoc signed bundle has to re-grant
  once. A rebuild at the same path with the same Developer ID normally
  survives the grant, but that's not guaranteed either
  ([#35](https://github.com/trsdn/OpenZonr/issues/35)).

### Built Locally = Published

`Scripts/bundle.sh` builds the same bundle the broker builds: the same
`Sources/OpenZonrApp/Info.plist` (only `__VERSION__` gets substituted), the
binary under `Contents/MacOS/OpenZonrApp`, and
`AppUpdater_AppUpdater.bundle` under `Contents/Resources`. A different
destination can be passed as the first argument — useful for a trial run
that doesn't touch the granted installation:

```bash
Scripts/bundle.sh "$(mktemp -d)/OpenZonr.app"
```

**One spot has drifted out of sync since the app got an icon** (Issue
[#55](https://github.com/trsdn/OpenZonr/issues/55)): `Scripts/bundle.sh`
copies `Resources/AppIcon.icns` to `Contents/Resources`, but the broker
adapter `assemble_menu_bar_swiftpm` doesn't — it only copies the binary,
the resource bundles named in the profile (`nested_resource_bundles`), and
the `Info.plist`. So a locally built bundle has the icon, but a published
one currently doesn't: it carries `CFBundleIconFile`, but the file is
missing, and macOS falls back to the placeholder. That's not a bug this
repo can fix — the adapter in `trsdn/macos-notarization-broker` needs to
bring the icon along from the source repo, the way `assemble_openswitchr`
and `assemble_openwritr` already do.

## Roadmap

| What | Status |
|---|---|
| Configuration: load, validate, write atomically, migrate | done |
| Rule engine, profile and zone resolution | done |
| Display identity and setup fingerprint | done, checked at a real desk |
| Window detection via `NSWorkspace` and `AXObserver` | done, measured: 124 ms to the observer for TextEdit, 2.2 s for Outlook |
| Command-line diagnostics (`displays`, `windows`) | done |
| Signing, so the grant normally survives rebuilds | done, `Scripts/bundle.sh`; not guaranteed (Issue #35) |
| Placement with retry loop | **done and measured on a real window**: TextEdit 1 attempt; Outlook 2 attempts once the window is actually draggable — the loop is genuinely exercised |
| Menu bar app with autostart | built, [#8](https://github.com/trsdn/OpenZonr/issues/8) — status, setup selection, pause, autostart, recent placements; placement with the app running **re-measured** (29.08.2026), see [docs/menueleisten-app.md](docs/menueleisten-app.md) |
| Editing rules without JSON | built, [#9](https://github.com/trsdn/OpenZonr/issues/9) — „Aktuelles Fenster festhalten" ("Pin current window") plus an editor for rules, roles, and zones; the core is measured headless, the interface not re-measured — it needs a hand on the mouse, not the grant anymore, see [docs/regel-editor.md](docs/regel-editor.md) |
| In-app updates from GitHub Releases | built, [#47](https://github.com/trsdn/OpenZonr/issues/47) — AppUpdater 4.1.2, menu entries, halting before the bundle swap; due-date logic, the default, menu text, and the "halt first, then install" order are tested. A **real run is not measured**: that requires a broker profile and a first release, both still missing |
| Drag-and-drop dropzones | built, [#10](https://github.com/trsdn/OpenZonr/issues/10) — overlay while dragging, drop uses the same placement as the automatic path, then „immer hier öffnen?" ("always open here?"); `CGEventTap` measured against `kAXMovedNotification` (the tap reports the release, Accessibility doesn't), a real drag not re-measured — it needs a hand on the mouse, not the grant anymore, see [docs/dropzones.md](docs/dropzones.md) |

The order was chosen deliberately: signing first, so placement becomes
measurable at all, and only then an interface. That paid off — the
measurement surfaced three bugs, all of which produced an empty log instead
of an error message, and an interface would only have covered them up.
They're described in [docs/tracer-bullet.md](docs/tracer-bullet.md).

## Further Reading

- [docs/konzept.md](docs/konzept.md) — architecture, rule model, monitor
  handling
- [docs/konfiguration.md](docs/konfiguration.md) — field reference and an
  annotated walkthrough of the example configuration
- [docs/menueleisten-app.md](docs/menueleisten-app.md) — the app: what it
  can do, why it's built this way, and what about it is measured
- [docs/regel-editor.md](docs/regel-editor.md) — editing rules, roles, and
  zones without JSON; decisions, deviations, and the state of measurement
- [docs/dropzones.md](docs/dropzones.md) — dragging windows into zones with
  the mouse; `CGEventTap` versus `kAXMovedNotification` with numbers, the
  behavior next to Magnet, and what about it is unmeasured
- [docs/tracer-bullet.md](docs/tracer-bullet.md) — what the tracer bullet
  covers, what's missing, and the state of measurement
- [docs/offene-fragen.md](docs/offene-fragen.md) — what hasn't been decided
  yet

## Language and Privacy

Primary language: English. This repository, its documentation, and its
contributor surfaces are English. The app's user interface still hardcodes
German text — that has not changed, and proper localization is tracked in
[#83](https://github.com/trsdn/OpenZonr/issues/83).

OpenZonr collects no user data and sends none: no telemetry, no analytics,
no crash reports. Window titles, bundle IDs, and displays stay on the
machine. The configuration lives in
`~/Library/Application Support/OpenZonr/config.json` (overridable with
`--config` or `OPENZONR_CONFIG`), the app's preferences in the UserDefaults
domain `com.trsdn.openzonr`. To delete: remove the
`~/Library/Application Support/OpenZonr` folder and run
`defaults delete com.trsdn.openzonr`. The only network connection is the
update check against this repository's GitHub Releases
([Updates and Publishing](#updates-and-publishing)); it can be turned off in
the menu via „Automatisch nach Updates suchen" ("Automatically check for
updates"). There is no third party that receives user content.

## License

MIT — see [LICENSE](LICENSE).
