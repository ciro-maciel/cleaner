import Foundation

/// Nothing Cleaner removes disappears at once: it moves here, with a manifest of where it came
/// from, and stays 7 days. Restoring moves it back. After 7 days the batch is deleted for good.
final class Quarantine: @unchecked Sendable {
    static let keepDays = 7

    struct Item: Codable, Identifiable, Hashable {
        var id: String { stored }
        let original: String
        let stored: String
        let size: Int64
        var restored: Bool = false
    }

    struct Batch: Codable, Identifiable, Hashable {
        let id: String
        let reason: String
        let createdAt: Date
        var items: [Item]
        /// Dock tiles removed with the apps of this batch, put back on restore.
        var dockTiles: [Data]? = nil
        var expiresAt: Date { createdAt.addingTimeInterval(TimeInterval(Quarantine.keepDays * 86_400)) }
        var size: Int64 { items.filter { !$0.restored }.reduce(0) { $0 + $1.size } }
        var activeItems: [Item] { items.filter { !$0.restored } }
    }

    struct MoveResult {
        var batch: Batch?
        var failures: [(path: String, message: String)] = []
        /// Left in place because macOS guards them behind Full Disk Access, which no password
        /// replaces: the app has to say so and point to the switch (15-app-mac.md).
        var needsFullDiskAccess: [String] = []
    }

    static let fullDiskAccessMessage = L("Full Disk Access is off for Cleaner")

    let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        if root == nil { Quarantine.migrateFromBroom() }
        self.root = root ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cleaner/Quarantine", isDirectory: true)
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    /// The app was called Broom until 10/10/2026. Its folder (quarantine + uninstall history)
    /// moves to Cleaner's, and every manifest's stored paths follow, so restores keep working.
    static func migrateFromBroom() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Broom"), new = support.appendingPathComponent("Cleaner")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        do { try fm.moveItem(at: old, to: new) } catch { return }
        let oldPrefix = old.path + "/", newPrefix = new.path + "/"
        let dirs = (try? fm.contentsOfDirectory(at: new.appendingPathComponent("Quarantine"), includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            let manifest = dir.appendingPathComponent("manifest.json")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
            // JSON escapes "/" as "\/" in some encoders; handle both spellings.
            let fixed = text.replacingOccurrences(of: oldPrefix, with: newPrefix)
                .replacingOccurrences(of: oldPrefix.replacingOccurrences(of: "/", with: "\\/"),
                                      with: newPrefix.replacingOccurrences(of: "/", with: "\\/"))
            try? fixed.write(to: manifest, atomically: true, encoding: .utf8)
        }
    }

    // MARK: reading

