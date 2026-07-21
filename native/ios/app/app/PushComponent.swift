import HotwireNative
import UIKit
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

// The "push" bridge component (.plans/mobile/04 §3): the web's Avisos row sends
// "register" (may prompt for OS permission); the native layout sends "registerIfGranted"
// on launch (silent — token rotation must never strand a device). Replies carry the FCM
// token; the WEB posts it to /push_devices through its own session.
//
// ponytail: FirebaseMessaging is compiled in only once the founder adds the SPM package
// + GoogleService-Info.plist (a Firebase project is founder-provisioned). Until then the
// permission flow works but no token reply is sent — the web posts nothing.
final class PushComponent: BridgeComponent {
    override nonisolated class var name: String { "push" }

    override func onReceive(message: Message) {
        switch message.event {
        case "register":          register(message: message, interactive: true)
        case "registerIfGranted": register(message: message, interactive: false)
        default: break
        }
    }

    private func register(message: Message, interactive: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                guard interactive else { return }
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    guard granted else { return }
                    self.replyWithToken(message)
                }
            case .authorized, .provisional, .ephemeral:
                self.replyWithToken(message)
            default:
                break   // denied — the OS Settings app is the only way back
            }
        }
    }

    private func replyWithToken(_ message: Message) {
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        #if canImport(FirebaseMessaging)
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let data = #"{"token":"\#(token)","platform":"ios","appVersion":"\#(version)"}"#
            self.reply(to: message.event, with: data)
        }
        #endif
    }
}
