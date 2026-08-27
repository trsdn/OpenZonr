# OpenZonr — Konzept und Architektur

Stand: früher Konzeptstand. Dieses Dokument beschreibt das Modell, nicht eine
fertige Implementierung. Die Swift-Typen unter `Sources/OpenZonrCore/` sind die
formale Fassung desselben Modells.

---

## 1. Zielbild und Nicht-Ziele

**Ziel:** Fenster landen beim Öffnen automatisch dort, wo sie hingehören —
über wechselnde Monitor-Setups hinweg, ohne dass Regeln pro Setup dupliziert
werden müssen.

**Ausdrücklich nicht das Ziel:**

- Kein Tiling-Window-Manager. Es wird nicht automatisch alles angeordnet,
  sondern nur das, was der Nutzer explizit geregelt hat.
- Kein Ersatz für Mission Control oder Spaces-Verwaltung.
- Keine kontinuierliche Überwachung, die jedes Fenster dauerhaft festhält.
  Platziert wird beim Öffnen; danach gehört das Fenster dem Nutzer.

Der letzte Punkt ist eine Haltung, keine technische Einschränkung: ein Tool,
das auf seinen Regeln beharrt, kämpft gegen den Nutzer statt für ihn.

---

## 2. Die Platzierungs-Pipeline

```
NSWorkspace.didLaunchApplication
        │
        ▼
AXObserver je App  ──  kAXWindowCreatedNotification
        │
        ▼
[1] Fensterfilter        Subrole, Mindestgröße, „erstes Fenster nach Launch"
        │
        ▼
[2] Regelauswertung      erste passende Regel nach Priorität gewinnt
        │
        ▼
[3] Rollenauflösung      Rolle → aktives Profil → Display + Zone
        │
        ▼
[4] Geometrie            RelativeRect × visibleFrame → absoluter Frame
        │
        ▼
[5] Platzieren           kAXPositionAttribute / kAXSizeAttribute
        │                mit Retry-Loop und Rücklesen des Ergebnisses
        ▼
   PlacementOutcome      protokolliert für Diagnose und UI
```

### Fensterquelle

Zwei Ereignisquellen greifen ineinander:

- `NSWorkspace.didLaunchApplicationNotification` meldet neu gestartete Apps.
  Für jede wird ein `AXObserver` erzeugt und auf
  `kAXWindowCreatedNotification` registriert.
- Beim Start von OpenZonr scannt ein einmaliger Durchlauf die bereits laufenden
  Apps und hängt dort ebenfalls Observer an.

`NSWorkspace` allein genügt nicht, weil eine App beim Start noch kein Fenster
hat. Der `AXObserver` allein genügt nicht, weil er an eine konkrete PID gebunden
ist und für neue Prozesse erst angelegt werden muss.

### Die entscheidende Stelle: Timing

Ein Fenster existiert häufig, bevor es endgültig dimensioniert ist. Electron-Apps
und die Office-Suite setzen nach dem ersten Zeichnen ihre gespeicherte
Fenstergeometrie, teilweise mehrfach und asynchron. Einmaliges Setzen von
Position und Größe wird deshalb Millisekunden später überschrieben — das Fenster
springt kurz und liegt dann doch wieder falsch.

Gegenmaßnahme: **platzieren, zurücklesen, wiederholen**. Der Frame wird nach dem
Setzen erneut über die Accessibility-API gelesen und mit dem gewünschten Frame
verglichen. Weicht er außerhalb der Toleranz ab, folgt der nächste Versuch.
Voreinstellung: drei Versuche, verteilt über rund 500 ms (`initialDelay` 50 ms,
`interval` 200 ms, Toleranz 4 Punkte). Das ist das Kleinste, was sich zuverlässig
gegen selbst-resizende Apps durchsetzt, ohne dass Fenster sichtbar zappeln.

Die Toleranz ist kein Detail: Terminals erzwingen Größenschritte in Zeichenbreiten,
manche Apps haben eine Mindestgröße. Ohne Toleranz würde gegen ein Fenster
angerannt, das seinem Ziel bereits so nah ist, wie es je kommen wird.

---

## 3. Welches Fenster überhaupt?

Outlook öffnet ein Hauptfenster, Verfassen-Fenster, Terminserien-Dialoge und
Erinnerungs-Popups. Ohne Filter würde jedes davon platziert.

Drei Filterstufen, aufsteigend nach Aufwand für den Nutzer:

1. **Subrole `AXStandardWindow`.** Schließt Dialoge, Sheets, Paletten und die
   meisten Popups aus, ohne dass irgendetwas konfiguriert werden muss.
2. **Mindestgröße** (Standard 400×300 Punkte). Fängt ab, was durchrutscht:
   Erinnerungsfenster, Fortschrittsanzeigen, Tool-Paletten.
