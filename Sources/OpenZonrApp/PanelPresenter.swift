import AppKit
import SwiftUI

/// Shows the app's two windows.
///
/// Written against `NSWindow` rather than SwiftUI's `Window` scene on purpose:
/// the app is an `LSUIElement`, so a window has to bring its own activation,
/// and the permission window has to be openable from places that have no
/// SwiftUI environment — the launch path, for one, which is exactly when a
/// missing permission needs explaining.
@MainActor
final class PanelPresenter {

    static let shared = PanelPresenter()

    private var windows: [String: NSWindow] = [:]

    private init() {}

    func show(
        id: String,
        title: String,
        size: NSSize,
        @ViewBuilder content: () -> some View
    ) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("openzonr.\(id)")
        window.makeKeyAndOrderFront(nil)

        windows[id] = window
    }
}
