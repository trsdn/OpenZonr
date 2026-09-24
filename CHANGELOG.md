# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
the versioning follows [Semantic Versioning](https://semver.org/).

At release time, the entries under "Unreleased" are moved into a section for
the new version. The broker (`scripts/request.sh … --publish`) only
publishes when "Unreleased" is empty and a section exists for the version;
that section's text becomes the release notes.

## [Unreleased]

## [0.2.0] - 2026-09-24

### Added

- **A zone now has two rectangles: a target frame and a hit area.** Until
  now both were the same rectangle — where the window ends up, and where
  you have to release it. That makes a stack of overlapping zones
  unresolvable: the hit test picks the smallest containing zone, so a large
  zone that's completely covered by smaller ones becomes **unreachable**.
  Not hard to hit — unreachable, and no hit-test rule can fix that, because
  one layer always loses.

  The new `activationArea` field is optional and screen-relative like
  `frame`; if it's absent, it defaults to the target frame. It may lie
  outside the target frame, which lets a zone be triggered at the screen
  edge while the window lands elsewhere — *possible*, but **not tried**.
  Existing configurations behave unchanged; there is no schema change and
  no migration step
  ([#74](https://github.com/trsdn/OpenZonr/pull/74)).

- **Two new validation findings, both warnings.** `zoneUnreachable` flags a
  zone whose hit area is covered by the **union** of the hit areas of
  higher-priority zones — the case above, which used to pass silently
  before. `activationAreaDetached` flags a hit area that has no overlap
  with its own target frame: allowed, but more often a mistake. Neither one
  makes a configuration unusable.

- **The zone editor now understands hit areas and lets you drag zones
  across cells.** A `Zielrahmen | Trefferfläche` ("Target frame | Hit
  area") toggle on the same canvas; the other layer always stays visible as
  a faint dashed outline, because for edge-triggered zones, the gap between
  the two is the only thing that matters. Dragging across cells creates a
  zone or redefines the selected one; a click with no movement produces a
  single cell. During a gesture, the snap dimensions are shown on the zone
  itself — as a fraction and in twelfths
  ([#75](https://github.com/trsdn/OpenZonr/pull/75)).

### Fixed

- **Crashes on clicking the menu bar icon.** Four reports, one bug, and it
  was in our own code, not Apple's: `AXUIElementCopyElementAtPosition` on
  the **system-wide** element ran inside `Task.detached`. When the hit
  point lands on one of our own elements — our own menu bar icon —
  AppKit doesn't service the query over IPC; it services it in-process, on
  the **calling** thread. Its Accessibility code is main-thread-bound;
  combined with the main thread, which walks the same status item on
  click, two threads ended up mutating the same objects.

  Now the window server answers the ownership question before every AX
  call (pure CoreGraphics), and the query is scoped to
  `AXUIElementCreateApplication(pid)` — a process guaranteed to belong to
  someone else. The earlier geometric safeguard only covered the **main**
  screen's menu bar and was bypassed on every additional one
  ([#72](https://github.com/trsdn/OpenZonr/pull/72),
  [#69](https://github.com/trsdn/OpenZonr/issues/69)).

  *Not claimed:* that the crash is gone for good. The causal chain is
  backed by four reports, and the code in question is verifiably no longer
  reached; that's confirmed only after extended use. #69 stays open.

- **Safari refused to accept a size change** — the window jumped to a
  different spot on every attempt and kept its old size. The frame was
  written as position, size, position; Safari re-derives its size as soon
  as a position write follows, and discards the one it was just given.
  Every retry wrote the same self-defeating sequence — the visible jumps
  *were* the attempts.

  The trailing position write is gone. In addition,
  `AXEnhancedUserInterface` is briefly switched off around the write and
  restored afterward: that flag makes Safari animate every frame change,
  and the size write was landing mid-animation. Measured: with the flag,
  0 of 4 hits on the first attempt; without it, 4 of 4 with 0 deviation.
  When VoiceOver or Switch Control is running, this intervention is
  skipped entirely
  ([#73](https://github.com/trsdn/OpenZonr/pull/73)).

- **The resize handle in the zone editor didn't track the pointer and
  jittered back and forth.** The gesture measured against its own view,
  whose size is computed from the gesture currently in progress — the
  handle kept drifting out from under the pointer. Both gestures now
  measure in the canvas's fixed coordinate space, and dragging the handle
  no longer also triggers a move
  ([#77](https://github.com/trsdn/OpenZonr/pull/77)).

- **In the overview, the labels of stacked zones overlapped each other** —
  „Rechts außen" and „Recht oben" turned into `Rechts:oben`, „Vollbild"
  over „Links" turned into `Linksild`. That can't be fixed by rearranging
  the labels: two rectangles in the same place have the same free corner.
  The overview now shows the overlap instead of drawing against it — the
  zones of a screen are split into overlap-free groups, and each group gets
  its own card, labeled „Ebene n von m" ("Layer n of m"). Shared edges
  don't count as overlap here, otherwise every ordinary column split would
  shatter into separate layers
  ([#80](https://github.com/trsdn/OpenZonr/pull/80)).

- **Small things in the editor:** duplicated field labels („Breite Breite"
  — "Width Width"), overlapping zone names on stacked zones, one handle
  per zone instead of only on the selected one, and the origin label that
  sat on top of the zones
  ([#76](https://github.com/trsdn/OpenZonr/pull/76),
  [#78](https://github.com/trsdn/OpenZonr/pull/78)).

## [0.1.2] - 2026-09-21

### Added

- **The app has an icon.** Until now, `OpenZonr.app` showed the generic
  placeholder symbol everywhere — in the Finder, in the list under System
  Settings → Privacy & Security → Accessibility, in the update dialog, in
  the DMG window. The new icon shows a window split into three zones at a
  25/50/25 ratio — the same split as the "wide" template — with the middle
  zone highlighted in accent blue, like the drop target under the pointer
  while dragging. It's generated from code
  (`swift Scripts/make-icon.swift`), ships in the repo as
  `Resources/AppIcon.icns`, and is copied by `Scripts/bundle.sh` into
  `Contents/Resources` before signing; `Info.plist` points to it via
  `CFBundleIconFile`
  ([#55](https://github.com/trsdn/OpenZonr/issues/55)).
  Also present in the published bundle: the broker copies the file via the
  `app_icon` profile field (trsdn/macos-notarization-broker#66) into
  `Contents/Resources` before signing. Until the icon shows up in the
  Finder, macOS may still display the old placeholder symbol from its
  cache (`killall Finder`).
- **A „Letzter Zug" ("Last drag") line in the menu that says why zones
  didn't appear.** „Letzter Zug: keine Zonen — ⌘ war nicht gedrückt."
  ("Last drag: no zones — ⌘ wasn't held."), „… kein Fenster unter dem
  Zeiger erkannt." ("… no window detected under the pointer."), „…
  Bewegung nicht als Fensterzug erkannt." ("… motion not recognized as a
  window drag."), „… losgelassen, bevor sich das Fenster bewegt hat." ("…
  released before the window moved."). Four causes that used to all look
  the same: nothing happens. `EventTapDragTracker` got a second return
  path (`onOutcome`) for presses that never make it to a drag — at most
  one sentence per press, none for an ordinary click, and still no AX call
  inside the tap callback
  ([#26](https://github.com/trsdn/OpenZonr/issues/26),
  [#37](https://github.com/trsdn/OpenZonr/issues/37)).

### Changed

- **The menu bar app's menu has been reordered and now speaks plain
  language.** Instead of a state name with a counter („Kein Profil passt —
  2 Profile in der Konfiguration" — "No profile matches — 2 profiles in
  the configuration"), there is now **one** line that says where things
  stand, and at most one button that says what to do: „Zugriff fehlt —
  ohne ihn kann OpenZonr keine Fenster bewegen" ("Access missing — without
  it OpenZonr can't move any windows") with „Zugriff freigeben …" ("Grant
  access…"), „Bereit — Setup „Schreibtisch"" ("Ready — Setup "Desk""),
  „Kein Setup passt zu den angeschlossenen Bildschirmen" ("No setup
  matches the connected screens") with „Was ist zu tun? …" ("What now?
  …"), „Pausiert" ("Paused"). At the very top, in **every** state, sits
  „OpenZonr" with the version from the bundle
  ([#56](https://github.com/trsdn/OpenZonr/issues/56)).
  Everything technical and rare — choosing a setup by hand, recent
  placements, reloading the configuration, status and permission,
  autostart, the update settings — lives under „Mehr" ("More"). Nothing
  was dropped; a pending update and the warning about a second window
  manager both stay at the top, because both demand a decision.
- **Two toggles for dragging became one question: when do the zones show
  up?** „Fenster in Zonen ziehen" ("Drag windows into zones") plus an
  invisible activation rule in the file are replaced by three lines under
  „Zonen beim Ziehen" ("Zones while dragging"): „Bei jedem Ziehen" ("On
  every drag"), „Nur mit gehaltener ⌘-Taste" ("Only while holding ⌘"),
  „Aus" ("Off"). The checkmark sits on the state actually **in effect**
  from the loaded configuration. A hand-written rule that matches none of
  the three (say, "only with ⌥") gets its own, checked line instead of a
  wrong checkmark — even while „Aus" applies, and then that line is the
  way back: clicking it turns dragging on without touching the rule. The
  selected state appears in the parent line's label („Zonen beim Ziehen:
  nur mit ⌘" — "Zones while dragging: only with ⌘"), so it's visible
  without expanding. It's written immediately, straight to the file, just
  like the toggle used to be
  ([#41](https://github.com/trsdn/OpenZonr/issues/41)).
- Menu entries renamed: „Regeln bearbeiten …" ("Edit rules…") is now
  „Zonen und Regeln bearbeiten …" ("Edit zones and rules…"), „Aktuelles
  Fenster hier festhalten" ("Pin current window here") is now „Aktuelles
  Fenster festhalten" ("Pin current window"), „Platzierung pausieren"
  ("Pause placement") has been flipped to „Fenster automatisch
  platzieren" ("Automatically place windows").

## [0.1.1] - 2026-09-20

### Fixed

- **Monitors without a serial number are now recognized despite a
  drifting port number.** The number (`CGDisplayUnitNumber`) shifts when
  software displays come and go (measured: the same monitor, the same
  cable, 0 on 29.08. and 1 on 19.09.). After that, no profile matched
  anymore, and the entire dropzone feature (overlay while dragging and
  the zone menu on the green button) disappeared without any message. A
  monitor without a serial number is now recognized independently of
  `portIndex` when the vendor and model appear exactly once in both the
  configuration and the connected screens; an exact match wins first.
  Identical monitors without a serial number still depend on `portIndex`;
  unknown displays still lead to „kein Profil" ("no profile") — it does
  not guess.

### Changed

- `openzonr displays` now accepts `--config <path>` and reports a case
  recognized this way as one line („konfiguriert als port=0, aktuell
  port=1: erkannt, weil eindeutig" — "configured as port=0, currently
  port=1: recognized because unambiguous"); the same line appears in the
  watch diagnostics.

## [0.1.0] - 2026-09-19

First release. Existing installations without an updater have to be
replaced by hand once; starting with the second release, the app updates
itself.

### Added

- **In-app updates from GitHub Releases** via AppUpdater 4.1.2 (#47): menu
  items „Nach Updates suchen…" ("Check for updates…") and „Automatisch
  nach Updates suchen" ("Automatically check for updates") (on by
  default). Before installing, the app halts observation and pending
  placements. Installed versions without an updater have to be replaced
  by hand once.
- Zone editor with a grid, edge snapping, coverage checking, and
  templates; an overview „Wohin geht was?" ("What goes where?") and a
  dry-run line in the rule editor.

### Changed

- The executable inside the app bundle is now called `OpenZonrApp`
  (previously `OpenZonr`), because the broker equates the product name
  with the file name. Path, bundle identifier, and signature stay the
  same.
- The commitment on the Accessibility grant now reads "normally survives
  a rebuild"; if it goes invalid afterward, only removing and re-adding
  the entry helps (#35).

### Fixed

- Pending placements no longer keep running after a pause, a stop, a
  reload, or a newer request (#38).
- On „Ersetzen" ("Replace"), the previous occupant is now actually moved
  to the fallback, and zone occupancy follows the real outcome: occupancy
  is cleaned up when apps quit and when placements fail (#40, #45).
- The menu toggle for dropzones now takes effect immediately, even if the
  editor was already open (#41).
- The editor no longer overwrites an externally changed configuration
  after a reload; on conflict, saving is blocked (#42).
- Dropping and the Zoom menu now respect the layout margin the same way
  the automatic path does (#43).
- The permission check no longer restarts drag tracking every two
  seconds (#44).
- Dragging window content (text, scrollbar, resize) no longer triggers
  placement or pinning; a window drag is now detected from actual window
  movement (#37). Measured only in TextEdit so far; as a result, the
  overlay now appears roughly 150 ms later.
- The identity of a monitor without a serial number no longer depends on
  the current display mode; existing configurations are still recognized
  (#39).
