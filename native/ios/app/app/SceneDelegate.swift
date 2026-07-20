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

        // The framework keeps its per-tab navigators private; activeNavigator is the only
        // public handle, so visit each index once to install the mic-granting UI delegate
        // (programmatic selection is cheap — load() already routed every navigator — and
        // never calls didSelect).
        for index in TabBar.tabs.indices {
            tabBarController.selectedIndex = index
            let navigator = tabBarController.activeNavigator
            navigator.webkitUIDelegate = AzulzinUIController(delegate: navigator)
        }
        tabBarController.selectedIndex = 0
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
        let tabURL = TabBar.tabs[tabBarController.selectedIndex].url
        let parked = navigator.activeWebView.url?.path
        // Parked on the sign-in redirect, or on the post-auth landing (root) while not
        // being the Início tab — the tab the user signed IN on shows root until re-tapped.
        let stale = parked == "/session/new" || (parked == TabBar.tabs[0].url.path && tabURL != TabBar.tabs[0].url)
        guard stale else { return }
        // REPLACE, not push: the stale page must leave the stack — a push would put a
        // back arrow on the tab root pointing at it.
        navigator.route(tabURL, options: VisitOptions(action: .replace))
    }
}
