import Foundation
import Testing

@testable import OpenZonrCore

/// Die gemessene Port-Index-Drift und die Toleranz, die sie auffängt.
///
/// Der Anlass ist keine Theorie, sondern eine Messung vom 19.09.2026 auf dem
/// Rechner des Autors: derselbe Monitor (C49RG9x, Vendor 19501, Modell 3996,
/// Seriennummer 0) trug am 29.08.2026 die `CGDisplayUnitNumber` 0 und am
/// 19.09.2026 die 1. Dazwischen lag nichts als ein Software-Display ("AAA",
/// Vendor 21252, Modell 0), das die Nummernvergabe verschoben hat — die Nummern
/// 0, 1, 2, 3 gingen in Aufzählungsreihenfolge an AAA, C49RG9x, U28E590 und
/// Teleprompter. In der Konfiguration stand `portIndex: 0`, die Maschine meldete
/// `1`, kein Profil passte, und damit war die gesamte Dropzone-Funktion weg.
///
/// Die Toleranz ist deshalb bewusst eng: sie greift nur, wenn Vendor + Modell
/// sowohl konfiguriert als auch beobachtet **genau einmal** vorkommen. Bei
/// baugleichen Monitoren ohne Seriennummer bleibt es beim Port-Vergleich, weil
/// dort jedes Raten den falschen Monitor treffen würde.
@Suite("Abgleich beobachteter Identitäten gegen die Konfiguration")
struct DisplayIdentityReconcilerTests {

    // MARK: - Gemessene Fixtures (19.09.2026)

    /// Der Ultrawide, wie ihn die Konfiguration seit dem 29.08.2026 führt.
    static let c49Configured = DisplayIdentity.fallback(
        vendorNumber: 19501, modelNumber: 3996, pixelWidth: 5120, pixelHeight: 1440, portIndex: 0
    )

    /// Derselbe Monitor, wie ihn die Maschine am 19.09.2026 meldet.
    static let c49Observed = DisplayIdentity.fallback(
        vendorNumber: 19501, modelNumber: 3996, pixelWidth: 5120, pixelHeight: 1440, portIndex: 1
    )

    /// Das zweite Panel — volle EDID, von der Drift also gar nicht betroffen.
    static let u28 = DisplayIdentity.edid(vendorNumber: 19501, modelNumber: 3149, serialNumber: 810_375_238)

    /// "AAA": Software-Display, gemessen mit Vendor 21252, Modell 0, Unit 0.
    static let aaa = DisplayIdentity.fallback(
        vendorNumber: 21252, modelNumber: 0, pixelWidth: 0, pixelHeight: 0, portIndex: 0
    )

    /// "Teleprompter Source": ebenfalls ein Software-Display. Vendor und Modell
    /// sind hier gesetzt, nicht gemessen — gemessen ist nur, dass es zusammen mit
    /// AAA auftauchte und die Unit-Nummer 3 belegte.
    static let teleprompter = DisplayIdentity.fallback(
        vendorNumber: 21252, modelNumber: 1, pixelWidth: 0, pixelHeight: 0, portIndex: 3
    )

    /// Die Konfiguration des Autors, auf das Nötige eingedampft: der Ultrawide
    /// mit `portIndex: 0`, das EDID-Panel, beide Software-Displays unter
    /// `ignoredDisplays`.
    static func measuredConfiguration() -> Configuration {
        var configuration = TestConfigurations.minimal()
        configuration.displays = [
            descriptor(alias: "c49rg9x", identity: c49Configured),
            descriptor(alias: "u28e590", identity: u28)
        ]
        configuration.profiles = [
            Profile(
                id: "schreibtisch",
                name: "Schreibtisch",
                fingerprint: ProfileFingerprint(displays: ["c49rg9x", "u28e590"]),
                roleBindings: [
                    RoleBinding(role: "editor", display: "c49rg9x", zone: "full"),
                    RoleBinding(role: "communication", display: "u28e590", zone: "full")
                ],
                fallback: RoleBinding(role: "editor", display: "c49rg9x", zone: "full")
            )
        ]
        configuration.ignoredDisplays = [aaa, teleprompter]
        return configuration
    }

