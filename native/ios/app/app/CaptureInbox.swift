import Foundation
import WebKit

// Drains the share-extension inbox (.plans/mobile/05 §3): each stashed file POSTs to
// /captures with the webview's session cookie + the X-Azulzin-Capture header the
// controller requires. Delete on success; keep for the next foreground otherwise —
// a share stashed while signed out uploads after sign-in (deliberate improvement on
// Android's v1 drop). Files older than 7 days are discarded, not uploaded.
enum CaptureInbox {
    private static var draining = false
    private static let maxAge: TimeInterval = 7 * 24 * 3600

    static func drain() {
        guard !draining,
              let container = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: "group.br.com.azulzin") else { return }
        let inbox = container.appendingPathComponent("inbox", isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: inbox, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension != "caption" }
        guard !files.isEmpty else { return }
        draining = true
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let host = Config.baseURL.host ?? ""
            let ours = cookies.filter { host.hasSuffix($0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
            let header = ours.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            guard header.contains("session_id=") else { draining = false; return }
            Task {
                for file in files { await upload(file, cookie: header) }
                draining = false
            }
        }
    }

    private static func upload(_ file: URL, cookie: String) async {
        if let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
           Date().timeIntervalSince(created) > maxAge { return remove(file) }
        guard let data = try? Data(contentsOf: file) else { return remove(file) }
        let ext = file.pathExtension
        let mime = ["pdf": "application/pdf", "png": "image/png"][ext] ?? "image/jpeg"
        let caption = try? String(contentsOf: file.deletingPathExtension().appendingPathExtension("caption"),
                                  encoding: .utf8)
        let boundary = "azulzin-\(UUID().uuidString)"
        var req = URLRequest(url: Config.baseURL.appendingPathComponent("captures"))
        req.httpMethod = "POST"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("1", forHTTPHeaderField: "X-Azulzin-Capture")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"share.\(ext)\"\r\nContent-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n")
        if let caption, !caption.isEmpty {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n\(caption)\r\n")
        }
        append("--\(boundary)--\r\n")
        req.httpBody = body
        // URLSession follows the success redirect; a stale session's redirect lands on
        // /session/new — that must NOT count as delivered.
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<400).contains(code),
              resp.url?.path.hasPrefix("/session") != true else { return }
        remove(file)
    }

    private static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: file.deletingPathExtension().appendingPathExtension("caption"))
    }
}
