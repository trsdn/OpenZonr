# Konfigurationsreferenz

Die Konfiguration liegt als **JSON** vor: versionierbar, diffbar, teilbar und mit
jedem Texteditor bearbeitbar. JSON kennt keine Kommentare — deshalb steht die
Erklärung hier statt in der Datei.

Referenzdatei: [`Examples/openzonr.config.json`](../Examples/openzonr.config.json).
Sie wird durch die Tests in `Tests/OpenZonrCoreTests/` gegen das Datenmodell
geprüft und ist damit garantiert gültig.

> **Die Beispielkonfiguration ist illustrativ, keine Vorlage zum Kopieren.**
>
> Sie zeigt die Struktur, nicht ein reales Setup. Konkret:
>
> - **Die EDID-Nummern sind frei erfunden.** `vendorNumber`, `modelNumber` und
>   `serialNumber` für „Dell" und „LG" sind Platzhalter. Wer sie übernimmt,
>   bekommt ein Profil, das nie greift.
> - **Alle drei Profile stützen sich auf ein `builtin`-Display.** Auf einem
>   Schreibtisch mit geschlossenem Deckel oder an einem Desktop-Mac ist
>   `CGDisplayIsBuiltin` bei *keinem* Display wahr — der Alias läuft dort ins
>   Leere. Real gemessen auf dem Setup des Autors: vier Displays, kein einziges
>   integriertes.
>
> **Verbindliche Quelle für echte Identitäten ist `openzonr displays`.**
> `openzonr displays --config-fragment` gibt ein fertiges `displays`-Fragment
> aus, das direkt übernommen werden kann. Erst danach Layouts, Rollen, Profile
> und Regeln ergänzen.


---

## Aufbau

```jsonc
{
  "version":  1,     // Schemaversion, steuert Migrationen
  "displays": [],    // physische Bildschirme + ihre Layouts
  "ignoredDisplays": [], // Displays, die den Fingerprint nicht beeinflussen
  "roles":    [],    // semantische Platzierungsziele
  "profiles": [],    // Setups: welche Rolle liegt wo?
  "rules":    [],    // Match → Aktion
  "defaults": {}     // Vorgaben, die Regeln erben
}
```

Die Reihenfolge folgt der Indirektionskette:

```
Regel ──match──▶ Rolle ──Profil──▶ Display + Zone ──Layout──▶ Geometrie
```

---

## `displays`

Ein Eintrag je physischem Bildschirm.

| Feld | Typ | Bedeutung |
|---|---|---|
| `alias` | String | Kurzer Handle zum Referenzieren, z. B. `"dell-u2723"`. Frei wählbar, muss eindeutig sein. |
| `displayName` | String | Klartextname für die UI. |
| `identity` | Objekt | Stabile Hardware-Identität, siehe unten. |
| `layouts` | Array | Alle für dieses Display definierten Layouts. |
| `defaultLayoutID` | String | Layout, wenn ein Profil keines auswählt. |

### `identity`

Drei Varianten, unterschieden über `kind`:

```jsonc
// Integriertes Display, erkannt über CGDisplayIsBuiltin
{ "kind": "builtin" }

// Bevorzugter Fall: vollständige EDID-Daten
{
  "kind": "edid",
  "vendorNumber": 4268,        // CGDisplayVendorNumber
  "modelNumber": 42145,        // CGDisplayModelNumber
  "serialNumber": 1194485571   // CGDisplaySerialNumber
}

// Nur wenn der Monitor keine brauchbare Seriennummer meldet
{
  "kind": "fallback",
  "vendorNumber": 4268,
  "modelNumber": 42145,
  "pixelWidth": 3840,
  "pixelHeight": 2160,
  "portIndex": 0
}
```

Die `fallback`-Variante ist nicht global eindeutig: zwei baugleiche Monitore an
getauschten Ports werden verwechselt. Sie ist deshalb ausdrücklich als solche
markiert, damit die UI warnen kann.