    static func descriptor(alias: DisplayAlias, identity: DisplayIdentity) -> DisplayDescriptor {
        DisplayDescriptor(
            alias: alias,
            displayName: alias.rawValue,
            identity: identity,
            layouts: [Layout(id: "voll", name: "Vollbild", zones: [Zone(id: "full", name: "Vollbild", frame: .full)])],
            defaultLayoutID: "voll"
        )
    }

    static func snapshot(_ identity: DisplayIdentity, name: String = "Display") -> DisplaySnapshot {
        let port: Int
        if case let .fallback(_, _, _, _, portIndex) = identity { port = portIndex } else { port = 0 }
        return DisplaySnapshot(
            identity: identity,
            localizedName: name,
            displayID: UInt32(port + 1),
            pixelWidth: 1920,
            pixelHeight: 1080,
            backingScaleFactor: 1,
            frame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: WindowFrame(x: 0, y: 0, width: 1920, height: 1080),
            portIndex: port
        )
    }

    // MARK: - Der gemessene Fall

    @Test("Der gemessene Fall: der Ultrawide wird trotz verschobenem Port erkannt")
    func measuredDriftResolvesTheProfile() {
        let configuration = Self.measuredConfiguration()
        let snapshots = [
            Self.snapshot(Self.aaa, name: "AAA"),
            Self.snapshot(Self.c49Observed, name: "C49RG9x"),
            Self.snapshot(Self.u28, name: "U28E590"),
            Self.snapshot(Self.teleprompter, name: "Teleprompter Source")
        ]

        let reconciler = configuration.displayReconciler(observing: snapshots)
        #expect(reconciler.resolve(Self.c49Observed) == Self.c49Configured)

        let fingerprint = SetupFingerprint(
            snapshots: snapshots,
            ignoring: configuration.ignoredDisplays,
            reconciler: reconciler
        )
        #expect(fingerprint.displays == [Self.c49Configured, Self.u28])

        let profile = DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration)
        #expect(profile?.id == "schreibtisch")
    }

    @Test("Der Abgleich meldet die Abweichung, statt sie zu verschlucken")
    func driftIsReported() throws {
        let configuration = Self.measuredConfiguration()
        let snapshots = [
            Self.snapshot(Self.aaa, name: "AAA"),
            Self.snapshot(Self.c49Observed, name: "C49RG9x"),
            Self.snapshot(Self.u28, name: "U28E590"),
            Self.snapshot(Self.teleprompter, name: "Teleprompter Source")
        ]
        let reconciler = configuration.displayReconciler(observing: snapshots)

        let drifts = reconciler.portDrifts
        #expect(drifts.count == 1)
        let drift = try #require(drifts.first)
        #expect(drift.configuredPortIndex == 0)
        #expect(drift.observedPortIndex == 1)
        #expect(drift.sentence == "konfiguriert als port=0, aktuell port=1: erkannt, weil eindeutig")
        #expect(reconciler.portDrift(for: Self.c49Observed) != nil)
        #expect(reconciler.portDrift(for: Self.u28) == nil)
    }

    @Test("Die sichtbaren Rahmen finden den Bildschirm ebenfalls über den Abgleich")
    func visibleFramesUseTheReconciler() {
        let configuration = Self.measuredConfiguration()
        let snapshots = [Self.snapshot(Self.c49Observed, name: "C49RG9x"), Self.snapshot(Self.u28)]
        let reconciler = configuration.displayReconciler(observing: snapshots)
        let frames = ScreenArrangement(snapshots: snapshots)
            .visibleFrames(for: configuration.displays, reconciler: reconciler)

        #expect(frames["c49rg9x"] != nil)
        #expect(frames["u28e590"] != nil)
    }

    @Test("Der Profil-Resolver gleicht selbst ab, auch ohne vorbereiteten Abgleich")
    func resolverReconcilesOnItsOwn() {
        let configuration = Self.measuredConfiguration()
        let snapshots = [Self.snapshot(Self.c49Observed), Self.snapshot(Self.u28)]

        // Der Fingerprint trägt hier noch die beobachtete Identität mit Port 1 …
        let fingerprint = SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays)
        #expect(fingerprint.displays.contains(Self.c49Observed))

        // … und der Resolver findet das Profil trotzdem. Das ist Absicht: ein
        // Aufrufer, der den Abgleich vergisst, bekommt keine stille Fehlfunktion
        // zurück. Ein zweiter Abgleich auf bereits abgeglichene Werte ändert
        // nichts, deshalb kostet der doppelte Weg auch nichts.
        #expect(DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration)?.id == "schreibtisch")
    }

    // MARK: - Baugleiche Monitore: keine Toleranz

    @Test("Zwei baugleiche Monitore ohne Seriennummer werden nicht zusammengeworfen")
    func identicalMonitorsStayExact() {
        let left = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 0
        )
        let right = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 1
        )
        let shifted = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 2
        )

        var configuration = TestConfigurations.minimal()
        configuration.displays = [
            Self.descriptor(alias: "links", identity: left),
            Self.descriptor(alias: "rechts", identity: right)
        ]
        configuration.profiles = [
            Profile(
                id: "paar",
                name: "Paar",
                fingerprint: ProfileFingerprint(displays: ["links", "rechts"]),
                roleBindings: [RoleBinding(role: "editor", display: "links", zone: "full")],
                fallback: RoleBinding(role: "editor", display: "links", zone: "full")
            )
        ]

        // Beide Anschlüsse um eins verschoben: hier ist jede Zuordnung geraten.
        let snapshots = [Self.snapshot(right), Self.snapshot(shifted)]
        let reconciler = configuration.displayReconciler(observing: snapshots)
        #expect(reconciler.resolve(shifted) == shifted)
        #expect(reconciler.portDrifts.isEmpty)

        let fingerprint = SetupFingerprint(snapshots: snapshots, reconciler: reconciler)
        #expect(DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration) == nil)
    }

    @Test("Ein konfigurierter, zwei beobachtete Monitore desselben Typs: kein Raten")
    func twoObservedOfOneConfiguredStayExact() {
        let configured = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 0
        )
        let first = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 1
        )
        let second = DisplayIdentity.fallback(
            vendorNumber: 4268, modelNumber: 42145, pixelWidth: 3840, pixelHeight: 2160, portIndex: 2
        )

        let reconciler = DisplayIdentityReconciler(configured: [configured], observed: [first, second])
        #expect(reconciler.resolve(first) == first)
        #expect(reconciler.resolve(second) == second)
        #expect(reconciler.portDrifts.isEmpty)
    }

    @Test("Ein exakter Treffer schlägt die Toleranz")
    func exactMatchWins() {
        let configuredA = DisplayIdentity.fallback(
            vendorNumber: 7, modelNumber: 9, pixelWidth: 0, pixelHeight: 0, portIndex: 0
        )
        let configuredB = DisplayIdentity.fallback(
            vendorNumber: 7, modelNumber: 9, pixelWidth: 0, pixelHeight: 0, portIndex: 4
        )
        let reconciler = DisplayIdentityReconciler(
            configured: [configuredA, configuredB],
            observed: [configuredB]
        )
        #expect(reconciler.resolve(configuredB) == configuredB)
        #expect(reconciler.portDrifts.isEmpty)
    }

    // MARK: - EDID und builtin bleiben unberührt

    @Test("EDID- und builtin-Identitäten werden ausschließlich exakt verglichen")
    func edidAndBuiltinAreUntouched() {
        let known = DisplayIdentity.edid(vendorNumber: 19501, modelNumber: 3996, serialNumber: 42)
        let sameModelOtherSerial = DisplayIdentity.edid(vendorNumber: 19501, modelNumber: 3996, serialNumber: 43)
        let fallbackOfSameModel = DisplayIdentity.fallback(
            vendorNumber: 19501, modelNumber: 3996, pixelWidth: 0, pixelHeight: 0, portIndex: 7
        )

        let reconciler = DisplayIdentityReconciler(
            configured: [known, .builtin],
            observed: [sameModelOtherSerial, fallbackOfSameModel, .builtin]
        )
        #expect(reconciler.resolve(sameModelOtherSerial) == sameModelOtherSerial)
        #expect(reconciler.resolve(fallbackOfSameModel) == fallbackOfSameModel)
        #expect(reconciler.resolve(.builtin) == .builtin)
        #expect(reconciler.portDrifts.isEmpty)
    }

    // MARK: - ignoredDisplays

    @Test("Auch ignorierte Displays werden mit derselben Toleranz erkannt")
    func ignoredDisplaysAreReconciledToo() {
        var configuration = Self.measuredConfiguration()
        // Das Software-Display steht mit Port 5 in der Konfiguration, meldet sich
        // aber als Port 0 — genau die Drift, nur auf der ignorierten Seite.
        configuration.ignoredDisplays = [
            .fallback(vendorNumber: 21252, modelNumber: 0, pixelWidth: 0, pixelHeight: 0, portIndex: 5)
        ]

        let snapshots = [
            Self.snapshot(Self.aaa, name: "AAA"),
            Self.snapshot(Self.c49Observed, name: "C49RG9x"),
            Self.snapshot(Self.u28, name: "U28E590")
        ]
        let reconciler = configuration.displayReconciler(observing: snapshots)
        let fingerprint = SetupFingerprint(
            snapshots: snapshots,
            ignoring: configuration.ignoredDisplays,
            reconciler: reconciler
        )

        #expect(fingerprint.displays == [Self.c49Configured, Self.u28])
        #expect(DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration)?.id == "schreibtisch")
    }

    // MARK: - Die Verweigerung bleibt

    @Test("Ein zusätzliches unbekanntes Display liefert weiterhin kein Profil")
    func unknownDisplayStillYieldsNoProfile() {
        let configuration = Self.measuredConfiguration()
        let stranger = DisplayIdentity.edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3)
        let snapshots = [
            Self.snapshot(Self.c49Observed, name: "C49RG9x"),
            Self.snapshot(Self.u28, name: "U28E590"),
            Self.snapshot(stranger, name: "Beamer")
        ]
        let reconciler = configuration.displayReconciler(observing: snapshots)
        let fingerprint = SetupFingerprint(
            snapshots: snapshots,
            ignoring: configuration.ignoredDisplays,
            reconciler: reconciler
        )
        #expect(DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration) == nil)
    }

    @Test("Die Vorschau eines Bildschirms findet den verschobenen Port ebenfalls")
    func canvasAspectUsesTheReconciler() {
        let configuration = Self.measuredConfiguration()
        let snapshots = [Self.snapshot(Self.c49Observed, name: "C49RG9x")]
        let reconciler = configuration.displayReconciler(observing: snapshots)
        let aspect = canvasAspect(
            for: configuration.displays[0],
            snapshots: snapshots,
            reconciler: reconciler
        )
        #expect(aspect.source == .measured)
    }

    @Test("Der Abgleich ist deterministisch — gleiche Eingabe, gleiche Zuordnung")
    func reconciliationIsDeterministic() {
        let configuration = Self.measuredConfiguration()
        let snapshots = [
            Self.snapshot(Self.teleprompter),
            Self.snapshot(Self.c49Observed),
            Self.snapshot(Self.aaa),
            Self.snapshot(Self.u28)
        ]
        let first = configuration.displayReconciler(observing: snapshots)
        let second = configuration.displayReconciler(observing: snapshots.reversed())
        #expect(first.portDrifts == second.portDrifts)
        #expect(first.resolve(Self.c49Observed) == second.resolve(Self.c49Observed))
    }
}