    func batches() -> [Batch] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { load($0) }
            .filter { !$0.activeItems.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func load(_ dir: URL) -> Batch? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Batch.self, from: data)
    }

    private func save(_ batch: Batch) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(batch).write(to: root.appendingPathComponent(batch.id).appendingPathComponent("manifest.json"))
    }

    // MARK: moving in

    /// Moves `paths` into a new batch. Items the user cannot move (owned by root) go through
    /// the administrator password once, all together.
    /// `adminPrelude` runs inside the same password prompt, before the moves (stopping a
    /// system launchd job whose plist is about to leave, for instance).
    func move(_ entries: [(path: String, size: Int64)], reason: String, adminPrelude: [String] = []) -> MoveResult {
        var result = MoveResult()
        guard !entries.isEmpty else { return result }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let id = "\(stamp)-\(UUID().uuidString.prefix(8))"
        let dir = root.appendingPathComponent(id, isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            result.failures = entries.map { ($0.path, error.localizedDescription) }
            return result
        }

        var batch = Batch(id: id, reason: reason, createdAt: Date(), items: [])
        var needAdmin: [(String, String, Int64)] = []
        for (index, entry) in entries.enumerated() {
            let name = (entry.path as NSString).lastPathComponent
            let stored = dir.appendingPathComponent("\(index)-\(name)").path
            do {
                try fm.moveItem(atPath: entry.path, toPath: stored)
                batch.items.append(Item(original: entry.path, stored: stored, size: entry.size))
            } catch let error as NSError where Self.isPrivacyBlock(error) {
                // EPERM: privacy protection (Trash, Mail, app containers) or SIP. A password
                // would not help, so it is never asked for this.
                if Permissions.hasFullDiskAccess {
                    result.failures.append((entry.path, L("macOS protects this item")))
                } else {
                    result.needsFullDiskAccess.append(entry.path)
                    result.failures.append((entry.path, Self.fullDiskAccessMessage))
                }
            } catch let error as NSError where Self.isPermission(error) {
                needAdmin.append((entry.path, stored, entry.size))
            } catch {
                result.failures.append((entry.path, error.localizedDescription))
            }
        }

        if !needAdmin.isEmpty {
            let user = NSUserName()
            let command = (adminPrelude.map { "(\($0)) || true" } + needAdmin.map { "/bin/mv \(Privileged.quoted($0.0)) \(Privileged.quoted($0.1)) && /usr/sbin/chown -R \(Privileged.quoted(user)) \(Privileged.quoted($0.1))" }).joined(separator: " && ")
            do {
                try Privileged.asAdmin(command, prompt: Self.adminPrompt(restoring: false, needAdmin.map(\.0)))
                for (path, stored, size) in needAdmin { batch.items.append(Item(original: path, stored: stored, size: size)) }
            } catch {
                // Some may have moved before the failure: keep what landed.
                for (path, stored, size) in needAdmin {
                    if fm.fileExists(atPath: stored) { batch.items.append(Item(original: path, stored: stored, size: size)) }
                    else { result.failures.append((path, error.localizedDescription)) }
                }
            }
        }

        if batch.items.isEmpty {
            try? fm.removeItem(at: dir)
            return result
        }
        // A moved .plist would be written back by cfprefsd from memory.
        for item in batch.items where Preferences.isPreferenceFile(item.original) { Preferences.forget(item.original) }
        do { try save(batch) } catch { result.failures.append((dir.path, error.localizedDescription)) }
        result.batch = batch
        return result
    }

    /// What the password prompt says: the action, how many items and the first of them, so
    /// the person knows what the password is for.
    static func adminPrompt(restoring: Bool, _ paths: [String]) -> String {
        let first = (paths.first ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if paths.count == 1 {
            return restoring
                ? L("Cleaner needs the administrator password to put 1 system item (%@) back where it was. It lives outside your home folder and belongs to the system.", first)
                : L("Cleaner needs the administrator password to move 1 system item (%@) to the quarantine. It lives outside your home folder and belongs to the system.", first)
        }
        let n = Format.count(paths.count)
        return restoring
            ? L("Cleaner needs the administrator password to put %1$@ system items, such as %2$@, back where they were. They live outside your home folder and belong to the system.", n, first)
            : L("Cleaner needs the administrator password to move %1$@ system items, such as %2$@, to the quarantine. They live outside your home folder and belong to the system.", n, first)
    }

    /// EPERM: privacy protection or SIP. Not solved by the administrator password.
    private static func isPrivacyBlock(_ error: NSError) -> Bool {
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EPERM)
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM)
    }

    /// EACCES and friends: the file belongs to another user (root). The password solves it.
    private static func isPermission(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return underlying.code == Int(EACCES) || underlying.code == Int(EPERM)
        }
        return false
    }

    func attachDockTiles(_ tiles: [Data], to batchID: String) {
        guard !tiles.isEmpty, var batch = load(root.appendingPathComponent(batchID)) else { return }
        batch.dockTiles = tiles
        try? save(batch)
    }

    // MARK: restoring

    /// Puts items back where they were. If something now sits at the original path, the item
    /// comes back next to it with " (restored)" (" (restaurado)" in Portuguese) in the name.
    func restore(batchID: String, items only: Set<String>? = nil) throws -> Int {
        let dir = root.appendingPathComponent(batchID)
        guard var batch = load(dir) else { return 0 }
        var restored = 0
        var errors: [String] = []
        var needAdmin: [(Int, String, String)] = []   // index, stored, target
        for i in batch.items.indices where !batch.items[i].restored {
            let item = batch.items[i]
            if let only, !only.contains(item.stored) { continue }
            var target = item.original
            if fm.fileExists(atPath: target) {
                let ns = target as NSString
                let ext = ns.pathExtension
                let base = ext.isEmpty ? target : ns.deletingPathExtension
                target = base + L(" (restored)") + (ext.isEmpty ? "" : "." + ext)
            }
            try? fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            do {
                try fm.moveItem(atPath: item.stored, toPath: target)
                batch.items[i].restored = true
                restored += 1
            } catch let error as NSError where Self.isPrivacyBlock(error) {
                errors.append(Permissions.hasFullDiskAccess ? L("macOS protects %@", (target as NSString).lastPathComponent) : Self.fullDiskAccessMessage)
            } catch let error as NSError where Self.isPermission(error) {
                needAdmin.append((i, item.stored, target))
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        // Every system item of the batch under one password prompt, not one per item.
        if !needAdmin.isEmpty {
            let command = needAdmin.map { "/bin/mv \(Privileged.quoted($0.1)) \(Privileged.quoted($0.2))" }.joined(separator: " && ")
            do {
                try Privileged.asAdmin(command, prompt: Self.adminPrompt(restoring: true, needAdmin.map(\.2)))
            } catch { errors.append(error.localizedDescription) }
            for (i, _, target) in needAdmin where fm.fileExists(atPath: target) {
                batch.items[i].restored = true
                restored += 1
            }
        }
        let back = batch.items.filter { $0.restored }
        if back.contains(where: { Preferences.isPreferenceFile($0.original) }) { Preferences.reload() }
        for item in back where item.original.hasSuffix(".app") && fm.fileExists(atPath: item.original) {
            Privileged.run(Uninstaller.lsregister, ["-f", item.original])
        }
        if let tiles = batch.dockTiles, back.contains(where: { $0.original.hasSuffix(".app") }) { Dock.restore(tiles) }
        if batch.activeItems.isEmpty { try? fm.removeItem(at: dir) } else { try? save(batch) }
        if let first = errors.first, restored == 0 { throw Privileged.Failure(message: first) }
        return restored
    }

    // MARK: deleting for good

    /// Batches being deleted live here: a rename into it is instant (same volume), so a batch
    /// leaves the list at once and the slow part, deleting millions of files, runs in the
    /// background. Whatever is still here at launch is finished then.
    var purging: URL { root.deletingLastPathComponent().appendingPathComponent("Purging", isDirectory: true) }

    /// Moves a batch out of the quarantine into Purging. Fast; safe on the main thread.
    @discardableResult
    func stage(batchID: String) -> Bool {
        try? fm.createDirectory(at: purging, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent(batchID)
        let target = purging.appendingPathComponent(batchID + "-" + UUID().uuidString.prefix(6))
        return (try? fm.moveItem(at: dir, to: target)) != nil
    }

    /// Deletes everything staged. Slow on big batches: call it off the main thread.
    func finishPurges() {
        let staged = (try? fm.contentsOfDirectory(at: purging, includingPropertiesForKeys: nil)) ?? []
        for dir in staged {
            // rm walks big trees faster than FileManager and never blocks the app.
            if Privileged.run("/bin/rm", ["-rf", dir.path]).status != 0, fm.fileExists(atPath: dir.path) {
                // Files the user cannot delete (should not happen: moved items are chowned).
                try? Privileged.asAdmin("/bin/rm -rf \(Privileged.quoted(dir.path))", prompt: L("Cleaner needs the administrator password to permanently delete a quarantine batch with system items."))
            }
        }
    }

    /// Still being deleted, for the screen to show.
    func purgingBytes() -> Int64 {
        let staged = (try? fm.contentsOfDirectory(at: purging, includingPropertiesForKeys: nil)) ?? []
        return staged.compactMap { load($0)?.size }.reduce(0, +)
    }

    /// Stages batches older than 7 days. Runs at launch; the deleting happens in the background.
    @discardableResult
    func stageExpired(now: Date = Date()) -> Int {
        var count = 0
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for dir in dirs {
            guard let batch = load(dir) else { continue }
            if batch.expiresAt < now || batch.activeItems.isEmpty { if stage(batchID: batch.id) { count += 1 } }
        }
        return count
    }

    /// Synchronous: stage, then delete. For the self-test.
    @discardableResult
    func purgeExpired(now: Date = Date()) -> Int {
        let n = stageExpired(now: now)
        finishPurges()
        return n
    }

    @discardableResult
    func purge(batchID: String) -> Bool {
        guard stage(batchID: batchID) else { return false }
        finishPurges()
        return true
    }

}
