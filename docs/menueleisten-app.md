# The Menu Bar App

The interface to [`openzonr watch`](../README.md#openzonr-watch--the-tracer-bullet):
an icon in the menu bar that houses the watcher instead of running it in the
foreground of a terminal. Implemented for
[#8](https://github.com/trsdn/OpenZonr/issues/8).

This document records the decisions that had to be made along the way and —
separately — what has actually been measured about the app and what hasn't.

## What it can do

| | |
|---|---|
| **Header** | "OpenZonr" plus the version from the bundle, the first entry in **every** state ([#56](https://github.com/trsdn/OpenZonr/issues/56)). |
| **State** | The icon distinguishes five cases: active, paused, no permission, no configuration, no profile matches. The menu shows **one** line about it in plain language and at most one button. |
| **Setup** | The detected setup (called a profile in the configuration) appears in the state line; any configured one can be picked by hand under „Mehr → Setup" (More → Setup). |
| **Automation** | „Fenster automatisch platzieren" (place windows automatically) pauses and resumes placement without quitting the app. The watcher keeps running and logging, but moves nothing. |
| **Zones while dragging** | Three lines spell out **when** the zones appear: „Bei jedem Ziehen" (on every drag), „Nur mit gehaltener ⌘-Taste" (only while holding ⌘), „Aus" (off). The chosen state shows in the parent line's label ("Zonen beim Ziehen: nur mit ⌘" — zones while dragging: only with ⌘), so it's visible without expanding the menu. The checkmark sits on the effective state from the loaded configuration; a hand-written rule that matches none of the three gets its own line — **even while "Aus" (off) applies** — and then that line is the way back: clicking it switches it on without touching the rule. |
| **Updates in the menu** | The state line is the outer condition, the buttons the inner one: „wird geladen" (downloading), „wird installiert" (installing), and a background attempt that failed each get a visible state, even when there's nothing to install. |
| **Last drag** | A grey sentence saying why the last observed drag ended the way it did („keine Zonen — ⌘ war nicht gedrückt" — no zones, ⌘ wasn't held; „kein Fenster unter dem Zeiger erkannt" — no window detected under the pointer). Diagnostic, see below. |
| **Launch at login** | Via `SMAppService.mainApp`. Under „Mehr" (More). |
| **Permission** | A dedicated window that explains the specific state and offers three ways to fix it. See below. |
| **Recent placements** | The most recent decisions as a list, plus the full log stream. Under „Mehr" (More). |
| **Pin** | „Aktuelles Fenster festhalten" (pin the current window) writes a rule and binding for the frontmost window. See [docs/regel-editor.md](regel-editor.md). |
| **Edit zones and rules** | A dedicated window for rules, roles & profiles, and zones. See [docs/regel-editor.md](regel-editor.md). |
| **Updates** | „Nach Updates suchen …" (check for updates) and „Automatisch nach Updates suchen" (check for updates automatically, on by default) live under „Mehr" (More). If something is ready, that line plus „Installieren"/„Später" (install/later) moves to the **top** — it demands a decision. Before swapping the bundle, the app stops window observation, pending placements and the drag tracker. The process and prerequisites are in the [README](../README.md#updates-and-publishing); **a real run has not been measured** while there is no release yet. |

## How the menu is built

Top to bottom, in every state:

1. **`OpenZonr <version>`** — not clickable, always first.
2. **One state line** plus at most one button: „Zugriff fehlt — ohne ihn
   kann OpenZonr keine Fenster bewegen" (access missing — without it OpenZonr
   can't move windows) / „Zugriff freigeben …" (grant access…), „Kein Setup
   passt zu den angeschlossenen Bildschirmen" (no setup matches the connected
   screens) / „Was ist zu tun? …" (what's to be done?…), „Bereit — Setup
   „Schreibtisch"" (ready — setup "Desk"), „Pausiert — es wird nichts
   automatisch platziert" (paused — nothing is being placed automatically).
3. **Whatever demands a decision** — an update that's ready, the warning
   about a second window manager.
4. **The two toggles**: „Fenster automatisch platzieren" (place windows
   automatically) and „Zonen beim Ziehen" (zones while dragging).
5. **The last drag**, as a grey sentence.
6. **Two actions**: „Aktuelles Fenster festhalten" (pin the current window),
   „Zonen und Regeln bearbeiten …" (edit zones and rules…).
7. **„Mehr" (More)** — Setup, Letzte Platzierungen (recent placements),
   Konfiguration neu laden (reload configuration), Status und Berechtigung
   (status and permission), Bei Anmeldung starten (start at login), the
   update settings.
8. **„OpenZonr beenden"** (quit OpenZonr).

The ordering is the answer to "I can't tell what's going on here": previously
the menu followed the program's own internal order and showed state names
with counters („Kein Profil passt — 2 Profile in der Konfiguration" — no
profile matches, 2 profiles in the configuration), which describes, but
doesn't say, what's going on. The wording now lives in
`MenuPresentation.swift` as pure functions — you can't open up a
`MenuBarExtra` and read it off, but you can read a function.

### Why the "Last drag" line

It exists for diagnosis — specifically for a bug whose cause is still open:
on the maintainer's machine, the zones don't appear when ⌘ is pressed. No
possible reason is visible from outside — no window under the press point, no
movement evidence ([#37](https://github.com/trsdn/OpenZonr/issues/37)), the
key not seen, no drag detected at all. All four look identical: nothing
happens.

`EventTapDragTracker` got a second return channel for this (`onOutcome`),
which reports **exactly the presses** that never make it to a `.began` —
at most one sentence per press, and none for an ordinary click. The
guarantees from [#26](https://github.com/trsdn/OpenZonr/issues/26) remain
untouched: the tap callback still contains no AX call, the channel only
forwards what the state machine has already decided.

## Decisions

### A SwiftPM executable, not an Xcode target

The issue left the choice open. It became an `.executableTarget` with
`MenuBarExtra`, for four reasons:

- `MenuBarExtra`, `@Observable` and `SMAppService` need nothing that a
  SwiftPM executable can't do.
- `Scripts/bundle.sh` already produces the signed bundle — Xcode wouldn't
  take over that step, it would replace it, and with one that can't be read
  in a diff.
- `swift build` and `swift test` remain the whole truth. Two build systems
  would be two truths, one of which drifts stale unnoticed.
- No `.pbxproj` merge conflicts.

The earlier announcement in the README that the app shell would arrive as an
Xcode target is thereby revised. This decision would only need revisiting
once entitlements are needed that require a provisioning profile — the app
needs none of those today.

### One binary for both the app and the command line

The bundle contains exactly one program. Without arguments it starts as the
menu bar app; with a recognized subcommand, as a command-line tool:

```bash
~/Applications/OpenZonr.app/Contents/MacOS/OpenZonrApp windows --bundle com.apple.Safari
```

That's not a gimmick, it follows from how macOS grants permission: **the
grant applies to a program at its path.** Two binaries in the same bundle
would be two grants — and the cross-check would measure something different
from what actually does the placing. This way, it measures exactly the
program that is also the app.

The distinction happens in `OpenZonrMenuBarApp.init()`, before any scene
exists, against a **fixed list** of subcommands. Not against "anything that
isn't a flag": LaunchServices passes its own arguments, and mistaking one of
those for a subcommand would mean the menu bar icon never appears — a
failure with no error message. The list is therefore tested.

`swift run openzonr` remains available via its own, trivial target; day to
day it's the tool for the development machine, not the shipped one.

### The watcher was extracted, not rewritten

The observation and placement logic now lives in `WatchEngine`
(`Sources/OpenZonrMac/Watch/`), shared between the CLI and the app. Three
properties of this logic are measured on real hardware and were carried over
verbatim; each one used to stand for a bug that produced an *empty log*
instead of an error message ([`tracer-bullet.md`](tracer-bullet.md)):

1. **The `NSRunningApplication` is held strongly** for as long as the
   observer's retry loop runs. Otherwise it gets deallocated before the
   first attempt, after 150 ms.
2. **Already-open windows are caught up on** after the observer attaches.
   Attaching takes 124 ms (TextEdit) to 2.2 s (Outlook), and the API only
   reports windows created *after* that.
3. **The frame is read patiently** — six attempts, one second apart. Outlook
   doesn't respond for roughly seven seconds at launch, and each read
   blocks for three.

A fourth, subtler point is also preserved: the counter of windows seen runs
*behind* the structural check, because Outlook opens a dummy window with
role `AXUnknown` before the real one.

### A manually chosen profile only applies to this session

`PinnedProfileResolver` puts a manual choice ahead of the automatic
detection. It's not persisted — it's a correction for the desk the user
happens to be sitting at right now, not a new rule. A manual choice that
survived a restart into a different setup would silently place windows on
the wrong screen; that's exactly what the exact match is meant to prevent.

If the chosen profile is missing from the configuration, detection takes
over again. That's tested too, since the configuration can change while the
app is running.

### The pause takes effect before the window counter

`isPaused` is checked the moment a window is reported — not only at the
point where the frame would be written. The difference isn't cosmetic.

It's the per-process counter that makes `onlyFirstWindowAfterLaunch` work at
all. If a window that shows up during a pause were counted, it would use up
the "first window after launch" slot — and after resuming, the rule would
silently skip exactly the window it was written for. Another failure with no
error message, the very kind this project has already paid for three times.

Paused therefore means: observe and report, not half-decide. The „pausiert"
(paused) line still shows up in the list, just without a rule or target —
those are deliberately not determined.

### Quit apps are forgotten

The watcher attaches one observer per watched app and remembers how many
windows it has shown since it launched. Until now, both were only cleaned up
when the watcher itself quit. The memory growth would have been the lesser
evil.

The serious problem is PID reuse. If a watched app launches under the number
of one that quit long ago, `attachObserver` finds an existing entry there
and bails out immediately. The stored observer belongs to a dead process and
never fires again; catching up on already-open windows sits below that
point in the code and is skipped as a result. Yet shortly before, the
watcher had noted that this app still owes its first window — and never
finds out otherwise. No log entry, no error, just silence. It hits exactly
`onlyFirstWindowAfterLaunch`.

The watcher therefore also listens for programs quitting, and checks
against the actually running processes rather than trusting the number in
the notification: `NSRunningApplication` returns −1 there once the process
is truly gone. The check is also self-healing — a missed notification gets
cleaned up on the next one. It also runs once more, just in case, before
attaching a new observer.

This is measurable without an Accessibility grant, and it was measured: a
throwaway program run against `OpenZonrMac`, with the real configuration,
counted `observedApplicationCount` before launching TextEdit, during, and
after. With the fix: 1 → 2 → 1; before the fix: 1 → 2 → **2**.

### All rules are watched, not just the active profile's

Whether an app gets watched at all is decided by the set of all enabled
rules in the configuration — not just the currently active profile's. That
looks like sloppiness, and isn't: rules are hardware-independent, profiles
merely translate them onto the desk at hand. Narrowing this to the active
profile would leave an app unwatched after a profile switch, right when it
becomes interesting again. There's a comment about this in the code, so
nobody later "cleans it up".

### Not every decision becomes a line

Only decisions that reached a rule show up in the menu. Every window of
every watched app passes through the filter; if the hundreds that were
never candidates were listed too, the handful of real matches would get
lost. The full stream is still available in the log window.

## The path to permission

The issue explicitly calls for care here rather than an error message, and
the reason is measured: **launched via LaunchServices — i.e. by
double-click or as a login item — the app is solely responsible for its own
permission.** Launched from a shell, the process inherits the terminal's
trust, and `AXIsProcessTrusted()` then misleadingly reports `true` while
window access inherits nothing. The app therefore checks
`Accessibility.probeWindowAccess()`, not `AXIsProcessTrusted()`.

Specifically:

- On the first launch without permission, the status window opens **once**
  on its own. A menu bar icon alone doesn't explain to anyone what to do.
- The window distinguishes the cases. „Nicht freigegeben" (not granted) and
  „freigegeben, aber nur Stellvertreter" (granted, but only proxies) have
  different causes and different fixes.
- It shows its own signature. Without a Developer ID, the grant is gone
  again after the next rebuild — that needs saying before anyone goes
  looking.
- It shows its own path and opens it in Finder, because it's exactly this
  bundle that belongs in the Accessibility list.
- It links directly into the right section of System Settings.

### `openzonr selftest`

```bash
open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
```

Reports the signature, the launch path and the *actual* window access.
`--out` exists because LaunchServices discards standard output — and the
LaunchServices-launched case is the one that matters. The same call from a
shell measures something different, and the report says so too:

```
Start:       aus einer Shell (Elternprozess PID 31134) — erbt fremdes Vertrauen
```

## Measurement status

What is confirmed as of 28.08.2026 on the target machine (macOS 26.6.2,
Mac16,11):

| Claim | Status |
|---|---|
| `swift build` and `swift test` are green | **measured** — 156 tests in 17 suites, headless |
| The bundle is signed and carries the expected designated requirement | **measured** — `identifier "com.trsdn.openzonr" and … subject.OU = G69Z5BNY97` |
| The app launches via LaunchServices and runs without a Dock icon | **measured** — process stable, `lsappinfo` reports `ApplicationType = UIElement` |
| The status window opens on its own when launching without permission | **measured** — window „OpenZonr — Status und Berechtigung" (OpenZonr — status and permission), 505×462 pt |
| The command line works from the same binary | **measured** — `selftest` and `windows` deliver their reports |
| The difference between a shell launch and a LaunchServices launch | **measured** — see below |
| Quit apps release their observer again | **measured** — `observedApplicationCount` 1 → 2 → 1; before the fix, 1 → 2 → 2 |
| Launch-at-login as a login item survives a re-login | **not measured** — `SMAppService.register()` reports success, but an actual log-out/log-in cycle was not performed |
| **Whether TextEdit lands in its zone at launch while the app is running** | **measured on 29.08.2026** — `3840,31 1280x1343` with the app running, `1920,32 1280x1343` without it. Addendum below |

The launch-path difference, verbatim from two runs of the same binary:

```
# open -n -a … --args selftest
  Start:                  über LaunchServices (Elternprozess launchd)
  AXIsProcessTrusted():   false
  probeWindowAccess():    notTrusted — keine Freigabe für dieses Bundle

# …/Contents/MacOS/OpenZonrApp selftest
  Start:                  aus einer Shell — erbt fremdes Vertrauen
  AXIsProcessTrusted():   true
  probeWindowAccess():    degraded — Vertrauen gemeldet, aber nur Stellvertreter
```

This independently confirms the addendum in
[`tracer-bullet.md`](tracer-bullet.md) and makes it reproducible in a single
command.

### Why placement went unverified for so long

> **Done on 29.08.2026.** The user granted the permission by hand; placement
> while the app is running has been measured since, with a cross-check and
> against the target app's remembered position. The numbers are in
> [`tracer-bullet.md`](tracer-bullet.md) under „Verifiziert: die Platzierung
> bei laufender App" (verified: placement while the app is running). The
> section below stays, because the reasoning for why this wasn't a code
> problem, and the setup steps, still hold unchanged.

The freshly built bundle at `~/Applications/OpenZonr.app` was **not
granted** in Accessibility. Without that grant the process sees no windows,
and without windows no placement can be measured.

Granting it could not be automated, for a reason that was itself checked:
macOS specifically shields these surfaces against automation. Both the
system dialog „Zugriff auf Bedienungshilfen" (Accessibility access) and
System Settings return **no accessibility tree and a black screenshot** on
the Accessibility pane. That's the intended hardening — a tool that could
grant itself its own window permission would defeat the point of the lock.

So what's missing is a manual step, not code:

1. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen
   (System Settings → Privacy & Security → Accessibility)
2. Add `~/Applications/OpenZonr.app` and enable it (an existing entry from
   an unsigned run: remove it and add it again — just re-checking the box
   is not enough)
3. A cross-check that needs no further assumptions:

```bash
open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
cat /tmp/openzonr.txt      # must report "granted"
```

After that, the actual measurement is restarting TextEdit while the app is
running. **Quit Magnet first** (`com.crowdcafe.windowmagnet`) — it operates
on the same API and would skew the result.

The placement logic itself is unchanged from the version that was measured:
`WatchEngine` was extracted from `WatchCommand`, not rewritten, and the CLI
today calls the very same code that produced the measurement in
[`tracer-bullet.md`](tracer-bullet.md). That's an argument, not a
measurement — and it's deliberately not presented as one here.

**Addendum:** the argument held up, but it would have been worthless if it
had been wrong — and the measurement showed why it shouldn't have been left
at that. It brought to light something the logic alone would never have
implied: Outlook resists the first write and needs a second attempt. An
argument based on unchanged code would never have found this case, because
it isn't a property of the code but of the target app.
