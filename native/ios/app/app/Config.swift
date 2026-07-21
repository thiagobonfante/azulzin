import Foundation

// Base URL per build configuration (.plans/mobile/02 §1). Debug talks to the local
// Rails server (ATS local-networking exception lives in the Debug Info.plist only).
enum Config {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:3000")!
    #else
    static let baseURL = URL(string: "https://app.azulzin.com.br")!
    #endif

    static let pathConfigurationRemoteURL = baseURL.appendingPathComponent("configurations/ios_v1.json")

    // Native Google SSO (.plans/mobile/10): the iOS OAuth client id from the founder's
    // Google Cloud console. Empty = Google sign-in stays dormant (Apple still works).
    static let googleClientID = "648002270527-p5ia5bhvviooa0ne51rl7vocbma0oplu.apps.googleusercontent.com"
}
