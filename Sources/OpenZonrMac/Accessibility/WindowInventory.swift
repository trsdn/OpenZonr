import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenZonrCore

/// Window server metadata that the Accessibility API does not expose.
///
/// Accessibility knows nothing about `kCGWindowLayer`, yet the layer is the most
/// reliable way to tell a real application window from system furniture. The
/// index is built from `CGWindowListCopyWindowInfo` and joined to Accessibility
/// windows over process id plus bounds — both APIs report bounds in the same
/// top-left based global space, so the join is exact rather than fuzzy.
public struct CoreGraphicsWindowIndex {

    public struct Entry {
        public var layer: Int
        public var bounds: CGRect
        public var title: String?
        public var ownerName: String?
        public var ownerPID: pid_t
    }

    public private(set) var entries: [Entry] = []
    private var byPID: [pid_t: [Entry]] = [:]

    public init(onScreenOnly: Bool = true) {
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        entries = raw.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            return Entry(
                layer: layer,
                bounds: bounds,
                title: info[kCGWindowName as String] as? String,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                ownerPID: pid
            )
        }

        byPID = Dictionary(grouping: entries, by: \.ownerPID)
    }

    /// The layer of the window of `pid` whose bounds match `frame`.
    ///
    /// Falls back to the process's lowest observed layer when no exact match is
    /// found: a window may have been resized between the two API calls, and
    /// guessing "the app's usual layer" is far better than treating an unmatched
    /// window as system furniture.
    public func layer(forPID pid: pid_t, frame: WindowFrame) -> Int? {
        guard let candidates = byPID[pid], !candidates.isEmpty else { return nil }

        let target = frame.cgRect
        if let exact = candidates.first(where: { $0.bounds.integral == target.integral }) {
            return exact.layer
        }
        return candidates.map(\.layer).min()
    }
}

/// Builds ``WindowSnapshot`` values from live Accessibility elements.
public enum WindowInventory {

    /// One window, paired with the element it came from.
    public struct Item {
        public var application: NSRunningApplication
        public var element: AXUIElement
        public var snapshot: WindowSnapshot
    }

    /// Every window of every running application, optionally filtered.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: restricts the listing to one application.
    ///   - includeAccessoryApps: menu bar agents and background apps are hidden
    ///     by default; their windows are exactly the layer noise that the filter
    ///     rejects anyway.
    @MainActor
    public static func allWindows(
        bundleIdentifier: String? = nil,
        includeAccessoryApps: Bool = false
    ) -> [Item] {
        let index = CoreGraphicsWindowIndex()

        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard includeAccessoryApps || app.activationPolicy == .regular else { return false }
                guard let bundleIdentifier else { return true }
                return app.bundleIdentifier == bundleIdentifier
            }
            .sorted { ($0.bundleIdentifier ?? "") < ($1.bundleIdentifier ?? "") }
            .flatMap { app in
                items(for: app, index: index)
            }
    }

    @MainActor
    public static func items(
        for application: NSRunningApplication,
        index: CoreGraphicsWindowIndex,
        isFirstWindowAfterLaunch: Bool = false
    ) -> [Item] {
        let pid = application.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        return Accessibility.windows(of: appElement).enumerated().compactMap { offset, window in
            guard let frame = Accessibility.frame(of: window) else { return nil }
            return Item(
                application: application,
                element: window,
                snapshot: snapshot(
                    of: window,
                    application: application,
                    frame: frame,
                    layer: index.layer(forPID: pid, frame: frame) ?? 0,
                    // Position in the app's window list is the best available
                    // proxy when the tool did not observe the launch itself.
                    isFirstWindowAfterLaunch: isFirstWindowAfterLaunch || offset == 0
                )
            )
        }
    }

    @MainActor
    public static func snapshot(
        of window: AXUIElement,
        application: NSRunningApplication,
        frame: WindowFrame,
        layer: Int,
        isFirstWindowAfterLaunch: Bool
    ) -> WindowSnapshot {
        WindowSnapshot(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            title: Accessibility.string(window, kAXTitleAttribute as String),
            role: Accessibility.string(window, kAXRoleAttribute as String),
            subrole: Accessibility.string(window, kAXSubroleAttribute as String),
            frame: frame,
            isFirstWindowAfterLaunch: isFirstWindowAfterLaunch,
            observedAt: Date(),
            windowLayer: layer
        )
    }
}
