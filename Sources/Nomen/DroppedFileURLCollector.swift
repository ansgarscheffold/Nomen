import AppKit
import UniformTypeIdentifiers
import NomenCore

enum DroppedFileURLCollector {
    @MainActor
    static func collect(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        let candidates = [
            UTType.fileURL.identifier,
            "public.file-url",
        ]
        for provider in providers {
            outer: for typeId in candidates where provider.hasItemConformingToTypeIdentifier(typeId) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: typeId)
                    if let url = item as? URL, let accepted = DroppedFileURLFilter.accept(url) {
                        urls.append(accepted)
                        break outer
                    }
                    if let nsurl = item as? NSURL, let accepted = DroppedFileURLFilter.accept(nsurl as URL) {
                        urls.append(accepted)
                        break outer
                    }
                    if let data = item as? Data {
                        var stale = false
                        if let bookmark = try? URL(
                            resolvingBookmarkData: data,
                            options: [.withSecurityScope, .withoutUI],
                            relativeTo: nil,
                            bookmarkDataIsStale: &stale
                        ), let accepted = DroppedFileURLFilter.accept(bookmark) {
                            urls.append(accepted)
                            break outer
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        return urls
    }
}
