#!/bin/bash
#
# Packt openzonr in ein signiertes App-Bundle an einem festen Ort.
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
# Damit überlebt die Freigabe jeden Neubau am selben Ort. Ein Ad-hoc-Zertifikat
# genügt nicht — es hat keine solche Kette.
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
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.trsdn.openzonr}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$HOME/Applications/OpenZonr.app}"

# Ohne Identität wird zwar gebaut und gepackt, aber nicht signiert — dann
# sieht das Ergebnis keine Fenster. Der Hinweis steht am Ende.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" \
  | head -1 \
  | sed -E 's/.*"(.*)"/\1/')}"

echo "==> Baue ($CONFIGURATION)"
swift build -c "$CONFIGURATION" --package-path "$ROOT"

BINARY="$ROOT/.build/$CONFIGURATION/openzonr"
[ -x "$BINARY" ] || { echo "Binärdatei fehlt: $BINARY" >&2; exit 1; }

echo "==> Packe $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/OpenZonr"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>OpenZonr</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_IDENTIFIER</string>
	<key>CFBundleName</key>
	<string>OpenZonr</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<!-- Kein Eintrag im Dock: das Werkzeug hat keine Oberfläche. -->
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

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

Die Freigabe gilt diesem Pfad. Solange hierhin gebaut wird, überlebt sie
jeden Neubau — auch aus einem anderen Klon des Repos. Wird das Bundle
woandershin gelegt, ist es dort erneut freizugeben.

Gegenprobe — muss AXStandardWindow mit einer Größe ungleich 0x0 zeigen:
  "$APP/Contents/MacOS/OpenZonr" windows --bundle com.apple.Safari

Zeigt die Gegenprobe stattdessen "Zugriff degradiert", fehlt die Freigabe
für dieses Bundle: AXIsProcessTrusted() erbt dann das Vertrauen vom
startenden Terminal, die Fensterzugriffe tun das nicht.
INFO
