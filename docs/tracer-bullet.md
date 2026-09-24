# Tracer Bullet — the probe

The smallest complete path from app launch to a placed window, as the
command-line tool `openzonr`. No UI, no rule editor, no menu bar app — just
the probe and the diagnostic tools needed to use it.

The purpose is not convenience but proof: **Can a newly opened window be
placed reliably into a defined zone, even when the app resizes itself again
after opening?**

The answer is measured, and it is yes. The numbers are under
[Verified: the placement](#verified-the-placement); the road there was long
blocked by a permission problem, whose resolution is described in the same
section.

---

## What the probe covers

The chain that `openzonr watch` runs through:

1. Load, migrate, and validate the configuration
   (`ConfigurationStore`, default path
   `~/Library/Application Support/OpenZonr/config.json`, overridable via
   `--config` or `OPENZONR_CONFIG`)
2. Read connected displays and condense them into the `SetupFingerprint`,
   **excluding** the software displays listed under `ignoredDisplays`
3. Determine the active profile. If none matches, `watch` aborts with a
   detailed message instead of silently picking the next-best one
4. Observe `NSWorkspace.didLaunchApplicationNotification` and attach an
   `AXObserver` on `kAXWindowCreatedNotification` for every relevant app —
   including apps that are already running at startup
5. Pre-filter the new window: window level, subrole, minimum size,
   `onlyFirstWindowAfterLaunch`
6. Evaluate rules by priority; the first match wins
7. Resolve the role to a display and zone via the active profile, honoring
   the fallback
8. Convert the `RelativeRect` against the target display's `visibleFrame` in
   AppKit coordinates, then mirror it into AX coordinates
9. Set it via `kAXPositionAttribute` and `kAXSizeAttribute`, read back the
   frame actually achieved, compare it against the tolerance from
   `RetryPolicy`, and retry if needed
10. Log every attempt: target frame, actual frame, deviation, attempt
    number, duration

Plus the two diagnostic commands `openzonr displays` and `openzonr windows`,
without which steps 1 through 3 would be pure guesswork.

## What is deliberately still missing

| Missing | Why |
|---|---|
| `mode: "suggest"` | Needs an overlay that displays the suggestion. `watch` logs the rule and the target frame in detail but places nothing. |
| Rule editor, zone editor | Not part of the probe. The menu bar app exists by now — [`menueleisten-app.md`](menueleisten-app.md). |
| Reacting to display changes at runtime | Partially solved: `WatchEngine` re-determines the profile on `NSApplication.didChangeScreenParametersNotification`. Not measured. |
| Continuous monitoring of placed windows | Deliberately not: after a successful placement, the window belongs to the user. |
| Notarization | Not needed for one's own machine. Signing, on the other hand, very much is — see "The blocker and its resolution". |

---

## Verification status

### Verified on real hardware

Measured on the user's desk: four displays, two of them physical (Samsung
C49RG9x 5120×1440 as the primary monitor, Samsung U28E590 1920×1080 above it
to the right) and two virtual ("AAA", "Teleprompter Source").

```
· Konfiguration geladen: /tmp/ozconf/config.json
· 2 Displays, 1 Profile, 3 aktive Regeln
· Angeschlossene Displays: 4, davon 2 im Fingerprint
    C49RG9x — fallback vendor=19501 model=3996 5120×1440 port=1
    U28E590 — edid vendor=19501 model=3149 serial=810375238
    AAA — fallback vendor=21252 model=0 1920×1080 port=2  [ignoriert]
    Teleprompter Source — edid vendor=21581 model=1 serial=1  [ignoriert]
✓ Aktives Profil: Schreibtisch (desk)
    Beobachte com.apple.Terminal
    Beobachte com.microsoft.Outlook
· Beobachte 2 laufende Apps plus alle neu gestarteten.
· Warte auf neue Fenster. Beenden mit Strg-C.
· App gestartet: com.apple.TextEdit (pid 2608)
    Beobachte com.apple.TextEdit
! Neues Fenster von com.apple.TextEdit ohne lesbaren Frame.
```

This establishes:

- **Display detection and identity formation.** The primary monitor reports
  serial number 0 and runs through the fallback path; the secondary monitor
  via EDID.
- **The fingerprint fix holds.** Four connected displays, two in the
  fingerprint. OBS or the teleprompter appearing no longer shifts the
  profile.
