import HotwireNative
import UIKit

// The five tabs (.plans/mobile/01 §3 / 07 #7). Titles come from Localizable.xcstrings.
enum TabBar {
    static let tabs: [HotwireTab] = [
        HotwireTab(title: String(localized: "tab.inicio"),
                   image: UIImage(systemName: "house")!,
                   url: Config.baseURL.appendingPathComponent("dashboard")),
        HotwireTab(title: String(localized: "tab.chat"),
                   image: UIImage(systemName: "message")!,
                   url: Config.baseURL.appendingPathComponent("chat")),
        HotwireTab(title: String(localized: "tab.movimentos"),
                   image: UIImage(systemName: "list.bullet.rectangle")!,
                   url: Config.baseURL.appendingPathComponent("transactions")),
        HotwireTab(title: String(localized: "tab.metas"),
                   image: UIImage(systemName: "target")!,
                   url: Config.baseURL.appendingPathComponent("goals")),
        HotwireTab(title: String(localized: "tab.mais"),
                   image: UIImage(systemName: "ellipsis")!,
                   url: Config.baseURL.appendingPathComponent("menu"))
    ]
}
