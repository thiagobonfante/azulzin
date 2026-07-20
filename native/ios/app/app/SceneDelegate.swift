import HotwireNative
import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?

    private let tabBarController = HotwireTabBarController()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()
        tabBarController.delegate = self
        tabBarController.load(TabBar.tabs)
    }

    // Tabs that loaded while signed out are parked on the sign-in redirect; after the
    // user authenticates in another tab, selecting them re-routes to the real start
    // location. Signed out this costs one redundant reload per tap — acceptable.
    // ponytail: sign-OUT staleness (other tabs keep authenticated snapshots until
    // tapped… and a tap keeps the stale page since location looks legit) is NOT
    // handled here — revisit with the biometric-lock phase.
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let hotwireTabBarController = tabBarController as? HotwireTabBarController,
              TabBar.tabs.indices.contains(tabBarController.selectedIndex) else { return }
        let navigator = hotwireTabBarController.activeNavigator
        guard navigator.activeWebView.url?.path == "/session/new" else { return }
        // REPLACE, not push: the stale sign-in page must leave the stack — a push
        // would put a back arrow on the tab root pointing at it.
        navigator.route(TabBar.tabs[tabBarController.selectedIndex].url,
                        options: VisitOptions(action: .replace))
    }
}
