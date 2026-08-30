import AppKit
import UniformTypeIdentifiers

enum DroppedFileURLCollector {
    @MainActor
    static func collect(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        let candidates = [
            UTType.fileURL.identifier,
            "public.file-url",
            UTType.url.identifier,
        ]
        for provider in providers {
            outer: for typeId in candidates where provider.hasItemConformingToTypeIdentifier(typeId) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: typeId)
                    if let url = item as? URL {
                        if url.isFileURL { urls.append(url) }
                        break outer
                    }
                    if let nsurl = item as? NSURL {
                        let u = nsurl as URL
                        if u.isFileURL { urls.append(u) }
                        break outer
                    }
                    if let data = item as? Data {
                        var stale = false
                        if let bookmark = try? URL(
                            resolvingBookmarkData: data,
                            options: [.withSecurityScope, .withoutUI],
                            relativeTo: nil,
                            bookmarkDataIsStale: &stale
                        ), bookmark.isFileURL {
                            urls.append(bookmark)
                            break outer
                        }
                        if let s = String(data: data, encoding: .utf8) {
                            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                            if let fileUrl = URL(string: trimmed), fileUrl.isFileURL {
                                urls.append(fileUrl)
                                break outer
                            }
                            let path = (trimmed as NSString).expandingTildeInPath
                            if !path.isEmpty {
                                urls.append(URL(fileURLWithPath: path))
                                break outer
                            }
                        }
                    }
                    if let str = item as? String {
                        if let fileUrl = URL(string: str), fileUrl.isFileURL {
                            urls.append(fileUrl)
                        } else {
                            urls.append(URL(fileURLWithPath: (str as NSString).expandingTildeInPath))
                        }
                        break outer
                    }
                } catch {
                    continue
                }
            }
        }
        return urls
    }
}
