import AppKit
import OpenZonrMac
import SwiftUI

/// OpenZonr as a menu bar app.
///
/// **Why a SwiftPM executable and not an Xcode app target.** The issue proposed
/// an Xcode target next to the package. It is not needed, and adding one would
/// cost something real. `Scripts/bundle.sh` already produces the signed bundle
/// that the Accessibility grant is bound to, `MenuBarExtra` and `SMAppService`
/// need nothing an executable target cannot provide, and keeping one build
/// system means `swift build` and `swift test` stay the whole story — headless,
/// diffable, without a `.pbxproj` to merge. If entitlements that require a
/// provisioning profile ever become necessary, that is the moment to revisit
/// this, and not before.
///
/// The app is an `LSUIElement`: no Dock icon, no menu bar of its own. What runs
/// inside it is ``WatchEngine``, unchanged from what the command line tool uses.
@main
struct OpenZonrMenuBarApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    /// Read once, at launch, like the activation policy beside it. A change
    /// takes effect on the next start — see ``AppDelegate``.
    private let presence = PresenceSettings().presence

    /// Dispatches to the command line before any scene exists.
    ///
    /// One binary, one signature, one Accessibility grant. The grant is bound to
    /// a bundle at a path, so a separate CLI binary — even signed with the same
    /// identifier — would have to be approved separately. Answering to
    /// subcommands here means `OpenZonr.app/Contents/MacOS/OpenZonrApp windows` is
    /// the diagnostic tool *and* the approved program, which is exactly what the
    /// cross-check in the README needs it to be.
    ///
    /// `run` never returns: every subcommand ends in `exit`, and `watch` parks
    /// on `CFRunLoopRun()`. Nothing of the app is set up yet at this point.
    init() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let first = arguments.first, OpenZonrCommandLine.isSubcommand(first) {
            OpenZonrCommandLine.run(arguments)
        }
    }

    var body: some Scene {
        // `isInserted` is a constant on purpose: the value is read once at
        // launch. A binding that could flip at runtime would promise a live
        // switch the activation policy beside it cannot honour.
        MenuBarExtra(isInserted: .constant(presence.showsMenuBarIcon)) {
            MenuContent(model: model)
        } label: {
            // `accessibilityLabel` deliberately static, no longer woven
            // together with the continuously changing status (Issue #69).
            // Suspicion, not proof: AppKit's own accessibility code for
            // status items (`NSAccessibilityMockStatusBarItem`) crashed
            // twice, both times right on a click on this symbol, both times
            // while building its attribute list. A label recomputed on
            // every status change gives AppKit more opportunities for that
            // than a fixed one does; the symbol itself stays dynamic,
            // because a changing icon is the ordinary case with no fallout
            // elsewhere. The status appears as the menu's first line anyway
            // once it is open.
            Image(systemName: model.status.symbolName)
                .accessibilityLabel("OpenZonr")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Holds the app to `.accessory` and keeps it alive without windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var didPresentPermissionWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The chosen presence decides the activation policy, and it is applied
        // once, here. `LSUIElement` stays `true` in the plist in every case —
        // both `Scripts/bundle.sh` and the notarization broker refuse a bundle
        // without it — so a Dock icon can only come from `.regular`.
        //
        // Applied at launch and not when the setting changes: switching the
        // activation policy of a running app is not known to leave the
        // Accessibility grant intact, and that grant is the one thing in this
        // app nobody can restore for the user. A restart is the cheap, honest
        // price; the settings say so.
        NSApp.setActivationPolicy(PresenceSettings().presence.activationPolicy)

        let model = AppModel.shared
        model.onStatusChange = { [weak self] status in
            // The first launch after installation almost always lands here, and
            // a menu bar icon alone does not explain what to do about it. The
            // window does — once, so it never becomes a nag.
            if status == .needsPermission { self?.presentPermissionWindowOnce(model: model) }
        }
        model.bootstrap()
        if model.status == .needsPermission { presentPermissionWindowOnce(model: model) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Answers a re-launch by showing the status window.
    ///
    /// This is the way back out of ``AppPresence/background``. With no menu bar
    /// icon and no Dock icon, opening the app again is the only gesture a user
    /// has left — and without this it would do nothing at all, because the app
    /// is already running. Choosing the invisible state would then hide the
    /// setting that undoes it.
    ///
    /// It also answers a re-launch in the other two states, where it is merely
    /// convenient rather than necessary.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        PanelPresenter.shared.show(
            id: "status",
            title: localized("statusWindow.panelTitle", "OpenZonr — Status and Permission"),
            size: NSSize(width: 620, height: 560)
        ) {
            StatusWindow(model: AppModel.shared)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// Shows the permission window at most once per launch.
    func presentPermissionWindowOnce(model: AppModel) {
        guard !didPresentPermissionWindow else { return }
        didPresentPermissionWindow = true
        PanelPresenter.shared.show(
            id: "status",
            title: localized("statusWindow.panelTitle", "OpenZonr — Status and Permission"),
            size: NSSize(width: 620, height: 560)
        ) {
            StatusWindow(model: model)
        }
    }
}
