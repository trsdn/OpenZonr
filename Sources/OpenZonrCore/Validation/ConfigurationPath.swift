import Foundation

/// A path to a location inside the configuration document, used to point a
/// human at the exact spot a validation finding refers to.
///
/// The rendered form mirrors how the JSON file reads, using the stable
/// identifier of a collection element instead of its index wherever one exists:
///
/// ```text
/// profiles[office].roleBindings[2].zone
/// displays[dell-u2723].layouts[dell-focus].zones[side].frame.width
/// ```
///
/// Identifiers are preferred over indices because a user editing the file finds
/// `profiles[office]` immediately, while `profiles[1]` requires counting.
public struct ConfigurationPath: Hashable, Sendable, CustomStringConvertible {

    /// One step of the path.
    public enum Component: Hashable, Sendable, CustomStringConvertible {
        /// A named field, rendered as `.name`.
        case field(String)
        /// A collection element addressed by its identifier, rendered as `[id]`.
        case key(String)
        /// A collection element addressed by its position, rendered as `[3]`.
        case index(Int)

        public var description: String {
            switch self {
            case let .field(name): return name
            case let .key(key): return "[\(key)]"
            case let .index(index): return "[\(index)]"
            }
        }
    }

    /// The steps from the document root to the referenced location.
    public private(set) var components: [Component]

    /// The document root.
    public init() {
        self.components = []
    }

    public init(components: [Component]) {
        self.components = components
    }

    /// Returns the path extended by a named field.
    public func field(_ name: String) -> ConfigurationPath {
        ConfigurationPath(components: components + [.field(name)])
    }

    /// Returns the path extended by a collection element addressed by its identifier.
    public func key(_ key: some CustomStringConvertible) -> ConfigurationPath {
        ConfigurationPath(components: components + [.key(key.description)])
    }

    /// Returns the path extended by a collection element addressed by its position.
    public func index(_ index: Int) -> ConfigurationPath {
        ConfigurationPath(components: components + [.index(index)])
    }

    /// Returns the path extended by a named collection and the identifier of one
    /// of its elements — the most common shape, e.g. `profiles[office]`.
    public func element(_ name: String, _ key: some CustomStringConvertible) -> ConfigurationPath {
        field(name).key(key)
    }

    /// Returns the path extended by a named collection and the position of one
    /// of its elements, for collections whose elements carry no identifier.
    public func element(_ name: String, at index: Int) -> ConfigurationPath {
        field(name).index(index)
    }

    public var description: String {
        var rendered = ""
        for component in components {
            switch component {
            case let .field(name):
                rendered += rendered.isEmpty ? name : ".\(name)"
            case .key, .index:
                rendered += component.description
            }
        }
        return rendered
    }
}