> **`serialNumber == 0` ist der Normalfall, nicht der Randfall.**
>
> Auf dem gemessenen Setup meldet ausgerechnet der Hauptmonitor — ein Samsung
> C49RG9x — die Seriennummer 0. Der `fallback`-Pfad ist damit der *wichtigste*
> Pfad, nicht die Ausnahme. Er ist entsprechend getestet und wird von
> `openzonr displays --config-fragment` automatisch gewählt, wenn die
> Seriennummer 0 ist.
>
> Beachte dabei: der Fallback enthält bewusst **auch die `modelNumber`**. Auf
> demselben Setup teilen sich zwei Samsung-Monitore den `vendorNumber` 19501 und
> unterscheiden sich nur über das Modell. Eine Identität aus Vendor plus
> Auflösung allein würde hier kollidieren.

**Nicht als Identität verwendet:** Position im Arrangement, Index in
`NSScreen.screens`, Auflösung allein oder `CGDirectDisplayID`. Begründung in
[konzept.md, Abschnitt 6](konzept.md#6-monitor-identität).

## `ignoredDisplays`

Eine Liste von `identity`-Objekten im selben Format wie oben. Displays, die
darin auftauchen, werden **beim Bilden des Setup-Fingerprints übersprungen**.

Der Grund ist ein Problem, das erst an echter Hardware sichtbar wurde:
**virtuelle Displays kippen den Fingerprint.** Software wie OBS oder ein
Teleprompter-Werkzeug meldet dem System vollwertige Displays. Sie kommen und
gehen, während sich physisch nichts ändert — und nach dem ursprünglichen Konzept
ändert sich damit jedes Mal der Fingerprint und das Profil springt um.

Auf dem gemessenen Setup betrifft das zwei von vier Displays („AAA",
„Teleprompter Source"). Mit `ignoredDisplays` bleibt der Fingerprint über beide
physischen Monitore stabil, egal ob OBS gerade läuft.

```jsonc
"ignoredDisplays": [
  { "kind": "fallback", "vendorNumber": 21252, "modelNumber": 0,
    "pixelWidth": 1920, "pixelHeight": 1080, "portIndex": 2 },
  { "kind": "edid", "vendorNumber": 21581, "modelNumber": 1, "serialNumber": 1 }
]
```

**Bewusst eine explizite Liste und keine Heuristik.** `openzonr displays`
markiert Verdachtsfälle mit `virtuell?`, trägt sie aber nicht selbst aus dem
Fingerprint aus — die Erkennung ist unzuverlässig (siehe
[offene-fragen.md](offene-fragen.md)), und ein Werkzeug, das Displays nach
Bauchgefühl ignoriert, ist schlimmer als eines, das fragt.
`openzonr displays --config-fragment` schlägt die Einträge vor; die Entscheidung
trifft der Nutzer.


### `layouts` und `zones`

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

`frame` ist **prozentual**, `0.0` bis `1.0`, relativ zum *sichtbaren* Frame des
Displays — also ohne Menüleiste und Dock. Ursprung `(0, 0)` ist **oben links**.

Niemals Pixel: der Büromonitor ist kleiner als der Home-Ultrawide, Skalierung und
ein ein- oder ausgeblendetes Dock ändern die nutzbare Fläche.

Layouts gehören ans Display, nicht ans Profil — ein Ultrawide will drei Spalten,
ein 24-Zöller zwei, unabhängig davon, welches Setup gerade aktiv ist.

---

## `roles`

Semantische Platzierungsziele. Regeln zeigen auf Rollen, niemals direkt auf
Zonen.

```jsonc
{
  "id": "communication",
  "name": "Kommunikation",
  "summary": "Mail und Chat — immer sichtbar, nie im Weg."
}
```

`summary` ist optional und rein dokumentarisch.

Die Beispielkonfiguration definiert fünf Rollen: `communication`, `editor`,
`reference`, `terminal`, `compose`. Fünf bis sieben sind ein guter Richtwert —
mehr Rollen bedeuten mehr Bindungen, die je Profil gepflegt werden müssen.

---

## `profiles`

Ein Profil beantwortet genau eine Frage: *Bei dieser Bildschirmkonstellation —
wo liegt welche Rolle?*

```jsonc
{
  "id": "office",
  "name": "Büro",

  // Aktiviert, wenn genau diese Displays angeschlossen sind.
  // Reihenfolgeunabhängig; verglichen wird das Set.
  "fingerprint": { "displays": ["builtin", "dell-u2723"] },

  // Welches Layout jedes Display in diesem Profil verwendet.
  // Fehlt ein Display, gilt sein defaultLayoutID.
  "layouts": {
    "builtin": "builtin-full",
    "dell-u2723": "dell-two-columns"
  },

  // Das eigentliche Rollen-Mapping.
  "roleBindings": [
    { "role": "communication", "display": "dell-u2723", "zone": "right-half" },
    { "role": "editor",        "display": "dell-u2723", "zone": "left-half"  },
    { "role": "reference",     "display": "builtin",    "zone": "full"       }
  ],

  // Pflichtfeld: wohin, wenn eine Rolle hier nicht gemappt ist.
  "fallback": { "role": "communication", "display": "builtin", "zone": "full" }
}
```

`fallback` ist bewusst **Pflicht**. Eine nicht gemappte Rolle darf nie
„irgendwo" bedeuten; das Fenster landet an definierter Stelle und das Ereignis
wird protokolliert.

Der Fingerprint wird **exakt** verglichen: ein Setup mit einem zusätzlichen,
unbekannten Monitor ist nicht dasselbe Profil. Ein unbekannter Fingerprint führt
zur Rückfrage beim Nutzer, nicht zu einem geratenen Profil.

### Die drei Beispielprofile im Vergleich

| Rolle | Büro | Home | Unterwegs |
|---|---|---|---|
| `communication` | Dell, rechte Hälfte | LG 38", rechts außen (25 %) | Builtin, rechte Hälfte |
| `editor` | Dell, linke Hälfte | LG 38", Mitte (50 %) | Builtin, linke Hälfte |
| `compose` | Dell, linke Hälfte | LG 38", Mitte | Builtin, rechte Hälfte |
| `reference` | Builtin, Vollbild | LG 38", links außen (25 %) | Builtin, rechte Hälfte |
| `terminal` | Builtin, Vollbild | Builtin, Vollbild | Builtin, linke Hälfte |

Die Regeln darunter sind für alle drei Profile **identisch**. Genau das ist der
Zweck der Rollen-Indirektion.

Im Profil „Büro" teilen sich `reference` und `terminal` dieselbe Zone. Das ist
kein Fehler, sondern der Normalfall für `conflict.occupiedZone: "stack"`: beide
Fenster liegen in derselben Zone übereinander.

---

## `rules`

```jsonc
{
  "id": "outlook-main",
  "name": "Outlook: Hauptfenster",
  "enabled": true,
  "priority": 50,               // höher = wird früher geprüft

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

### `match` — alle Felder optional, UND-verknüpft

| Feld | Typ | Zweck |
|---|---|---|
| `bundleIdentifier` | String | Der Basisfall. |
| `titlePattern` | String (Regex, ICU) | Trennt Hauptfenster von Verfassen-Fenstern. **Sparsam einsetzen** — Titel sind lokalisiert und ändern sich zur Laufzeit, siehe die Warnung unten. |
| `roles` | [String] | `kAXRoleAttribute`, z. B. `"AXWindow"`. |
| `subroles` | [String] | `kAXSubroleAttribute`. `"AXStandardWindow"` filtert Dialoge und Popups. |
| `minimumSize` / `maximumSize` | `{width, height}` in Punkten | Filtert Popups und Paletten. |
| `aspectRatio` | `{minimum, maximum}` als `width / height` | Fängt ungewöhnliche Formate ab. |
| `onlyFirstWindowAfterLaunch` | Bool | Überschreibt die globale Voreinstellung. |

Ein leeres `match` passt auf **jedes** Fenster.

### Immer aktiv: der Ebenenfilter

Unabhängig von `match` verwirft OpenZonr jedes Fenster, das nicht auf der
Anwendungsebene liegt (`kCGWindowLayer == 0` bzw. das AX-Äquivalent). Das ist
**keine Option und nicht abschaltbar**, sondern das erste Kriterium überhaupt.

Der Grund ist eine Messung an der echten Fensterlandschaft:

```
Ebene 20            Dock
Ebene 21            Mitteilungszentrale   5120×1440  ← besteht jeden Größenfilter
Ebene 24            Menüleiste (4×, je Display)
Ebene 25            ~130 Kontrollzentrum-Items
Ebene 3             Overlay einer Fremd-App
Ebene 2147483630    StatusIndicator des Window Servers
Ebene 0             echte App-Fenster
```

Die Mitteilungszentrale ist **so groß wie der ganze Hauptmonitor**. Jede
Mindestgrößen-Prüfung lässt sie durch; nur die Ebene unterscheidet sie von einem
echten Fenster. Subrolle und Mindestgröße allein reichen also nicht.

### Warum `titlePattern` bei Outlook und Browsern unbrauchbar ist

Titel sind kein Identitätsmerkmal, sondern Zustandsanzeige. Zwei Messungen
desselben Outlook-Hauptfensters, gleiche Sitzung, zwei Minuten Abstand:

```
com.microsoft.Outlook   1708×1344 @ 1706,31
  t₀   "torstenmahr@microsoft.com" wird durchsucht
  t₁   yesterbox • torstenmahr@microsoft.com
```

Gleiches Fenster, komplett anderer Titel — der erste ist ein *Suchzustand* und
enthält obendrein verschachtelte Anführungszeichen. Bei Edge und Safari ist der
Titel schlicht der Seitentitel und ändert sich mit jedem Klick.

Dazu kommt: **die Systemsprache ist nicht garantiert Englisch.** Ein Muster wie
`(Message|Compose)` greift auf einem deutschen System nicht. Die
Beispielkonfiguration listet deshalb `(Nachricht|Message|Verfassen|Compose|Termin|Meeting)`
— was das Problem lindert, aber nicht löst.

**Der robustere Primärweg ist deshalb:**

1. `bundleIdentifier` als Basis
2. `onlyFirstWindowAfterLaunch: true` für das Hauptfenster
3. `minimumSize` gegen Popups und Paletten
4. `subroles: ["AXStandardWindow"]` gegen Dialoge

`titlePattern` erst dann, wenn diese vier nicht ausreichen — und dann in dem
Bewusstsein, dass die Regel bei einem Sprachwechsel oder einem UI-Update der App
still aufhört zu greifen. `openzonr windows --bundle <id>` zeigt, womit man es
tatsächlich zu tun hat.

Warum `onlyFirstWindowAfterLaunch` und `minimumSize` beide gebraucht werden,
zeigt derselbe Messlauf:

```
com.corecode.MacUpdater   4× deckungsgleich   420×206 @ 750,230   Titel ""
```

Vier identische Fenster derselben App, alle mit leerem Titel. Ohne
Mindestgröße wären alle vier Kandidaten; ohne
`onlyFirstWindowAfterLaunch` würden alle vier in dieselbe Zone geschoben.


### `action`

| Feld | Werte | Zweck |
|---|---|---|
| `role` | Rollen-ID | Pflicht. Das semantische Ziel. |
| `share` | `{axis, slots, slotIndex}` | Teilt die Zone in gleich große Slots. `axis`: `"horizontal"` oder `"vertical"`. `slotIndex` ist nullbasiert. |
| `focus` | `"activate"` / `"leaveAsIs"` | Ob das Fenster nach vorn geholt wird. |
| `mode` | `"place"` / `"suggest"` | `"suggest"` verschiebt nichts, sondern bietet die Platzierung an. |

### Auswertungsreihenfolge

Nach `priority` absteigend, bei Gleichstand in Dateireihenfolge. **Die erste
passende Regel gewinnt**, danach wird abgebrochen.

Daraus folgt: **spezifisch vor generisch**. In der Beispielkonfiguration:

| Priorität | Regel | Warum diese Reihenfolge |
|---|---|---|
| 100 | `outlook-compose` | Muss vor der allgemeinen Outlook-Regel greifen, sonst kommt sie nie zum Zug. |
| 50 | `outlook-main` | Der Normalfall. |
| 40 | `teams-main` | |
| 30 | `vscode` | |
| 20 | `safari` | |
| 10 | `terminal` | |
| −100 | `catch-all` | Auffangregel, standardmäßig `"enabled": false` und `"mode": "suggest"`. |

### Das Outlook-Beispiel im Detail

Das Verfassen-Fenster ist der Grund, warum es überhaupt mehr als ein
Match-Kriterium gibt:

```jsonc
{
  "id": "outlook-compose",
  "priority": 100,
  "match": {
    "bundleIdentifier": "com.microsoft.Outlook",
    "titlePattern": "(Nachricht|Message|Verfassen|Compose|Termin|Meeting)",
    "subroles": ["AXStandardWindow"],
    // Ausdrücklich abgeschaltet: das Verfassen-Fenster ist nie das erste.
    "onlyFirstWindowAfterLaunch": false
  },
  "action": { "role": "compose", "focus": "activate", "mode": "place" }
}
```

Und der Gegenpart, das Hauptfenster:

```jsonc
{
  "id": "outlook-main",
  "priority": 50,
  "match": {
    "bundleIdentifier": "com.microsoft.Outlook",
    "subroles": ["AXStandardWindow"],
    "minimumSize": { "width": 800, "height": 600 },
    // Der Standard: Erinnerungs-Popups und Dialoge fallen automatisch heraus.
    "onlyFirstWindowAfterLaunch": true
  },
  "action": {
    "role": "communication",
    // Obere Hälfte der Kommunikationszone; Teams nimmt die untere.
    "share": { "axis": "vertical", "slots": 2, "slotIndex": 0 },
    // Outlook startet oft im Hintergrund und soll den Fokus nicht stehlen.
    "focus": "leaveAsIs",
    "mode": "place"
  }
}
```

Das Titel-Pattern ist eine Krücke und als solche gedacht: Outlook-Titel sind
lokalisiert, das Pattern deckt deshalb deutsche und englische Varianten ab. Wer
nur eine Sprachvariante nutzt, sollte es kürzen.

---

## `defaults`

Vorgaben, die jede Regel erbt, solange sie sie nicht überschreibt.

```jsonc
{
  // Die wichtigste Voreinstellung überhaupt: Dialoge, Verfassen-Fenster und
  // Popups fallen automatisch heraus, ohne dass eine Titel-Regex nötig wäre.
  "onlyFirstWindowAfterLaunch": true,

  "allowedSubroles": ["AXStandardWindow"],
  "minimumWindowSize": { "width": 400, "height": 300 },

  "retry": {
    "attempts": 3,        // inklusive erstem Versuch
    "initialDelay": 0.05, // Sekunden bis zum ersten Versuch
    "interval": 0.2,      // Sekunden zwischen den Versuchen
    "tolerance": 4.0      // Punkte Abweichung, die noch als Erfolg zählen
  },

  "conflict": {
    "occupiedZone": "stack",        // "stack" | "replace" | "skip"
    "honorManualOverride": true,    // manuell verschobene Fenster in Ruhe lassen
    "manualOverrideTimeout": null   // null = für die Lebensdauer des Fensters
  }
}
```

### Zu `retry`

Ein Fenster existiert oft, bevor es endgültig dimensioniert ist; Electron- und
Office-Apps stellen ihre gespeicherte Geometrie nach dem Öffnen wieder her.
Deshalb wird platziert, zurückgelesen und wiederholt. Drei Versuche über rund
500 ms sind das Kleinste, was sich zuverlässig durchsetzt, ohne dass Fenster
sichtbar zappeln.

`tolerance` verhindert Endlosversuche gegen Apps mit Größenschritten
(Terminals) oder Mindestgrößen.

### Zu `conflict`

- `stack` — neues Fenster zusätzlich in die Zone, nichts wird verdrängt.
- `replace` — neues Fenster übernimmt, der bisherige Insasse wandert in die
  Fallback-Zone des Profils.
- `skip` — das neue Fenster bleibt, wo das System es geöffnet hat.

`honorManualOverride` ist die Höflichkeitsregel: zieht der Nutzer ein Fenster
selbst heraus, darf die Regel es nicht zurückreißen.

---

## Speicherort

Gesucht wird in dieser Reihenfolge; die erste Angabe gewinnt:

1. ein Pfad, den der Aufrufer ausdrücklich übergibt (Kommandozeilenschalter, Test),
2. die Umgebungsvariable `OPENZONR_CONFIG`,
3. `~/Library/Application Support/OpenZonr/config.json`.

Ein führendes `~` wird in den ersten beiden Fällen aufgelöst. Wer seine
Konfiguration im Dotfile-Repository pflegt, setzt also etwa:

```sh
export OPENZONR_CONFIG=~/dotfiles/openzonr.json
```

Fehlt die Datei, ist das kein Fehler, sondern der normale Zustand beim ersten
Start — OpenZonr fragt dann nach, statt eine Fehlermeldung zu zeigen.

### Schreiben

Geschrieben wird atomar: zuerst eine Zwischendatei im Zielverzeichnis, dann wird
die Zieldatei durch sie ersetzt. Bricht der Vorgang ab, bleibt die alte Datei
unangetastet. Eine halb geschriebene Konfiguration wäre schlimmer als eine
veraltete — die alte lässt sich wenigstens noch laden.

Die Ausgabe ist stabil: Schlüssel alphabetisch sortiert, eingerückt, mit
abschließendem Zeilenumbruch. Eine geänderte Zone erzeugt damit einen kurzen
Diff und keine umsortierte Datei.

### Migration

Das Feld `version` steuert die Migration. Beim Laden wird eine ältere Version
schrittweise auf den aktuellen Stand gehoben. Vor einer *schreibenden* Migration
sichert OpenZonr die Ursprungsdatei daneben als
`config.json.v<alte Version>.backup`.

Eine **neuere** Version als die dem Programm bekannte wird abgelehnt, nicht
teilweise gelesen: ein neueres Schema kann Felder verschoben haben, und eine halb
verstandene Konfiguration platziert Fenster dort, wo niemand sie haben wollte.
In diesem Fall hilft nur ein Update von OpenZonr.

---

## Fehler und Warnungen

Beim Laden wird die gesamte Datei geprüft und **alle** Befunde werden zusammen
gemeldet — nicht nur der erste. Wer drei Tippfehler in seiner Datei hat, soll sie
in einem Durchgang beheben können und nicht dreimal neu starten.

Jeder Befund nennt die Stelle im Dokument, an der er entstanden ist, etwa
`profiles[office].roleBindings[2].zone`.

Unterschieden wird zwischen:

- **Fehlern** — die Konfiguration ist unbenutzbar. Beispiele: eine Regel verweist
  auf eine Rolle, die es nicht gibt; eine Rollenbindung zeigt auf eine Zone, die
  im gewählten Layout dieses Displays nicht existiert; zwei Profile haben denselben
  Fingerprint; ein `titlePattern` ist kein übersetzbarer regulärer Ausdruck.
- **Warnungen** — die Konfiguration ist benutzbar, aber vermutlich nicht so
  gemeint. Beispiele: eine Rolle, die keine Regel verwendet; eine Regel, die von
  einer höher priorisierten vollständig überdeckt wird und deshalb nie greifen
  kann.

Warnungen halten das Laden nicht auf.
