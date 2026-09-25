import Foundation
import OpenZonrMac
import ServiceManagement

/// Start at login, via `SMAppService`.
///
/// `SMAppService.mainApp` registers the enclosing bundle, which is why the app
/// has to be the bundle's main executable rather than a helper next to the CLI.
/// The API throws for reasons the user can act on — an unsigned bundle, or a
/// registration the user revoked in System Settings — so the reason is kept and
/// shown instead of being swallowed into a checkbox that silently springs back.
enum LoginItem {

    nonisolated(unsafe) private(set) static var lastProblem: String?

    static var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        case .requiresApproval:
            lastProblem = localized(
                "loginItem.requiresApproval",
                "Login item is registered, but not yet approved by the system. "
                    + "Enable it in System Settings → General → Login Items → OpenZonr."
            )
            return false
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                lastProblem = nil
                Log.info(localized("loginItem.registered", "Login item registered."))
            } else {
                try SMAppService.mainApp.unregister()
                lastProblem = nil
                Log.info(localized("loginItem.unregistered", "Login item removed."))
            }
            // Registering can succeed and still land in "requires approval";
            // reading the status back is the only way to notice.
            _ = isEnabled
        } catch {
            let action = enabled
                ? localized("loginItem.actionRegistered", "registered")
                : localized("loginItem.actionRemoved", "removed")
            lastProblem = localized(
                "loginItem.registrationFailed",
                "Login item could not be %@: %@\n\n"
                    + "Most common reason: the bundle is not signed, or it sits in a "
                    + "place launchd does not accept. Scripts/bundle.sh signs it; the "
                    + "login item additionally needs the app in /Applications.",
                action, error.localizedDescription
            )
            Log.warn(lastProblem ?? "")
        }
    }
}
