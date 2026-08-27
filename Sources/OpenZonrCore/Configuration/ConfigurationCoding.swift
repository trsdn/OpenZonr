import Foundation

/// The single place that knows how a configuration is turned into bytes and back.
///
/// Output is deliberately stable: keys sorted, pretty printed, slashes not
/// escaped. The configuration file is meant to live in a Git repository, so a
/// change of one zone must produce a one-line diff and not a reshuffled file.
public enum ConfigurationCoding {

    /// Encoder used for every write.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Decoder used for every read.
    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Encodes a configuration into its on-disk representation, terminated by a
    /// newline so the file is well-formed for line-based tools.
    public static func encode(_ configuration: Configuration) throws -> Data {
        var data = try makeEncoder().encode(configuration)
        if data.last != 0x0A {
            data.append(0x0A)
        }
        return data
    }

    /// Decodes a configuration from its on-disk representation.
    public static func decode(_ data: Data) throws -> Configuration {
        try makeDecoder().decode(Configuration.self, from: data)
    }
}
