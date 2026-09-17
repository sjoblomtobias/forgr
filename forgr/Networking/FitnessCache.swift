import Foundation

/// Best-effort on-disk cache of the last successfully loaded data, so cold launches
/// can render real content immediately instead of waiting on the network.
/// Explicitly `nonisolated` so disk I/O can run off the main actor.
nonisolated enum FitnessCache {
    private static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forgr-snapshot.json")
    }

    static func load() -> FitnessSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(FitnessSnapshot.self, from: data)
    }

    static func save(_ snapshot: FitnessSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
