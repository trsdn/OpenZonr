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

    /// Dispatches to the command line before any scene exists.
    ///
    /// One binary, one signature, one Accessibility grant. The grant is bound to
    /// a bundle at a path, so a separate CLI binary — even signed with the same
    /// identifier — would have to be approved separately. Answering to
    /// subcommands here means `OpenZonr.app/Contents/MacOS/OpenZonr windows` is
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
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.status.symbolName)
                .accessibilityLabel("OpenZonr — \(model.status.headline)")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Holds the app to `.accessory` and keeps it alive without windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var didPresentPermissionWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces: LSUIElement in Info.plist already does this, but a
        // bundle built by hand or run from the build directory may not have it,
        // and a Dock icon on a window manager is noise.
        NSApp.setActivationPolicy(.accessory)

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

    /// Shows the permission window at most once per launch.
    func presentPermissionWindowOnce(model: AppModel) {
        guard !didPresentPermissionWindow else { return }
        didPresentPermissionWindow = true
        PanelPresenter.shared.show(
            id: "status",
            title: "OpenZonr — Status und Berechtigung",
            size: NSSize(width: 620, height: 560)
        ) {
            StatusWindow(model: model)
        }
    }
}
