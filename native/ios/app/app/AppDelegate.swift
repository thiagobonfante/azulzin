import HotwireNative
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
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

        // Push registration bridge (.plans/mobile/04 §3). Firebase boots only when the
        // founder-provisioned GoogleService-Info.plist ships with the app.
        Hotwire.registerBridgeComponents([PushComponent.self])
        #if canImport(FirebaseCore)
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            FirebaseApp.configure()
        }
        #endif
        UNUserNotificationCenter.current().delegate = self
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

    // MARK: - Notification tap-through (.plans/mobile/04 §1: data.url deep link)

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let url = response.notification.request.content.userInfo["url"] as? String {
            let scene = UIApplication.shared.connectedScenes.first
            (scene?.delegate as? SceneDelegate)?.route(path: url)
        }
        completionHandler()
    }

    // Foreground pushes still show as a banner (quiet, no sound doctrine lives server-side).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge])
    }
}
