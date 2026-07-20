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
}
