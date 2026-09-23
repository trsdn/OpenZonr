import Foundation
import Testing

@testable import OpenZonrCore

/// Die Trefferfläche ist optional und bildschirmbezogen — derselbe Raum wie
/// ``Zone/frame``. Fehlt sie, ist sie der Zielrahmen; bestehende
/// Konfigurationen verhalten sich dadurch unverändert.
@Suite("Zone — Trefferfläche")
struct ZoneActivationAreaTests {

    @Test("Ohne Feld im JSON bleibt die Trefferfläche nil")
    func decodesMissingActivationAreaAsNil() throws {
        let json = """
        {"id":"links","name":"Links","frame":{"x":0,"y":0,"width":0.5,"height":1}}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(json.utf8))

        #expect(zone.activationArea == nil)
        #expect(zone.frame == RelativeRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test("Mit Feld im JSON wird die Trefferfläche gelesen")
    func decodesActivationArea() throws {
        let json = """
        {"id":"links","name":"Links",
         "frame":{"x":0,"y":0,"width":0.5,"height":1},
         "activationArea":{"x":0,"y":0.4,"width":0.5,"height":0.2}}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(json.utf8))

        #expect(zone.activationArea == RelativeRect(x: 0, y: 0.4, width: 0.5, height: 0.2))
    }

    @Test("Hin und zurück durch JSON verliert nichts")
    func roundTrips() throws {
        let zone = Zone(
            id: ZoneID(rawValue: "rechts"),
            name: "Rechts",
            frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            activationArea: RelativeRect(x: 0.9, y: 0, width: 0.1, height: 1)
        )

        let data = try JSONEncoder().encode(zone)
        #expect(try JSONDecoder().decode(Zone.self, from: data) == zone)
    }

    @Test("Ohne Trefferfläche bleibt das Feld beim Kodieren weg")
    func omitsNilActivationArea() throws {
        let zone = Zone(
            id: ZoneID(rawValue: "links"),
            name: "Links",
            frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)
        )

        let text = String(decoding: try JSONEncoder().encode(zone), as: UTF8.self)
        #expect(text.contains("activationArea") == false)
    }
}