3. **Titel-Regex** — die scharfe Waffe, aber die letzte Wahl. Fenstertitel sind
   lokalisiert und ändern sich oft Sekundenbruchteile nach dem Öffnen.

### Die wichtigste Voreinstellung

**„Nur erstes Fenster nach App-Start"** ist standardmäßig aktiv. Dialoge,
Verfassen-Fenster und Popups erscheinen *später* und fallen dadurch automatisch
heraus — ohne dass jemand eine Titel-Regex schreiben muss. Diese eine
Voreinstellung erspart einen großen Teil der sonst nötigen Feinarbeit.

Wer ein Verfassen-Fenster gezielt platzieren will, schaltet sie für genau diese
Regel ab und ergänzt ein Titel-Pattern — siehe die Regel `outlook-compose` in der
Beispielkonfiguration.

---

## 4. Das Regelmodell: Match → Aktion

Eine Regel besteht aus Kriterien und einer Aktion.

### Match-Kriterien

Alle optional, alle mit **UND** verknüpft:

| Kriterium | Zweck |
|---|---|
| `bundleIdentifier` | Der Basisfall, z. B. `com.microsoft.Outlook`. |
| `titlePattern` | Trennt „Posteingang" von Verfassen-Fenstern. |
| `roles` / `subroles` | Standardfenster gegen Dialog. |
| `minimumSize` / `maximumSize` | Filtert Popups und Paletten. |
| `aspectRatio` | Fängt die restlichen ungewöhnlichen Formate ab. |
| `onlyFirstWindowAfterLaunch` | Siehe oben; überschreibt die globale Voreinstellung. |

Eine leere Match-Definition passt auf jedes Fenster. Als Auffangregel mit
niedrigster Priorität am Ende ist das sinnvoll, überall sonst gefährlich.

Die Kriterien bilden bewusst genau das ab, was die Accessibility-API zum
Zeitpunkt von `kAXWindowCreatedNotification` billig liefert. Alles, was tiefere
Inspektion verlangt, würde den Platzierungspfad verlangsamen — und der ist
ohnehin im Wettlauf mit dem Layout-Code der App.

### Aktion

- **`role`** — das semantische Ziel (siehe Abschnitt 5). Pflichtangabe.
- **`share`** — optionale Unterteilung der Zone in gleich große Slots
  (Achse, Slot-Anzahl, Slot-Index). Damit teilen sich Mail und Chat eine
  Kommunikationszone, ohne dass dafür eine zweite Zone gezeichnet werden muss.
  Alles Komplexere gehört als eigene Zone ins Layout.
- **`focus`** — `activate` oder `leaveAsIs`. Für Apps, die beim Login im
  Hintergrund starten, ist `leaveAsIs` die vernünftige Wahl.
- **`mode`** — `place` oder `suggest`. `suggest` verschiebt nichts, sondern bietet
  die Platzierung an. Nützlich beim Einfahren einer neuen Regel und für Apps, die
  schlecht darauf reagieren, während des Starts bewegt zu werden.

---

## 5. Die zentrale Indirektion: Rollen statt Zonen

Regeln zeigen **nicht** auf eine Zone, sondern auf eine **Rolle**. Jedes Profil
mappt Rollen auf seine eigenen Zonen:

```
Regel:              Outlook → Rolle „Kommunikation"

Profil Büro:        Kommunikation = Dell U2723,  Zone rechts (50 %)
Profil Home:        Kommunikation = LG 38",      Zone rechts außen (25 %)
Profil Unterwegs:   Kommunikation = Builtin,     rechte Hälfte
```

