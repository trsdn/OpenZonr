#!/bin/bash
#
# Packt OpenZonr in ein signiertes App-Bundle an einem festen Ort.
#
# Im Bundle liegt genau eine Binärdatei, und sie ist beides: ohne Argumente die
# Menüleisten-App, mit einem Unterbefehl das Kommandozeilenwerkzeug. Das ist
# kein Kunststück, sondern Notwendigkeit — die Bedienungshilfen-Freigabe gilt
# einem Programm an seinem Pfad. Zwei Binärdateien wären zwei Freigaben, und die
# Gegenprobe würde etwas anderes messen als das, was tatsächlich läuft.
#
# Ohne Signatur kommt man an die Bedienungshilfen nicht heran. Eine unsignierte
# Binärdatei bekommt zwar einen Haken in den Systemeinstellungen und
# AXIsProcessTrusted() meldet true, aber jeder Fensterzugriff liefert nur
# Platzhalter: AXWindows gibt Elemente mit der Rolle AXApplication zurück,
# AXPosition antwortet mit -25205. Der Grund ist die Prüfsumme — sie ändert
# sich bei jedem Neubau, und TCC erkennt das Programm nicht wieder.
#
# Die Designated Requirement einer Developer-ID-Signatur bindet dagegen an
# Bundle-Identifier und Team, nicht an die Prüfsumme:
#
#   identifier "com.trsdn.openzonr" and anchor apple generic
#     and certificate leaf[subject.OU] = <TEAM>
#
# Damit übersteht die Freigabe einen Neubau am selben Ort in der Regel; zugesichert
# ist das nicht (siehe unten, Issue #35). Ein Ad-hoc-Zertifikat genügt nicht — es
# hat keine solche Kette.
#
# Der Ort zählt aber trotzdem. Gemessen: ein frisch gebautes, identisch
# signiertes Bundle an einem neuen Pfad ist nicht freigegeben — beim Start über
# LaunchServices meldet es "nicht vertraut". Die Freigabe gilt also dem Programm
# an seinem Platz, nicht dem Identifier allein. Deshalb landet das Bundle
# standardmäßig unter ~/Applications und nicht in .build: dort überlebt es
# "swift package clean", einen zweiten Klon des Repos und den Wechsel des
# Arbeitsverzeichnisses. Ein anderer Zielort lässt sich als Argument übergeben —
# dann ist er einmalig neu freizugeben.
#
# Das Bundle hat dieselbe Gestalt wie ein veröffentlichtes.
#
# Seit Issue #47 baut der Notarisierungs-Broker aus demselben Quelltext, und
# sein `assemble_menu_bar_swiftpm` legt drei Dinge fest, die hier deshalb gleich
# sein müssen — sonst ist das, was lokal geprüft wird, nicht das, was per
# Update ankommt:
#
#   * Die Info.plist kommt aus Sources/OpenZonrApp/Info.plist. Hier wird nur
#     __VERSION__ ersetzt; der Broker setzt dieselben Schlüssel aus dem Tag.
#   * Die Binärdatei heisst im Bundle wie das SwiftPM-Produkt: OpenZonrApp.
#     Der Broker kennt dafür nur einen Namen und benutzt ihn für beides.
#     Die Bedienungshilfen-Freigabe hängt an Bundle-Identifier und Team (siehe
#     die Designated Requirement oben), nicht am Namen der Binärdatei.
#   * AppUpdater_AppUpdater.bundle liegt unter Contents/Resources. AppUpdater
#     bringt es als SwiftPM-Ressourcenbündel mit; ohne die Kopie fehlt es einem
#     lokal gebauten Bundle, und der Unterschied fiele erst beim Update auf.
#
# Eine Stelle läuft seit Issue #55 bewusst auseinander: das App-Icon. Hier wird
# Resources/AppIcon.icns nach Contents/Resources kopiert, `assemble_menu_bar_swiftpm`
# tut das nicht — der Adapter kopiert nur die Binärdatei, die im Profil genannten
# Ressourcenbündel und die Info.plist. Ein veröffentlichtes Bundle hat deshalb
# CFBundleIconFile, aber keine Icon-Datei, bis der Broker das nachzieht.
#
# Ein anderer Zielort als ~/Applications lässt sich als erstes Argument
# übergeben — für einen Probelauf, der die freigegebene Installation nicht
# anfasst:
#
#   Scripts/bundle.sh "$(mktemp -d)/OpenZonr.app"
#
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HOME/Applications/OpenZonr.app}"
PRODUCT="OpenZonrApp"
INFO_PLIST_SOURCE="$ROOT/Sources/$PRODUCT/Info.plist"

# Ohne Identität wird zwar gebaut und gepackt, aber nicht signiert — dann
# sieht das Ergebnis keine Fenster. Der Hinweis steht am Ende.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" \
  | head -1 \
  | sed -E 's/.*"(.*)"/\1/')}"

echo "==> Baue ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT" --product "$PRODUCT"

BIN_DIR="$(swift build -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)"
BINARY="$BIN_DIR/$PRODUCT"
[ -x "$BINARY" ] || { echo "Binärdatei fehlt: $BINARY" >&2; exit 1; }

