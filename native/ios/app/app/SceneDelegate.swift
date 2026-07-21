import HotwireNative
import LocalAuthentication
import UIKit
import WebKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?

    private lazy var tabBarController = HotwireTabBarController(navigatorDelegate: self)

    // Biometric lock (.plans/mobile/02 §4): gate on cold start and on foreground after
    // > 2 min in background; the overlay doubles as the app-switcher privacy screen.
    private let lockScreen = LockScreenViewController()
    private var unlocked = false
    private var backgroundedAt: Date?
    private var authenticating = false
    private let relockAfter: TimeInterval = 120

    // Tabs holding a stale snapshot after a sign-out elsewhere; re-routed on selection.
    private var dirtyTabs = Set<Int>()

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

        showLockCover()
    }

    // MARK: - Biometric lock + privacy screen

    func sceneWillResignActive(_ scene: UIScene) {
        // Privacy: never let the app-switcher snapshot show balances. The Face ID sheet
        // itself resigns active — don't cover (and cancel the auth) mid-evaluation.
        guard !authenticating else { return }
        showLockCover()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        backgroundedAt = Date()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        CaptureInbox.drain()   // share-extension inbox → /captures (.plans/mobile/05 §3)
        if let at = backgroundedAt, Date().timeIntervalSince(at) > relockAfter { unlocked = false }
        backgroundedAt = nil
        guard !unlocked else { return hideLockCover() }
        authenticate()
    }

    private func authenticate() {
        guard !authenticating else { return }
        let context = LAContext()
        var error: NSError?
        // No device credential at all → never lock the user out of their own finances.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlocked = true
            return hideLockCover()
        }
        authenticating = true
        lockScreen.showRetry(false)
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: String(localized: "lock.reason")) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authenticating = false
                if success {
                    self.unlocked = true
                    self.hideLockCover()
                } else {
                    self.lockScreen.showRetry(true)
                    self.lockScreen.onRetry = { [weak self] in self?.authenticate() }
                }
            }
        }
    }

    private func showLockCover() {
        guard lockScreen.presentingViewController == nil, let root = window?.rootViewController else { return }
        lockScreen.modalPresentationStyle = .fullScreen
        (root.presentedViewController ?? root).present(lockScreen, animated: false)
    }

    private func hideLockCover() {
        guard lockScreen.presentingViewController != nil else { return }
        lockScreen.dismiss(animated: false)
    }

    // MARK: - Push tap-through (.plans/mobile/04): select the Início tab, then route the
    // deep link there — routing whatever tab is visible strands the page in that tab's
    // stack (Android twin routes a hidden navigator, which looks like a dead tap).

    func route(path: String) {
        tabBarController.selectedIndex = 0
        tabBarController.activeNavigator.route(Config.baseURL.appendingPathComponent(path))
    }

    // MARK: - Tab selection re-routes

    // Tabs that loaded while signed out park on the sign-in redirect; tabs that were
    // authenticated when a sign-out happened elsewhere keep a stale snapshot (dirtyTabs);
    // the tab the user signed IN on shows the root landing. All three re-route to the
    // tab's start location on selection. Signed out this costs one redundant reload per
    // tap — acceptable.
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let hotwireTabBarController = tabBarController as? HotwireTabBarController,
              TabBar.tabs.indices.contains(tabBarController.selectedIndex) else { return }
        let index = tabBarController.selectedIndex
        let navigator = hotwireTabBarController.activeNavigator
        let tabURL = TabBar.tabs[index].url
        let parked = navigator.activeWebView.url?.path
        let stale = dirtyTabs.contains(index) ||
            parked == "/session/new" ||
            (parked == TabBar.tabs[0].url.path && tabURL != TabBar.tabs[0].url)
        guard stale else { return }
        dirtyTabs.remove(index)
        // REPLACE, not push: the stale page must leave the stack — a push would put a
        // back arrow on the tab root pointing at it.
        navigator.route(tabURL, options: VisitOptions(action: .replace))
    }
}

extension SceneDelegate: NavigatorDelegate {
    // The VISIBLE tab arriving at the sign-in page means every OTHER tab's authenticated
    // snapshot is now stale (Sair, or a server-side session expiry) — mark them for a
    // fresh visit on next selection. Background navigators redirecting there during a
    // signed-out cold start are ignored: the parked-/session/new check already covers
    // them, and the user may be typing into the visible form.
    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        if proposal.url.path == "/session/new", navigator === tabBarController.activeNavigator {
            for index in TabBar.tabs.indices where index != tabBarController.selectedIndex {
                dirtyTabs.insert(index)
            }
        }
        return .accept
    }
}