- **Profile selection.** "Schreibtisch" ("Desk") was determined unambiguously
  via the reduced fingerprint.
- **The observation chain.** After `didLaunchApplicationNotification`, the
  `AXObserver` attached to the new app 37 ms later, and
  `kAXWindowCreatedNotification` was delivered a further 310 ms after that.

  This first measurement invited the conclusion that the window was "small
  but sufficient." That was too optimistic a generalization: 37 ms was the
  best case observed. Later measurements yielded 124 ms for TextEdit and
  2.2 s for Outlook — and it is in this gap that apps open their first
  window. See Error 2 further below.

### The blocker and its resolution: signing

For a long time it looked as though the last step was not measurable. The
finding was clear and reproducible:

```
AXIsProcessTrusted()                                        → true
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)     → .success
  Safari      n=1   role of the "window": AXApplication
  Outlook     n=1   role of the "window": AXApplication
  … 21 apps, not a single one delivers an element with role AXWindow
AXPosition / AXSize on these elements                       → -25205
```

`-25205` is `kAXErrorAttributeUnsupported`. Every app responded to
`AXWindows` with a stand-in that carried the role `AXApplication` and had
neither position nor size. A separately compiled probe program that used
nothing from this repository got exactly the same stubs — so the cause was
not in the code.

**The explanation was almost right, and the conclusion came too fast.** The
suspicion was that the permission was tied to the *responsible* process and
therefore unreachable. The decisive lever is the **code signature**: an
unsigned binary gets a different checksum on every rebuild, and TCC does not
recognize it again — the checkbox in System Settings stays checked but
refers to a different program. That the responsible process also plays a
role is shown by the addendum further below.

The resolution is a signed app bundle. The designated requirement of a
Developer ID signature binds to identifier and team, not to the checksum:

```
designated => identifier "com.trsdn.openzonr" and anchor apple generic
  and certificate 1[field.1.2.840.113635.100.6.2.6]
  and certificate leaf[field.1.2.840.113635.100.6.1.13]
  and certificate leaf[subject.OU] = G69Z5BNY97
```

With this, the grant survives a rebuild as a rule (see the addendum from
30.08.2026 further below: this is not guaranteed). `Scripts/bundle.sh`
builds, packages, and signs in one step. An ad-hoc certificate is not
enough; it has no such chain.

After signing, the same call returns 19 real `AXWindow` elements with a
readable frame. A new manual grant was not necessary.

**Addendum — a claim in this document was too broadly stated.** It used to
say that the grant survives "even moving the bundle to a different path,
which was cross-checked." A later, more careful cross-check disproves that:

```
fresh clone → Scripts/bundle.sh → identical designated requirement
  Launch from the shell      : "access degraded"
  Launch via LaunchServices  : "no access — not trusted"
```

The second finding is the meaningful one. Started from the shell, the
process inherits the terminal's trust, which is why `AXIsProcessTrusted()`
still reports `true` — but window access does not inherit it. Started via
LaunchServices, the app is responsible for itself, and that is where the
truth shows: this bundle is not granted access. **The grant belongs to the
program at its location, not to the identifier alone.** The original
assumption about the responsible process was thus not wrong, just
incomplete; both mechanisms are at work.

Practical consequence, implemented in `Scripts/bundle.sh`: the bundle now
lands under `~/Applications/OpenZonr.app` by default instead of in
`.build`. There, the one-time grant survives `swift package clean`, a
second clone, and every rebuild. In `.build` it would be lost at the first
cleanup.

**Addendum to the addendum, 28.08.2026:** This finding is by now
reproducible in a single command. `openzonr selftest` reports, alongside
signature and window access, the *launch path* as well — and thereby
answers the question that makes the difference. Two runs of the same binary
from `~/Applications/OpenZonr.app`, the same signature, the same second:

```
# open -n -a … --args selftest --out /tmp/openzonr.txt
  Start:                  über LaunchServices (Elternprozess launchd)
  AXIsProcessTrusted():   false
  probeWindowAccess():    notTrusted — keine Freigabe für dieses Bundle

# …/Contents/MacOS/OpenZonrApp selftest
  Start:                  aus einer Shell — erbt fremdes Vertrauen
  AXIsProcessTrusted():   true
  probeWindowAccess():    degraded — Vertrauen gemeldet, aber nur Stellvertreter
```