# AppUpdater liefert seine Vertrauensanker als SwiftPM-Ressourcenbündel. Fehlt
# es, scheitert erst das Update — also lieber hier, laut und sofort.
RESOURCE_BUNDLE="$BIN_DIR/AppUpdater_AppUpdater.bundle"
[ -d "$RESOURCE_BUNDLE" ] || { echo "Ressourcenbündel fehlt: $RESOURCE_BUNDLE" >&2; exit 1; }

# Das eigene Ressourcenbündel trägt die übersetzten Oberflächentexte
# (Localizable.xcstrings, von SwiftPM nach <locale>.lproj/Localizable.strings
# übersetzt). Fehlt es, läuft die App weiter — sie zeigt dann überall die
# englischen Quelltexte, und niemandem fiele auf, dass die Übersetzung nicht
# ausgeliefert wurde. Deshalb hier laut abbrechen.
#
# Dasselbe Bündel muss im Broker-Profil unter `nested_resource_bundles`
# stehen, sonst fehlt es genau im veröffentlichten Bundle und nur dort.
APP_RESOURCE_BUNDLE="$BIN_DIR/OpenZonr_OpenZonrApp.bundle"
[ -d "$APP_RESOURCE_BUNDLE" ] || { echo "Ressourcenbündel fehlt: $APP_RESOURCE_BUNDLE" >&2; exit 1; }

# Das App-Icon liegt als erzeugte Datei im Repo (Scripts/make-icon.swift).
# Info.plist verweist mit CFBundleIconFile darauf; fehlt die Datei, zeigt macOS
# stumm das Platzhalter-Icon — also lieber hier abbrechen.
ICON="$ROOT/Resources/AppIcon.icns"
[ -f "$ICON" ] || { echo "App-Icon fehlt: $ICON (swift Scripts/make-icon.swift)" >&2; exit 1; }

echo "==> Packe $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$PRODUCT"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp -R "$APP_RESOURCE_BUNDLE" "$APP/Contents/Resources/"
# Vor dem Signieren, sonst siegelt die Signatur ein Bundle ohne Icon und
# `codesign --verify --deep --strict` schlägt hinterher fehl.
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

sed "s/__VERSION__/$VERSION/g" "$INFO_PLIST_SOURCE" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist" > /dev/null
# Ohne LSUIElement bekäme die Menüleisten-App ein Dock-Symbol. Der Broker
# verweigert in dem Fall die Signatur; hier wird derselbe Fehler früher laut.
plutil -extract LSUIElement raw "$APP/Contents/Info.plist" | grep -q '^true$' || {
	echo "Info.plist ohne LSUIElement=true — die App bekäme ein Dock-Symbol." >&2
	exit 1
}

if [ -z "$IDENTITY" ]; then
	cat >&2 <<'WARN'

Kein Developer-ID-Zertifikat gefunden — das Bundle bleibt unsigniert.

Es lässt sich starten, sieht aber keine Fenster: jeder Fensterzugriff
liefert Platzhalter, egal welchen Haken man in den Systemeinstellungen
setzt. Ein kostenloses Apple-ID-Konto genügt nicht, es braucht eine
Developer-ID.

WARN
	exit 0
fi

echo "==> Signiere mit: $IDENTITY"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --display --requirements - "$APP" 2>&1 | grep -A 1 "designated" || true

cat <<INFO

Fertig: $APP

Einmalig freigeben:
  Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen
  → "+" → $APP

Bei einem bestehenden Eintrag aus einem unsignierten Lauf: Eintrag
entfernen und neu hinzufügen. Den Haken nur neu zu setzen genügt nicht.

Die Freigabe gilt diesem Pfad. Solange hierhin gebaut wird, übersteht sie
einen Neubau in der Regel — auch aus einem anderen Klon des Repos. Wird das
Bundle woandershin gelegt, ist es dort erneut freizugeben.

Meldet "$APP/Contents/MacOS/OpenZonrApp selftest" (über LaunchServices gestartet:
open -n -a … --args selftest --out <datei>) nach einem Neubau trotzdem
"degraded", ist der Eintrag ungültig geworden, obwohl Pfad und Signatur gleich
geblieben sind (beobachtet am 30.08.2026, Ursache nicht geklärt). Dann den
Eintrag entfernen und neu hinzufügen; den Haken nur aus- und einzuschalten
genügt nicht.

Starten:
  open -n "$APP"          # Menüleisten-App
Gegenprobe — muss AXStandardWindow mit einer Größe ungleich 0x0 zeigen:
  "$APP/Contents/MacOS/OpenZonrApp" windows --bundle com.apple.Safari

Dieselbe Binärdatei, einmal mit und einmal ohne Unterbefehl. Was die
Gegenprobe misst, ist deshalb genau das Programm, das auch die App ist.

Zeigt die Gegenprobe stattdessen "Zugriff degradiert", fehlt die Freigabe
für dieses Bundle: AXIsProcessTrusted() erbt dann das Vertrauen vom
startenden Terminal, die Fensterzugriffe tun das nicht.
INFO
