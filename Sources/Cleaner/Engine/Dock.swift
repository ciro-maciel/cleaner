import Foundation

/// Apps pinned to the Dock live in com.apple.dock "persistent-apps". An app that leaves the
/// disk stays there as a "?" until its tile is removed, so a full uninstall removes the tile
/// too, and a restore puts it back.
enum Dock {
    struct Entry: Hashable {
        let path: String          // /Applications/Foo.app
        let bundleID: String?
        var exists: Bool { FileManager.default.fileExists(atPath: path) }
        var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    }

    private static let domain = "com.apple.dock" as CFString
    private static let key = "persistent-apps" as CFString

    private static func tiles() -> [[String: Any]] {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? [[String: Any]]) ?? []
    }

    private static func path(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let file = data["file-data"] as? [String: Any],
              let url = file["_CFURLString"] as? String,
              let u = URL(string: url) else { return nil }
        return u.path.hasSuffix("/") ? String(u.path.dropLast()) : u.path
    }

    static func entries() -> [Entry] {
        tiles().compactMap { tile in
            guard let p = path(of: tile) else { return nil }
            let id = (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
            return Entry(path: p, bundleID: id)
        }
    }

    /// Removes the tiles of these app paths. Returns each removed tile as plist data, to be
    /// stored with the quarantine batch for a restore.
    static func remove(appPaths: Set<String>) -> [Data] {
        let all = tiles()
        var kept: [[String: Any]] = []
        var removed: [Data] = []
        for tile in all {
            if let p = path(of: tile), appPaths.contains(p) {
                if let data = try? PropertyListSerialization.data(fromPropertyList: tile, format: .binary, options: 0) {
                    removed.append(data)
                }
            } else {
                kept.append(tile)
            }
        }
        guard kept.count != all.count else { return [] }
        write(kept)
        return removed
    }

    /// Puts tiles back at the end of the Dock, skipping any whose app is not on disk again.
    static func restore(_ saved: [Data]) {
        let back = saved.compactMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            .filter { tile in path(of: tile).map { FileManager.default.fileExists(atPath: $0) } ?? false }
        guard !back.isEmpty else { return }
        let current = tiles()
        let present = Set(current.compactMap(path(of:)))
        write(current + back.filter { !present.contains(path(of: $0) ?? "") })
    }

    /// Writes the tile list and restarts the Dock. A Dock that is mid-launch (or quitting)
    /// can write its in-memory list back over ours, so the result is read back and written
    /// again until it holds.
    private static func write(_ list: [[String: Any]]) {
        let wanted = list.compactMap(path(of:))
        for _ in 0..<3 {
            CFPreferencesSetAppValue(key, list as CFArray, domain)
            CFPreferencesAppSynchronize(domain)
            Privileged.run("/usr/bin/killall", ["Dock"])
            Thread.sleep(forTimeInterval: 1.2)
            if tiles().compactMap(path(of:)) == wanted { return }
        }
    }
}

/// cfprefsd keeps preference domains in memory and writes them back to disk: moving a
/// .plist away is not enough, the cached domain must be dropped too.
enum Preferences {
    static func isPreferenceFile(_ path: String) -> Bool {
        path.contains("/Library/Preferences/") && path.hasSuffix(".plist") && !path.contains("/ByHost/")
    }

    static func forget(_ plistPath: String) {
        let domain = ((plistPath as NSString).lastPathComponent as NSString).deletingPathExtension
        guard !domain.isEmpty, !domain.hasPrefix("com.apple.") else { return }
        // The file is already in the quarantine; this only clears what cfprefsd still holds.
        Privileged.run("/usr/bin/defaults", ["delete", domain])
    }

    /// After a .plist comes back from the quarantine, cfprefsd must read it again.
    static func reload() {
        Privileged.run("/usr/bin/killall", ["-u", NSUserName(), "cfprefsd"])
    }
}

/// Apps Cleaner removed, kept after their quarantine batch is gone, so leftovers they leave
/// later (a recreated plist, a Dock tile) can still be found by bundle identifier.
enum UninstallHistory {
    struct Record: Codable, Hashable {
        let bundleID: String
        let name: String
        let path: String
        let date: Date
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cleaner/uninstalled.json")
    }

    static func all() -> [Record] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file), let list = try? decoder.decode([Record].self, from: data) else { return [] }
        return list
    }

    static func add(_ records: [Record]) {
        var list = all().filter { r in !records.contains { $0.bundleID == r.bundleID } }
        list.append(contentsOf: records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(list).write(to: file)
    }

    static func remove(bundleIDs: Set<String>) {
        let list = all().filter { !bundleIDs.contains($0.bundleID) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(list).write(to: file)
    }
}
