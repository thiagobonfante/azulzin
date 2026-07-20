import HotwireNative
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Server can gate features per app version later without new plumbing (02 §1).
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        Hotwire.config.applicationUserAgentPrefix = "Azulzin/\(version)"

        // Bundled copy = first-launch/offline fallback; remote wins when reachable.
        // Keep the bundle file in sync with PathConfigurationsController at release time.
        Hotwire.loadPathConfiguration(from: [
            .file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!),
            .server(Config.pathConfigurationRemoteURL)
        ])
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // The Info.plist scene manifest is auto-generated (no delegate entry) — point the
        // configuration at SceneDelegate in code so the wiring survives plist regeneration.
        let configuration = UISceneConfiguration(name: "Default Configuration",
                                                 sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
