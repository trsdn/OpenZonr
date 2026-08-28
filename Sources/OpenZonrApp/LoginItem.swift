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
            lastProblem = """
            Der Autostart ist eingetragen, aber vom System noch nicht genehmigt.
            Systemeinstellungen → Allgemein → Anmeldeobjekte → OpenZonr aktivieren.
            """
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
                Log.info("Autostart eingetragen.")
            } else {
                try SMAppService.mainApp.unregister()
                lastProblem = nil
                Log.info("Autostart entfernt.")
            }
            // Registering can succeed and still land in "requires approval";
            // reading the status back is the only way to notice.
            _ = isEnabled
        } catch {
            lastProblem = """
            Autostart konnte nicht \(enabled ? "eingetragen" : "entfernt") werden: \
            \(error.localizedDescription)

            Häufigster Grund: das Bundle ist nicht signiert, oder es liegt an einem
            Ort, den launchd nicht akzeptiert. Scripts/bundle.sh signiert; für den
            Autostart gehört die App zusätzlich nach /Applications.
            """
            Log.warn(lastProblem ?? "")
        }
    }
}
