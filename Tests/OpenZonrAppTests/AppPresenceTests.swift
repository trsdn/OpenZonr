import AppKit
import Foundation
import Testing

@testable import OpenZonrApp

/// Where the app shows itself, and what that implies.
///
/// The interesting part is not the enum but the two promises around it: an
/// upgrade must not move anyone's icon, and choosing "background" must not lock
/// the settings away behind the setting that hid them.
@Suite("App presence")
@MainActor
struct AppPresenceTests {

    private func settings(_ suiteName: String = UUID().uuidString) -> (PresenceSettings, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PresenceSettings(defaults: defaults), defaults)
    }

    /// The state the app already had. Anything else would move the icon of
    /// every existing installation on upgrade.
    @Test("Nothing stored means the menu bar, as before")
    func defaultsToTheMenuBar() {
        let (store, _) = settings()

        #expect(store.presence == .menuBar)
        #expect(AppPresence.default == .menuBar)
    }

    @Test("A stored choice is read back")
    func storedChoiceRoundTrips() {
        let (store, _) = settings()

        for value in AppPresence.allCases {
            store.presence = value
            #expect(store.presence == value)
        }
    }

    /// A preference that has rotted must not decide where the only entry point
    /// is — falling back to the menu bar always leaves a way in.
    @Test("An unreadable value falls back to the menu bar")
    func unreadableValueFallsBack() {
        let (store, defaults) = settings()
        defaults.set("moon", forKey: PresenceSettings.key)

        #expect(store.presence == .menuBar)
    }

    @Test("Only the Dock state asks for a Dock icon")
    func onlyDockUsesRegularPolicy() {
        #expect(AppPresence.dock.activationPolicy == .regular)
        #expect(AppPresence.menuBar.activationPolicy == .accessory)
        #expect(AppPresence.background.activationPolicy == .accessory)
    }

    /// Exclusive by design: two icons are two doors into a one-window app.
    @Test("Only the menu bar state carries the menu bar icon")
    func onlyMenuBarShowsTheIcon() {
        #expect(AppPresence.menuBar.showsMenuBarIcon)
        #expect(AppPresence.dock.showsMenuBarIcon == false)
        #expect(AppPresence.background.showsMenuBarIcon == false)
    }

    /// The flag that obliges the delegate to answer a re-launch. If this ever
    /// becomes true for `background`, the re-open handler can go — and not
    /// before.
    @Test("Only the background state has no visible way in")
    func onlyBackgroundHasNoEntryPoint() {
        #expect(AppPresence.menuBar.hasVisibleEntryPoint)
        #expect(AppPresence.dock.hasVisibleEntryPoint)
        #expect(AppPresence.background.hasVisibleEntryPoint == false)
    }

    /// Every state shows the app somewhere, or is the one state that does not
    /// and is handled for it. Nothing may fall between the two.
    @Test("Every state either shows an icon or is handled as invisible")
    func everyStateIsAccountedFor() {
        for value in AppPresence.allCases {
            let visible = value.showsMenuBarIcon || value.activationPolicy == .regular
            #expect(visible == value.hasVisibleEntryPoint)
        }
    }
}
