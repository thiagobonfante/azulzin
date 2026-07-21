import AuthenticationServices
import HotwireNative
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// The "sign-in" bridge component (.plans/mobile/10): the auth screens' hidden SSO
// buttons reveal when this registers; a tap sends "signIn" {provider} and the reply
// carries the platform ID token — the WEB posts it to /auth/:provider/token, so the
// session cookie lands in the webview. No reply on cancel/failure: the page stays put.
//
// ponytail: GoogleSignIn compiles in only once the founder adds the SPM package
// (https://github.com/google/GoogleSignIn-iOS), sets Config.googleClientID, and adds
// the reversed-client-ID URL type (Target ▸ Info ▸ URL Types). Until then the Google
// tap replies nothing; Apple works out of the box (AuthenticationServices + the
// applesignin entitlement).
final class SignInComponent: BridgeComponent {
    override nonisolated class var name: String { "sign-in" }

    private var appleFlow: AppleFlow?   // retains the delegate while the sheet is up

    private struct SignInMessage: Decodable { let provider: String }

    override func onReceive(message: Message) {
        guard message.event == "signIn", let data: SignInMessage = message.data() else { return }
        switch data.provider {
        case "google_oauth2": signInWithGoogle(message: message)
        case "apple":         signInWithApple(message: message)
        default: break
        }
    }

    private var presenter: UIViewController? {
        delegate?.destination as? UIViewController
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
    }

    private func replyToken(_ message: Message, idToken: String) {
        reply(to: message.event, with: #"{"idToken":"\#(idToken)"}"#)
    }

    // MARK: - Google

    private func signInWithGoogle(message: Message) {
        #if canImport(GoogleSignIn)
        guard !Config.googleClientID.isEmpty, let presenter else { return }
        if GIDSignIn.sharedInstance.configuration == nil {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Config.googleClientID)
        }
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { [weak self] result, _ in
            guard let idToken = result?.user.idToken?.tokenString else { return }   // nil = cancelled
            DispatchQueue.main.async { self?.replyToken(message, idToken: idToken) }
        }
        #endif
    }

    // MARK: - Apple

    private func signInWithApple(message: Message) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        let flow = AppleFlow(anchor: presenter?.view.window) { [weak self] idToken in
            DispatchQueue.main.async {
                self?.appleFlow = nil
                guard let self, let idToken else { return }
                self.replyToken(message, idToken: idToken)
            }
        }
        appleFlow = flow
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = flow
        controller.presentationContextProvider = flow
        controller.performRequests()
    }

    private final class AppleFlow: NSObject, ASAuthorizationControllerDelegate,
                                   ASAuthorizationControllerPresentationContextProviding {
        private let anchor: UIWindow?
        private let completion: (String?) -> Void

        init(anchor: UIWindow?, completion: @escaping (String?) -> Void) {
            self.anchor = anchor
            self.completion = completion
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithAuthorization authorization: ASAuthorization) {
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            completion(credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) })
        }

        func authorizationController(controller: ASAuthorizationController,
                                     didCompleteWithError error: Error) {
            completion(nil)   // cancelled/failed — the page stays on the sign-in form
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            anchor
                ?? UIApplication.shared.connectedScenes
                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
                ?? ASPresentationAnchor()
        }
    }
}
