import AppKit
import Foundation

/// Where the app shows itself.
///
/// The three states are exclusive on purpose. A Dock icon and a menu bar icon
/// at the same time is two doors into the same one-window app, and the second
/// one has to be explained every time someone asks why it is there.
///
/// `LSUIElement` in `Info.plist` stays `true` in every case. Both
/// `Scripts/bundle.sh` and the notarization broker refuse a bundle without it,
/// so the Dock icon cannot come from the plist — it comes from the activation
/// policy, applied once at launch.
public enum AppPresence: String, CaseIterable, Sendable {

    /// An icon in the menu bar, no Dock icon. What the app has always done.
    case menuBar

    /// A Dock icon, no menu bar icon.
    case dock

    /// Neither. The app runs and places windows, but shows nothing.
    case background

    /// The default, and deliberately the state the app already had: an upgrade
    /// must not move anyone's icon.
    public static let `default` = AppPresence.menuBar

    public var title: String {
        switch self {
        case .menuBar: return localized("appPresence.title.menuBar", "Menu Bar")
        case .dock: return localized("appPresence.title.dock", "Dock Icon")
        case .background: return localized("appPresence.title.background", "Background Only")
        }
    }

    /// Whether the menu bar carries the icon.
    public var showsMenuBarIcon: Bool {
        self == .menuBar
    }

    /// The activation policy this presence needs.
    ///
    /// `.regular` is what puts an icon in the Dock; `.accessory` is what keeps
    /// it out. `.prohibited` would also hide it but takes the app out of the
    /// window server's activation handling, and this app needs to come forward
    /// to show its own windows.
    public var activationPolicy: NSApplication.ActivationPolicy {
        self == .dock ? .regular : .accessory
    }

    /// Whether a user in this state can still reach the app's windows by
    /// ordinary means — clicking an icon.
    ///
    /// `false` for ``background``, and that is the whole reason
    /// ``AppDelegate`` answers a re-launch by opening the status window:
    /// without an icon and without that answer, choosing this state would lock
    /// the settings away behind the very setting that hid them.
    public var hasVisibleEntryPoint: Bool {
        self != .background
    }
}

/// Reads and writes the chosen presence.
///
/// Stored in `UserDefaults` rather than in the configuration file: it describes
/// this installation, not the window layout, and copying a configuration to
/// another machine should not drag an icon preference along with it.
@MainActor
public struct PresenceSettings {

    static let key = "presence"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored presence, or the default when nothing is stored — and also
    /// when something unreadable is stored. A preference that has rotted
    /// should not decide where the app's only entry point is.
    public var presence: AppPresence {
        get {
            guard let raw = defaults.string(forKey: Self.key),
                  let value = AppPresence(rawValue: raw)
            else { return .default }
            return value
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
