import Foundation
import Testing
@testable import OpenZonrCore

/// Pixelmaße einer Fallback-Identität sind Anzeigeinformation. Sie dürfen nicht
/// bestimmen, ob ein Monitor wiedererkannt wird: ein Moduswechsel ändert sie.
struct DisplayIdentityTests {

    private func fallback(width: Int, height: Int, port: Int = 1) -> DisplayIdentity {
        .fallback(vendorNumber: 19501, modelNumber: 7, pixelWidth: width, pixelHeight: height, portIndex: port)
    }

    @Test("Gleicher Monitor in zwei Modi ist dieselbe Identität")
    func sameMonitorDifferentModes() {
        #expect(fallback(width: 3840, height: 2160) == fallback(width: 2560, height: 1440))
        #expect(fallback(width: 3840, height: 2160).hashValue == fallback(width: 2560, height: 1440).hashValue)
        #expect(Set([fallback(width: 3840, height: 2160), fallback(width: 0, height: 0)]).count == 1)
    }

    @Test("Ein anderer Port bleibt eine andere Identität")
    func differentPortStaysDifferent() {
        #expect(fallback(width: 3840, height: 2160, port: 1) != fallback(width: 3840, height: 2160, port: 2))
    }

    @Test("Anderes Modell bleibt eine andere Identität")
    func differentModelStaysDifferent() {
        let other = DisplayIdentity.fallback(
            vendorNumber: 19501, modelNumber: 8, pixelWidth: 3840, pixelHeight: 2160, portIndex: 1
        )
        #expect(fallback(width: 3840, height: 2160) != other)
    }

    @Test("Fallback ist nie gleich einer EDID-Identität")
    func fallbackNeverEqualsEdid() {
        let edid = DisplayIdentity.edid(vendorNumber: 19501, modelNumber: 7, serialNumber: 1)
        #expect(fallback(width: 3840, height: 2160) != edid)
    }

    @Test("Eine alte Datei mit Modus-Pixelmaßen decodiert zu einer gleichen Identität")
    func legacyJSONDecodesEqual() throws {
        let legacy = Data("""
        {"kind":"fallback","vendorNumber":19501,"modelNumber":7,
         "pixelWidth":2560,"pixelHeight":1440,"portIndex":1}
        """.utf8)
        let decoded = try JSONDecoder().decode(DisplayIdentity.self, from: legacy)
        #expect(decoded == fallback(width: 3840, height: 2160))
    }

    @Test("Das Codable-Format behält die Pixelmaße bei")
    func encodingKeepsPixelFields() throws {
        let data = try JSONEncoder().encode(fallback(width: 3840, height: 2160))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["pixelWidth"] as? Int == 3840)
        #expect(object["pixelHeight"] as? Int == 2160)
    }
}
