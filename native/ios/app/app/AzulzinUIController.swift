import HotwireNative
import WebKit

// Chat audio capture (.plans/mobile/08 §4): the composer's getUserMedia would make
// WKWebView show its own per-site mic prompt on top of the OS-level one. Granting here
// skips the duplicate — iOS still enforces NSMicrophoneUsageDescription the first time.
final class AzulzinUIController: WKUIController {
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // Mic only, and only for our own pages — anything else keeps the default prompt.
        let ours = origin.host == Config.baseURL.host
        decisionHandler(ours && type == .microphone ? .grant : .prompt)
    }
}
