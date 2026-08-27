# OpenZonr

**Status: früher Konzeptstand (early concept).** Dieses Repository enthält das
Konzept, das Datenmodell, den Konfigurationsspeicher und die rechnende Hälfte der
Platzierung — aber noch keine lauffähige App: die Anbindung an die
Accessibility-API und die Oberfläche fehlen.

OpenZonr ist ein Fenstermanager für macOS mit Dropzones. Der Unterschied zu allem,
was es sonst gibt, steckt in einem einzigen Satz:

> **Apps öffnen sich von selbst in der Zone, die für sie vorgesehen ist.**

## Das Problem

Bestehende Tools lösen das Verschieben, nicht das Öffnen:

> „Ich will, dass Outlook immer in Zone 2 aufgeht. Heute geht es irgendwo auf,
> außer ich ziehe es selbst in die Dropzone."

Genau dieses Ziehen ist der wunde Punkt. Jede App, jeden Tag, nach jedem Neustart,
nach jedem Monitorwechsel. Zonen zu definieren ist gelöst — Fenster automatisch
dort landen zu lassen nicht.

## Der Ansatz

1. **Fenster erkennen** — `NSWorkspace.didLaunchApplication` plus ein `AXObserver`
   je App auf `kAXWindowCreatedNotification`.
2. **Regel finden** — Match-Kriterien wie Bundle-ID, Titel-Regex, Subrole,
   Fenstergröße.
3. **Rolle auflösen** — Regeln zeigen auf eine *Rolle* (z. B. „Kommunikation"),
   nicht auf eine Zone. Das aktive Profil übersetzt die Rolle in Display + Zone.
4. **Platzieren** — `kAXPositionAttribute` / `kAXSizeAttribute`, mit Retry-Loop
   gegen Apps, die sich nach dem Öffnen selbst nochmal resizen.

Alles Weitere steht in **[docs/konzept.md](docs/konzept.md)**.

## Abgrenzung

| Tool | Was es tut | Was fehlt |
|---|---|---|
| **Rectangle / Rectangle Pro** | Fenster per Shortcut oder Drag in Hälften, Drittel, benutzerdefinierte Zonen legen. Rectangle Pro kann App-Regeln beim Start anwenden. | Keine Rollen-Indirektion: Regeln hängen an konkreten Bildschirmbereichen und müssen pro Setup gepflegt werden. Keine EDID-stabile Monitoridentität. |
| **yabai** | Vollwertiger Tiling-WM mit Scripting-Sprache; sehr mächtig. | Verlangt teilweise das Deaktivieren von SIP. Automatisches Tiling statt fester, selbst gezeichneter Zonen. Regeln sind Skriptcode, keine teilbare Konfiguration. |
| **Amethyst** | Automatisches Tiling nach Layout-Algorithmen, App-Regeln vor allem als Float-Ausnahmen. | Man wählt ein Layout, keine frei platzierten Zonen. Kein „diese App gehört hierhin, unabhängig davon, was sonst offen ist". |
| **FancyZones (Windows)** | Das direkte konzeptionelle Vorbild inklusive App-Zuordnung zu Zonen. | Gibt es für macOS nicht — und die Layoutzuordnung hängt an Auflösung und Monitorreihenfolge statt an einer stabilen Monitoridentität. |
| **Moom, Magnet, Swish** | Komfortables manuelles Anordnen. | Ausdrücklich manuell. |

OpenZonr ist bewusst **kein** Tiling-Window-Manager. Es ordnet nicht automatisch
alles an, sondern platziert die wenigen Apps, für die man eine klare Vorstellung
hat, zuverlässig dort, wo sie hingehören — und lässt den Rest in Ruhe.

Zwei Dinge sind der Kern:

- **Rollen statt Zonen.** App-Regeln werden einmal geschrieben, nicht pro Setup
  dupliziert. Jedes Profil mappt Rollen auf seine eigenen Zonen.
- **Monitoridentität über EDID.** Ein Profil wird über das Set der tatsächlich
  angeschlossenen Monitore erkannt, nicht über Position, Index oder Auflösung.
  Umstecken ändert nichts.

## Projektstruktur

```
Package.swift                 SwiftPM-Manifest (macOS 14+)
Sources/OpenZonrCore/
  Geometry/                   RelativeRect, Zone, Layout
  Display/                    DisplayIdentity, SetupFingerprint
  Roles/                      ZoneRole, RoleBinding
  Rules/                      WindowMatch, PlacementAction, PlacementRule
  Profiles/                   Profile
  Configuration/              Configuration, Speicher, atomares Schreiben
    Migration/                Schrittkette zwischen Schemaversionen
  Validation/                 Validierung mit Dokumentpfaden
    Checks/                   Die einzelnen Prüfungen
  Placement/                  Filter, Regel-Engine, Profil- und Zonenauflösung
Tests/OpenZonrCoreTests/      Unit-Tests; Support/ enthält Fixtures
Examples/                     Beispielkonfiguration (Büro / Home / Unterwegs)
docs/                         Konzept, Konfigurationsreferenz, offene Fragen
```

Der Stand umfasst das Datenmodell, den Konfigurationsspeicher (laden,
validieren, atomar schreiben, migrieren) und die rein rechnende Hälfte der
Platzierung. Alles darin ist ohne laufenden Fensterserver testbar; die Anbindung
an die Accessibility-API und die Oberfläche fehlen noch.

**Warum Swift Package Manager und (noch) kein Xcode-Projekt?** Das Manifest ist
Text, also diff- und reviewbar, und es gibt keine `.pbxproj`-Merge-Konflikte.
Vor allem lässt sich der aktuelle Stand headless mit `swift build` und
`swift test` prüfen. Die spätere App-Hülle — Menüleisten-App, Entitlements und
Code-Signing, damit der Accessibility-Grant Updates übersteht — kommt als
separates Xcode-App-Target hinzu, das `OpenZonrCore` als lokales Package einbindet.

## Bauen

```bash
swift build
swift test
```

Mindestanforderung: macOS 14, Swift 6. Die verwendeten APIs (Accessibility,
`CGDisplay*`, `NSWorkspace`) sind deutlich älter; macOS 14 ist für die spätere
UI-Schicht (Observation, `MenuBarExtra`) gesetzt.

## Weiterlesen

- [docs/konzept.md](docs/konzept.md) — Architektur, Regelmodell, Monitor-Handling
- [docs/konfiguration.md](docs/konfiguration.md) — Feldreferenz und kommentierte
  Erklärung der Beispielkonfiguration
- [docs/offene-fragen.md](docs/offene-fragen.md) — was noch nicht entschieden ist

## Lizenz

MIT — siehe [LICENSE](LICENSE).