`--out` here is not a convenience but a necessity: LaunchServices discards
standard output, and without a file, precisely the decisive case would
remain unobservable.

**Addendum, 30.08.2026 (Issue #35): "survives every rebuild" was too
broadly stated.**
After a `Scripts/bundle.sh` run on `ec34da5` to the same path, the
self-test over LaunchServices (parent process `launchd`) reported
`degraded`, three times about 45 s apart. Path, identifier, team, and
designated requirement were character-for-character the same as before, and
across the two rebuilds before that (29.08 18:38 and 30.08 03:45) the grant
had held. So this is occasional behavior, not a consistent one. **Why** the
entry became invalid is not known: the TCC database is SIP-protected and
unreadable. Rebuild frequency or a time window as a cause are not measured
and are therefore not stated here as a guess. Remedy: remove the entry in
Accessibility and add it again; unchecking and rechecking the box is not
enough. The help texts (self-test, `Scripts/bundle.sh`, README) have since
said „übersteht einen Neubau in der Regel“ ("survives a rebuild as a
rule").

Notable, and important for later troubleshooting: **notifications work even
in the degraded state.** `AXObserverAddNotification` succeeds and
`kAXWindowCreatedNotification` is delivered — only the attributes of the
reported element are empty. A tool that relies on `AXIsProcessTrusted()`
would, in exactly this situation, silently do nothing at all. `openzonr`
therefore additionally checks whether any app returns an element with the
role `AXWindow` **and** a readable frame, and otherwise refuses `watch` with
a reason.

### Verified: the placement

Measured on 28.08.2026 on the four-display setup described above, with
Magnet quit.

| Case | Zone | Target | Actual | Deviation | Attempts | Duration |
|---|---|---|---|---|---|---|
| TextEdit, cold start | `c49rg9x/right-quarter` | `3840,31 1280x1344` | `3840,31 1280x1343` | 1.0 pt | **1** | 122 ms |
| Outlook, running | `c49rg9x/center-half` | `1280,31 2560x1344` | `1280,31 2560x1344` | 0.0 pt | **1** | 236 ms |

Both times independently cross-checked with `openzonr windows --bundle …`.

**This answers the question "do three attempts over 500 ms suffice?": yes,
by a wide margin.** Both measured apps comply on the first write. The one
deviation of 1.0 pt for TextEdit lies well within the 4 pt tolerance and
comes from height rounding, not from the app pushing back.

The retry loop remains necessary nonetheless — it is aimed at apps that
push back, and that behavior is covered with a fake window
(`Tests/OpenZonrCoreTests/RetryingWindowPlacerTests.swift`).

> **Added on 29.08.2026 — the last sentence of this section was wrong.**
> It read: "What the measurement shows is that it is not invoked in the
> normal case." That held for two cases in which the window barely had to
> travel. As soon as a real window has to be dragged across the screen, the
> loop is very much invoked — see
> ["Verified: the placement with a running app"](#verified-the-placement-with-a-running-app).
> The reason it did not show up back then is the same one that makes the
> Outlook row above questionable: Outlook was already at the target
> position.

### Verified: the placement with a running app

Measured on 29.08.2026, `main` at `28d84e7`. The difference from the table
above is not the logic but the **launch path**: not `openzonr watch` from a
shell, but the signed bundle under `~/Applications/OpenZonr.app`, started
via LaunchServices, with the Accessibility grant given by hand. That was the
gap that [`menueleisten-app.md`](menueleisten-app.md) had left open.

Preconditions, each checked individually rather than assumed:

```
selftest via LaunchServices (parent process launchd)
  probeWindowAccess():  granted
Cross-check on a foreign app: Safari → AXWindow / AXStandardWindow, frame 1820,74 1202x1108
Magnet:                   not running (pgrep, not merely assumed)
Displays:                 4 active, both fingerprint displays present
Profile:                  „Schreibtisch" (measured) applies
```

| Case | Zone | Actual **with** OpenZonr | Actual **without** OpenZonr | Probative value |
|---|---|---|---|---|
| TextEdit, cold start | `c49rg9x/right-quarter` | `3840,31 1280x1343` | `1920,32 1280x1343` | **conclusive** — 1920 pt offset, same size |
| Outlook, cold start | `c49rg9x/center-half` | `1280,31 2560x1344` | `1280,31 2560x1344` | **worthless** — see below |
| Outlook against its own memory | `c49rg9x/left-quarter` | `0,31 1280x1344` | (remembers `1280,…`) | **conclusive** — see below |

**The middle row is deliberately in this table.** Outlook restores its own
window position by itself. So it lands in `center-half` even when OpenZonr
is not running at all — the measurement succeeds without the thing it is
supposed to prove, and thereby proves nothing. It was the first attempt and
would have passed as a success.

The case only becomes decidable once the two answers **diverge**: a copy of
the configuration (`watch --config`, nothing changed on the original) sends
the role `mail` to `left-quarter`. Outlook remembers `x=1280`, the rule
demands `x=0`. From the log — timestamps removed, the window title contains
an email address and is therefore omitted, otherwise unchanged:

```
▸ Neues Fenster: com.microsoft.Outlook  1280,31 2560x1344  subrole=AXUnknown  Ebene 0
  ignoriert — Subrole AXUnknown ist nicht freigegeben.
▸ Neues Fenster: com.microsoft.Outlook  1280,31 2560x1344  subrole=AXStandardWindow  Ebene 0
✓ Regel "outlook" → Rolle "mail" → c49rg9x/left-quarter
  Soll-Frame 0,65 1280x1344 (AppKit) → 0,31 1280x1344 (AX)
  Versuch 1: Soll 0,31 1280x1344 | Ist -0,31 1288x1344 | Abweichung 8.0 pt (Toleranz 4 pt) | Abweichung zu groß | 121 ms
  Versuch 2: Soll 0,31 1280x1344 | Ist -0,31 1280x1344 | Abweichung 0.0 pt (Toleranz 4 pt) | innerhalb der Toleranz | 218 ms
✓ Platziert nach 2 Versuchen.
```

The `-0` in the actual column is not a measurement but negative zero from
formatting; the deviation next to it is 0.0 pt. `openzonr windows`
subsequently outputs the same frame as `-0,31 1280x1344`. Not a placement
error, but a spot where a reader stumbles.

Three things these eight lines establish that the previous measurement
could not:

1. **The app wins against the target app's position memory.** That is
   exactly what prompted the project.
2. **The retry loop is load-bearing, not decoration.** Outlook did *not*
   comply on the first write: 1288 instead of 1280 pt wide, 8 pt over the
   4 pt tolerance. Without the second attempt, the window would have stayed
   wrongly placed — and the deviation would have been small enough that no
   one would have recognized it as an error. The claim further above, that
   the loop is "not invoked in the normal case," is thereby refuted.
3. **The subrole filter works.** Outlook reports two windows with an
   identical frame; one carries `AXUnknown`. Without the filter, the
   placement would have gone to a phantom.

**A methodological error that nearly produced a second worthless
measurement:** `pgrep -x Outlook` does **not** find Outlook — the process is
named `Microsoft Outlook`. A test that then assumes "not running" and
subsequently measures a frame is measuring a window that has been sitting
there for hours. It only surfaced via `ps -p <pid> -o lstart`. Anyone
reporting a placement as fresh must establish the **process's start time**,
not merely assume its absence. For the same reason, `ps aux | grep -i
openzonr` is not suitable for checking whether the app is running: it
matches every process that carries the path in its invocation. The correct
command is `pgrep -lf 'OpenZonr.app/Contents/MacOS'`.

Left unmeasured: autostart via `SMAppService` after a real re-login, and
everything that needs a hand on the mouse — overlay, an actual drag, Magnet
in conflict, the offer panel (see [`dropzones.md`](dropzones.md)).

### What the measurement brought to light in the way of bugs

Three bugs, each invisible on its own, that together resulted in not a
single window being placed. None of them would have surfaced without real
hardware; all three produced an empty log instead of an error message.

**1. The application was held weakly.** The retry loop that attaches the
`AXObserver` held `NSRunningApplication` weakly, and no one else held it.
Before the first retry after 150 ms, the instance had been released, the
`guard` failed, and the loop returned without reporting success *or*
failure. The log read „App gestartet" ("app started") and then nothing —
indistinguishable from the app never having opened a window.

**2. The window was faster than the observer.** Attaching takes time:
124 ms for TextEdit, 2.2 s for Outlook. Apps open their first window
exactly in this gap. Since the API only reports windows created *after*
registration, this window was lost for good — precisely the one the rule
was written for. Already-existing windows are now caught up once.

**3. The frame was not yet readable.** A caught-up window can belong to an
app that is still launching. Outlook returned nothing at all for seven
seconds, with each individual read blocking for three seconds. Giving up at
the first empty frame discarded exactly the window being sought. The frame
is now re-read up to six times.

A fourth bug concerned rule selection rather than mechanics: Outlook opens
an `AXUnknown` window of the same size **before** its real one. The counter
for "first window after launch" ran ahead of the structural filter and
counted this dummy window too, which made the mailbox the *second* window
and the rule no longer matched. The counter now runs after the filter.

### What the measurement taught about Outlook

Outlook restarts itself automatically after a `quit`. As a result, it
counts as an already-running app the next time `watch` starts, and never as
freshly launched. For the use case "Outlook should *always* sit in its
zone," `onlyFirstWindowAfterLaunch: false` is therefore the right setting —
the default of `true` is meant for apps that open further windows during
work.

---

## Known source of interference: competing window managers

Running in parallel on the measurement machine:

| Bundle ID | Tool |
|---|---|
| `com.crowdcafe.windowmagnet` | Magnet |
| `com.openswitchr.app` | the user's own overlay, layer 3 |

**Magnet places windows through the same Accessibility API.** It can
override a placement by OpenZonr, and OpenZonr can override one by Magnet.
For reading the retry log, this means: a deviation between the target and
actual frame is not automatically the app's own resize — it could just as
well come from Magnet. Anyone who does not know this measures Magnet and
mistakes the result for Outlook.

**For a clean measurement, quit Magnet temporarily.** If that is not an
option, at least note in the log that it was running.

**With the dropzones (#10), Magnet turned from a measurement problem into a
design problem**, because both programs display an overlay while dragging.
How OpenZonr behaves in that case — detect and warn once, not fight for
dominance — is covered in [dropzones.md](dropzones.md).

---

## The coordinate trap, with real numbers

Two coordinate systems collide:

| | Origin | y increases |
|---|---|---|
| AppKit (`NSScreen.frame`, `visibleFrame`, `ZoneResolver`) | bottom-left of the primary display | upward |
| Accessibility (`kAXPositionAttribute`, `CGDisplayBounds`, `CGWindowListCopyWindowInfo`) | top-left of the primary display | downward |

Conversion: `y' = primaryTopY - (y + height)`, self-inverse.

On the measured desk:

| Display | AppKit `frame` | AX bounds (measured) |
|---|---|---|
| C49RG9x (primary) | `0, 0, 5120×1440` | `0, 0, 5120×1440` |
| U28E590 | `2833, 1440, 1920×1080` | `2833, -1080, 1920×1080` |
| AAA | `-1007, 1440, 1920×1080` | `-1007, -1080, 1920×1080` |
| Teleprompter Source | `913, 1440, 1920×1080` | `913, -1080, 1920×1080` |

This arrangement is the actual test case: the primary monitor is 1440 tall,
the ones above it 1080. With equally tall displays, a window still lands on
the right screen despite a wrong conversion, and the bug survives. Not
here — `ScreenArrangementTests` recomputes exactly these values.

Equally important: **the `visibleFrame` is read per display.** Only the
primary monitor reports a reduced one (1344 instead of 1440, i.e., 96
points for the menu bar and Dock); the other three report `visibleFrame ==
frame`, even though a menu bar is visible on each of them. A global
menu-bar deduction would be wrong on three of the four displays.

---

## Reproducing this

```bash
Scripts/bundle.sh                       # builds, packages, and signs
```

Register the bundle once in System Settings → Privacy & Security →
Accessibility. If there is an existing entry from an unsigned run: remove
it and add it again — merely re-checking the box is not enough.

```bash
APP=~/Applications/OpenZonr.app/Contents/MacOS/OpenZonrApp
"$APP" windows --bundle com.apple.Safari       # must show AXStandardWindow ≠ 0x0
"$APP" displays --config-fragment              # displays for the configuration
"$APP" watch --config <path>
```

Before measuring, quit competing window managers (see above). Then quit and
restart the target app; the attempt lines appear in the log.

---

## Further reading

- [README.md](../README.md) — building, permission, the three subcommands
- [docs/konfiguration.md](konfiguration.md) — field reference, including
  `ignoredDisplays` and the warning about title regex
- [docs/offene-fragen.md](offene-fragen.md) — what the probe answered and
  what it raised anew
