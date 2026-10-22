import Foundation

nonisolated enum WanderlustStaticDataCache {
    private static let schemaVersion = 1

    private struct Envelope<Payload: Codable>: Codable {
        let schemaVersion: Int
        let sourceSignature: String
        let createdAt: Date
        let payload: Payload
    }

    static func loadArray<Element: Codable>(
        cacheName: String,
        sourceURL: URL,
        as elementType: Element.Type
    ) -> [Element]? {
        do {
            let signature = try sourceSignature(for: sourceURL)
            let url = try cacheURL(cacheName: cacheName)
            let data = try Data(contentsOf: url)
            let envelope = try PropertyListDecoder().decode(Envelope<[Element]>.self, from: data)
            guard envelope.schemaVersion == schemaVersion,
                  envelope.sourceSignature == signature else {
                try? FileManager.default.removeItem(at: url)
                WanderlustDiagnostics.info("static_cache_stale name=\(cacheName)", category: .performance)
                return nil
            }

            WanderlustDiagnostics.info("static_cache_hit name=\(cacheName) count=\(envelope.payload.count)", category: .performance)
            return envelope.payload
        } catch {
            WanderlustDiagnostics.info("static_cache_miss name=\(cacheName)", category: .performance)
            return nil
        }
    }

    static func loadPayload<Payload: Codable>(
        cacheName: String,
        sourceURL: URL,
        as payloadType: Payload.Type
    ) -> Payload? {
        do {
            let signature = try sourceSignature(for: sourceURL)
            let url = try cacheURL(cacheName: cacheName)
            let data = try Data(contentsOf: url)
            let envelope = try PropertyListDecoder().decode(Envelope<Payload>.self, from: data)
            guard envelope.schemaVersion == schemaVersion,
                  envelope.sourceSignature == signature else {
                try? FileManager.default.removeItem(at: url)
                WanderlustDiagnostics.info("static_cache_stale name=\(cacheName)", category: .performance)
                return nil
            }

            WanderlustDiagnostics.info("static_cache_hit name=\(cacheName)", category: .performance)
            return envelope.payload
        } catch {
            WanderlustDiagnostics.info("static_cache_miss name=\(cacheName)", category: .performance)
            return nil
        }
    }

    static func saveArray<Element: Codable>(
        _ payload: [Element],
        cacheName: String,
        sourceURL: URL
    ) {
        do {
            let signature = try sourceSignature(for: sourceURL)
            let envelope = Envelope(
                schemaVersion: schemaVersion,
                sourceSignature: signature,
                createdAt: Date(),
                payload: payload
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(envelope)
            let url = try cacheURL(cacheName: cacheName)
            try data.write(to: url, options: [.atomic])
            WanderlustDiagnostics.info("static_cache_write name=\(cacheName) bytes=\(data.count)", category: .performance)
        } catch {
            WanderlustDiagnostics.error(error, category: .performance, message: "static_cache_write_failed name=\(cacheName)")
        }
    }

    static func savePayload<Payload: Codable>(
        _ payload: Payload,
        cacheName: String,
        sourceURL: URL
    ) {
        do {
            let signature = try sourceSignature(for: sourceURL)
            let envelope = Envelope(
                schemaVersion: schemaVersion,
                sourceSignature: signature,
                createdAt: Date(),
                payload: payload
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(envelope)
            let url = try cacheURL(cacheName: cacheName)
            try data.write(to: url, options: [.atomic])
            WanderlustDiagnostics.info("static_cache_write name=\(cacheName) bytes=\(data.count)", category: .performance)
        } catch {
            WanderlustDiagnostics.error(
                error,
                category: .performance,
                message: "static_cache_write_failed name=\(cacheName)"
            )
        }
    }

    private static func cacheURL(cacheName: String) throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("StaticDataCache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("\(cacheName).plist")
    }

    private static func sourceSignature(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .nameKey])
        let size = values.fileSize ?? 0
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let name = values.name ?? url.lastPathComponent
        return "schema=\(schemaVersion)|name=\(name)|size=\(size)|modified=\(modified)"
    }
}
