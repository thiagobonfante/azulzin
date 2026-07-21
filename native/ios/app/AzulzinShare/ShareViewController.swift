import Social
import UIKit
import UniformTypeIdentifiers

// Share intake (.plans/mobile/05 §3): accept ONE image or PDF, stash it (+ optional
// caption sidecar) into the App Group inbox — the main app drains it to /captures on
// next foreground. No network, no auth here: the extension process has no webview
// cookies, and the inbox pattern keeps it that way.
class ShareViewController: SLComposeServiceViewController {
    private static let types: [UTType] = [.image, .pdf]

    private var provider: NSItemProvider? {
        (extensionContext?.inputItems.first as? NSExtensionItem)?.attachments?
            .first { p in Self.types.contains { p.hasItemConformingToTypeIdentifier($0.identifier) } }
    }

    override func isContentValid() -> Bool { provider != nil }

    override func didSelectPost() {
        guard let provider,
              let type = Self.types.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return extensionContext!.completeRequest(returningItems: [])
        }
        let caption = contentText
        // The temp URL is only valid inside the callback — copy before completing.
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, _ in
            if let url { Self.stash(url, caption: caption) }
            DispatchQueue.main.async { self?.extensionContext!.completeRequest(returningItems: []) }
        }
    }

    private static func stash(_ url: URL, caption: String?) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.br.com.azulzin") else { return }
        let inbox = container.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let name = UUID().uuidString
        // The server identifies content type from the filename EXTENSION — keep it real.
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        do {
            let dest = inbox.appendingPathComponent("\(name).\(ext)")
            try FileManager.default.copyItem(at: url, to: dest)
            // copyItem preserves the SOURCE's dates (a photo file can be years old) —
            // stamp stash time explicitly or the drain's stale sweep discards it.
            try? FileManager.default.setAttributes([.creationDate: Date()], ofItemAtPath: dest.path)
            if let caption, !caption.isEmpty {
                try? caption.write(to: inbox.appendingPathComponent("\(name).caption"),
                                   atomically: true, encoding: .utf8)
            }
        } catch {}
    }

    override func configurationItems() -> [Any]! { [] }
}
