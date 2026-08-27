import Foundation

/// One schema-version hop for a raw configuration document.
///
/// Migrations are intentionally single-hop only: when a later schema version is
/// added, it contributes exactly one new step, instead of requiring every old
/// version to know an N-to-M migration matrix.
public protocol MigrationStep {

    var fromVersion: Int { get }

    /// The next schema version. Must always be `fromVersion + 1`.
    var toVersion: Int { get }

    func migrate(_ document: [String: Any]) throws -> [String: Any]
}