Der Gewinn: App-Regeln werden **einmal** geschrieben statt pro Setup dupliziert.
Ein neuer Monitor bedeutet ein neues Profil mit fünf Rollenbindungen — nicht das
Neuschreiben aller App-Regeln. Und eine Rolle umzuhängen („Kommunikation gehört
ab jetzt links") ist ein einziger Eintrag statt einer Suche durch alle Regeln.

Der Datenfluss insgesamt:

```
Regel ──match──▶ Rolle ──Profil──▶ Display + Zone ──Layout──▶ Geometrie
```

### Fallback ist Pflicht

Ist eine Rolle im aktiven Profil nicht gemappt, greift die im Profil hinterlegte
`fallback`-Bindung. Sie ist ein Pflichtfeld, und das mit Absicht: eine nicht
gemappte Rolle darf niemals „irgendwo" bedeuten. Das Fenster landet an einer
definierten Stelle, und das Ereignis wird protokolliert, damit die Lücke sichtbar
wird statt still zu bleiben.

---

## 6. Monitor-Identität

Der schwierigste Teil, weil hier alle naheliegenden Lösungen falsch sind.

### Was nicht funktioniert

| Ansatz | Warum er scheitert |
|---|---|
| Position im Arrangement | Ändert sich beim Umstecken oder Verschieben in den Systemeinstellungen. |
| Index in `NSScreen.screens` | Reihenfolge ist nicht stabil, insbesondere beim Aufwachen. |
| Auflösung allein | Zwei baugleiche Monitore sind nicht unterscheidbar. |
| `CGDirectDisplayID` | Wird pro Sitzung vergeben, nicht über Neustarts hinweg stabil. |

### Was funktioniert

Die EDID-Daten, die CoreGraphics bereitstellt:

- `CGDisplayVendorNumber`
- `CGDisplayModelNumber`
- `CGDisplaySerialNumber`

Damit ist ein Monitor eindeutig, egal an welchem Port und in welcher Reihenfolge
er angeschlossen wird.

**Sonderfall integriertes Display:** wird über `CGDisplayIsBuiltin` erkannt und
als eigener Identitätsfall geführt. Es ist der einzige Bildschirm, der in jedem
Setup vorhanden ist und nie gegen ein anderes Modell getauscht wird, ohne dass
gleichzeitig die Maschine getauscht wird.

**Fallback ohne Seriennummer:** manche Monitore melden `0` als Seriennummer.
Dann greift Vendor + Model + native Pixelgröße + Port-Index. Das ist nicht global
eindeutig, aber stabil, solange nicht zwei baugleiche Monitore zwischen Ports
getauscht werden. Der Fall wird im Datenmodell ausdrücklich als `fallback`
markiert, damit die UI genau davor warnen kann.

---

## 7. Setup-Fingerprint und Profile

Das aktive Profil ergibt sich aus dem **Fingerprint**: dem sortierten,
reihenfolgeunabhängigen Set aller aktiven Monitor-Identitäten.

```
{builtin}                          → „Unterwegs"
{builtin, DellU2723-SN1194485571}  → „Büro"
{builtin, LG38-SN909876}           → „Home"
```

Reihenfolgeunabhängigkeit ist wichtig: ob der externe Monitor vor oder nach dem
Dock erkannt wird, darf die Profilwahl nicht beeinflussen.

**Beobachtung** über `CGDisplayRegisterReconfigurationCallback`. Der Callback
feuert beim An- und Abstecken mehrfach, während Displays aufwachen und
Auflösungen aushandeln. Deshalb wird entprellt, bevor der Fingerprint neu
berechnet wird — sonst wird während eines einzigen Dock-Vorgangs mehrfach das
Profil gewechselt.

**Unbekannter Fingerprint → nachfragen, nicht raten.** Ein neues Setup führt zur
Rückfrage, ob ein Profil angelegt werden soll. Ein „bestes ähnliches Profil" zu
erraten würde Fenster stillschweigend auf den falschen Bildschirm legen — das ist
schlechter, als nichts zu tun.

In der Konfigurationsdatei referenzieren Profile Displays über einen kurzen
**Alias** (`"dell-u2723"`) statt über die rohe Identität. Das hält die Datei
lesbar; die Auflösung Alias → Identität übernimmt die Display-Tabelle.

---

## 8. Zonen und Layouts

**Zonen werden niemals in Pixeln gespeichert**, sondern prozentual relativ zum
*sichtbaren* Frame — also ohne Menüleiste und Dock. Der Büromonitor ist kleiner
als der Home-Ultrawide; eine in Punkten gespeicherte Zone wäre auf dem einen
Bildschirm passend und auf dem anderen unbrauchbar. Auch Skalierungsänderungen
und ein ein- oder ausgeblendetes Dock verschieben die nutzbare Fläche.

Koordinatensystem der `RelativeRect`: Ursprung `(0, 0)` oben links, `(1, 1)`
unten rechts. AppKit rechnet von unten links; die Umrechnung passiert in der
Platzierungsschicht, nicht im Dateiformat — oben links ist das, was Menschen in
einem Zoneneditor zeichnen.

**Layouts gehören an das Display, nicht an das Profil.** Ein 38-Zoll-Ultrawide
will ein Drei-Spalten-Layout, ein 24-Zöller ein Zwei-Spalten-Layout, und das
bleibt wahr, egal welches Profil gerade aktiv ist. Ein Display kann mehrere
Layouts besitzen; das aktive Profil wählt aus, welches verwendet wird
(`profile.layouts`), sonst gilt `defaultLayoutID`.

Zonen innerhalb eines Layouts dürfen sich überlappen. Das ist eine legitime
Gestaltung — eine große Fokuszone über zwei Hälften gelegt —, deshalb wird es
nicht verboten. Mehrdeutigkeit wird über Rollenbindungen aufgelöst, nie durch
Raten anhand der Geometrie.

---

## 9. Konfliktauflösung

Drei Konfliktarten, alle explizit geregelt.

### Mehrere passende Regeln

Auswertung nach `priority` absteigend, bei Gleichstand in Dateireihenfolge.
**Die erste passende Regel gewinnt**, danach wird abgebrochen.

Daraus folgt: **spezifisch vor generisch**. Die Outlook-Compose-Regel muss eine
höhere Priorität haben als die allgemeine Outlook-Regel — sonst greift die
allgemeine zuerst und die spezifische kommt nie zum Zug. In der
Beispielkonfiguration ist das an den Prioritäten 100 gegen 50 ablesbar.

### Zielzone ist besetzt

Drei konfigurierbare Strategien (`conflict.occupiedZone`):

- **`stack`** (Voreinstellung) — das neue Fenster kommt zusätzlich in die Zone.
  Nichts wird verdrängt; die Zone hält mehrere Fenster, durch die man wechseln
  kann. Die konservative Wahl.
- **`replace`** — das neue Fenster übernimmt die Zone, der bisherige Insasse
  wandert in die Fallback-Zone des Profils.
- **`skip`** — das neue Fenster bleibt dort, wo das System es geöffnet hat.

### Manuelle Übersteuerung

Zieht der Nutzer ein Fenster selbst aus seiner Zone heraus, ist das eine
Aussage. **Die Regel darf es nicht zurückreißen.** Das Fenster wird als manuell
übersteuert markiert (`conflict.honorManualOverride`, Voreinstellung `true`) und
für den Rest seiner Lebensdauer in Ruhe gelassen. Optional lässt sich über
`manualOverrideTimeout` festlegen, dass die Übersteuerung nach einer Zeitspanne
verfällt.

---

## 10. Stolperfallen

### Berechtigungen

Ohne Accessibility-Berechtigung geht nichts — weder Beobachten noch Platzieren.
Zwei Konsequenzen:

- Die App muss den Nutzer sauber durch die Erteilung führen und mit
  `AXIsProcessTrustedWithOptions` prüfen, statt bei fehlender Berechtigung
  wortlos nichts zu tun. Dafür existiert `PlacementOutcome.missingPermission`.
- **Die App muss signiert sein.** Der Accessibility-Grant hängt an der
  Code-Signatur. Bei einer unsignierten oder ad-hoc signierten App verfällt er
  bei jedem Update, und der Nutzer muss den Eintrag jedes Mal aus den
  Systemeinstellungen entfernen und neu erteilen.

### Selbst-resizende Apps

Siehe Abschnitt 2. Electron-Builds und die Office-Suite stellen ihre gespeicherte
Geometrie nach dem Öffnen wieder her. Der Retry-Loop mit Rücklesen ist die
Antwort.

### Nicht-kooperative Apps

Java-Toolkits (AWT/Swing) und einzelne Electron-Builds ignorieren
AX-Positionierung teilweise oder klemmen sie auf ihre eigene Vorstellung eines
gültigen Frames. Dafür gibt es `PlacementOutcome.rejectedByApplication` mit dem
tatsächlich erreichten Frame: die UI kann die betroffene App benennen, statt still
zu scheitern. Wie weit darüber hinaus nachgesetzt werden soll, ist offen — siehe
`docs/offene-fragen.md`.

### Fenstertitel

Lokalisiert und oft erst nach dem Erscheinen final gesetzt. Titel-Regex deshalb
nur dort, wo es nicht anders geht.

---

## 11. UI in zwei Stufen

**Stufe 1 — einfach, deckt rund 90 % der Fälle:**
Rechtsklick auf ein platziertes Fenster → *„Diese App immer hier öffnen"*. Im
Hintergrund entsteht eine Regel auf die Bundle-ID mit der Rolle, die zur aktuellen
Zone gehört. Kein Regeleditor, kein Formular, keine Erklärung nötig.

**Stufe 2 — erweitert:**
Ein Regeleditor mit den Match-Kriterien aus Abschnitt 4, für Fälle wie das
Outlook-Verfassen-Fenster. Wer ihn nicht braucht, sieht ihn nicht.

Darunter liegt in beiden Fällen dieselbe **Konfigurationsdatei im JSON-Format** —
versionierbar, teilbar, als Text editierbar. Wer möchte, umgeht die UI komplett.

---

## 12. Ausbaustufen

1. Datenmodell und Konfigurationsformat *(dieser Stand)*
2. Monitorerkennung: Identität, Fingerprint, Profilwechsel
3. Fenstererkennung und Filter, zunächst nur protokollierend
4. Platzierung mit Retry-Loop
5. Regelauswertung und Rollenauflösung
6. Menüleisten-App mit Stufe-1-UI
7. Zoneneditor und Regeleditor
8. Signierung und Verteilung

Die Reihenfolge folgt dem Risiko: Monitoridentität und Platzierungs-Timing sind
die Teile, an denen das Konzept scheitern könnte. Sie kommen zuerst.
