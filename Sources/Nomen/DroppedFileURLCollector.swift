import AppKit
import UniformTypeIdentifiers
import NomenCore

enum DroppedFileURLCollector {
    @MainActor
    static func collect(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadFileURL(from: provider) {
                urls.append(url)
            }
        }
        return urls
    }

    @MainActor
    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self),
           let url = await loadObjectURL(provider),
           let accepted = DroppedFileURLFilter.accept(url) {
            return accepted
        }

        let candidates = [
            UTType.fileURL.identifier,
            "public.file-url",
            UTType.url.identifier,
        ]
        for typeId in candidates where provider.hasItemConformingToTypeIdentifier(typeId) {
            do {
                let item = try await provider.loadItem(forTypeIdentifier: typeId)
                if let url = decodeDroppedItem(item) {
                    return url
                }
            } catch {
                continue
            }
        }
        return nil
    }

    @MainActor
    private static func loadObjectURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func decodeDroppedItem(_ item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return DroppedFileURLFilter.accept(url)
        }
        if let nsurl = item as? NSURL {
            return DroppedFileURLFilter.accept(nsurl as URL)
        }
        if let data = item as? Data {
            return DroppedFileURLFilter.acceptPasteboardData(data)
        }
        if let str = item as? String {
            return DroppedFileURLFilter.acceptFileURLString(str)
        }
        return nil
    }
}
