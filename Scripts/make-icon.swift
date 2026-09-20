// Erzeugt Resources/AppIcon.icns aus Code.
//
//     swift Scripts/make-icon.swift
//
// Das Icon liegt als erzeugte Datei im Repo, damit Scripts/bundle.sh und der
// Broker es unverändert ins Bundle kopieren können. Reproduzierbar ist es
// trotzdem: der Entwurf steht hier, nicht in einer Binärdatei, die niemand
// mehr aufbekommt.
//
// Das Bild zeigt, was die App tut: ein Fenster, aufgeteilt in drei Zonen im
// Verhältnis 25/50/25 — dieselbe Aufteilung wie die Vorlage `wide` in
// Sources/OpenZonrCore/Geometry/LayoutTemplates.swift. Die mittlere Zone ist
// hervorgehoben, so wie die Dropzone-Überlagerung das Ziel unter dem Zeiger
// einfärbt (NSColor.controlAccentColor, siehe DropzoneOverlay.swift).
//
// Keine Schrift, keine Fremdbilder: nur Rechtecke und Verläufe. Das hält das
// Motiv auch bei 16 px lesbar, wo alles Feine ohnehin verschwindet.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Apple rechnet das Icon-Raster auf 1024 pt. Die gerundete Platte darunter ist
// 824 pt breit; die übrigen 100 pt an jeder Seite bleiben frei für den
// Schlagschatten, den macOS selbst zeichnet.
private let canvas: CGFloat = 1024
private let plateInset: CGFloat = 100
private let plateSize: CGFloat = canvas - 2 * plateInset
// 0,2237 der Kantenlänge ist der Radius, den Apples Icon-Raster vorgibt.
private let plateRadius: CGFloat = plateSize * 0.2237

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha
        ]
    )!
}

/// Rechteck aus Angaben von oben gemessen — so, wie ein Entwurf gelesen wird.
/// CoreGraphics zählt von unten, die Umrechnung steht deshalb nur hier.
private func rect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvas - top - height, width: width, height: height)
}

private func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations)!
}

/// Füllt einen Pfad mit einem senkrechten Verlauf (oben -> unten).
private func fill(_ path: CGPath, in context: CGContext, with gradient: CGGradient) {
    let box = path.boundingBox
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.midX, y: box.maxY),
        end: CGPoint(x: box.midX, y: box.minY),
        options: []
    )
    context.restoreGState()
}

private func roundedRect(_ box: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func drawArtwork(in context: CGContext) {
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Die Platte: ein blauer Verlauf von hell oben nach dunkel unten. Dunkel
    // genug, dass das weisse Fenster darauf auch bei 16 px noch heraussticht.
    let plate = roundedRect(
        rect(x: plateInset, top: plateInset, width: plateSize, height: plateSize),
        radius: plateRadius
    )
    fill(plate, in: context, with: gradient([color(0x4F9BF5), color(0x14367E)], [0, 1]))

    // Ein heller Saum an der Oberkante — das, was eine gewölbte Fläche mit
    // Licht macht. Bleibt so schwach, dass es bei kleinen Größen nur die Kante
    // weicher wirken lässt.
    context.saveGState()
    context.addPath(plate)
    context.clip()
    fill(
        roundedRect(
            rect(x: plateInset, top: plateInset, width: plateSize, height: plateSize * 0.45),
            radius: plateRadius
        ),
        in: context,
        with: gradient([color(0xFFFFFF, 0.20), color(0xFFFFFF, 0)], [0, 1])
    )
    context.restoreGState()

    // Das Fenster. Breiter als hoch, wie ein Bildschirmfenster, und mittig auf
    // der Platte.
    let windowWidth: CGFloat = 648
    let windowHeight: CGFloat = 464
    let windowLeft = (canvas - windowWidth) / 2
    let windowTop = (canvas - windowHeight) / 2
    let windowBox = rect(x: windowLeft, top: windowTop, width: windowWidth, height: windowHeight)
    let windowRadius: CGFloat = 52
    let window = roundedRect(windowBox, radius: windowRadius)

    // Schatten unter dem Fenster, damit es auf der Platte liegt und nicht
    // darin klebt.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -18),
        blur: 44,
        color: color(0x061B3E, 0.45)
    )
    context.addPath(window)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    fill(window, in: context, with: gradient([color(0xFFFFFF), color(0xE7EEF9)], [0, 1]))

    // Titelleiste: ein schmaler Streifen am oberen Rand. Bei 16 px ist das ein
    // Pixel Grau — es stört nicht und macht das Fenster bei 128 px erkennbar.
    let titleBarHeight: CGFloat = 62
    context.saveGState()
    context.addPath(window)
    context.clip()
    context.setFillColor(color(0xD3E0F2))
    context.fill(rect(x: windowLeft, top: windowTop, width: windowWidth, height: titleBarHeight))
    context.setFillColor(color(0xB6C9E4))
    context.fill(rect(x: windowLeft, top: windowTop + titleBarHeight - 4, width: windowWidth, height: 4))
    context.restoreGState()

    // Die drei Zonen: 25 / 50 / 25, getrennt durch gleich breite Fugen.
    let padding: CGFloat = 36
    let gap: CGFloat = 22
    let zonesLeft = windowLeft + padding
    let zonesTop = windowTop + titleBarHeight + padding * 0.75
    let zonesWidth = windowWidth - 2 * padding
    let zonesHeight = windowHeight - titleBarHeight - padding * 1.75
    let usableWidth = zonesWidth - 2 * gap
    let widths: [CGFloat] = [usableWidth * 0.25, usableWidth * 0.5, usableWidth * 0.25]
    let zoneRadius: CGFloat = 18

    var x = zonesLeft
    for (index, width) in widths.enumerated() {
        let box = rect(x: x, top: zonesTop, width: width, height: zonesHeight)
        let path = roundedRect(box, radius: zoneRadius)
        if index == 1 {
            // Die mittlere Zone ist das Ziel: kräftiges Akzentblau, so wie die
            // Dropzone-Überlagerung die Zone unter dem Zeiger einfärbt.
            fill(path, in: context, with: gradient([color(0x2F8BFF), color(0x0A5FE0)], [0, 1]))
        } else {
            // Die Randzonen sind deutlich dunkler als das Fenster, sonst
            // verschwindet die Dreiteilung bei 16 px im Weiss.
            fill(path, in: context, with: gradient([color(0xA8BFDE), color(0x8EA9CD)], [0, 1]))
        }
        x += width + gap
    }
}

private func renderPNG(size: Int, to url: URL) throws {
    guard
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    drawArtwork(in: context)

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = repositoryRoot.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Die Größen, die macOS in einem .iconset erwartet.
let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

for variant in variants {
    try renderPNG(size: variant.size, to: iconset.appendingPathComponent("\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "--convert", "icns",
    "--output", resources.appendingPathComponent("AppIcon.icns").path,
    iconset.path
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil ist fehlgeschlagen.\n".utf8))
    exit(1)
}

try FileManager.default.removeItem(at: iconset)
print("Resources/AppIcon.icns erzeugt.")
