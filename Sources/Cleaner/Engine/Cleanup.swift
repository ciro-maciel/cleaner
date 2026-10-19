import Foundation
import AppKit

/// The public cleanup rules (rules.json). Allowlist: nothing outside them is ever proposed.
struct CleanupRule: Codable, Identifiable, Hashable {
    enum Mode: String, Codable { case children, files, `self` }
    enum Risk: String, Codable { case low, medium }

    let id: String
    let title: String
    let why: String
    /// English title and reason; title and why are the Portuguese originals.
    var titleEn: String? = nil
    var whyEn: String? = nil
    let risk: Risk
    let mode: Mode
    let paths: [String]
    var exclude: [String]? = nil
    var extensions: [String]? = nil
    var minAgeDays: Int? = nil
    var skipRunningApps: Bool? = nil
    var defaultOn: Bool

    static func loadAll() -> [CleanupRule] {
        let candidates = [
            Bundle.main.url(forResource: "rules", withExtension: "json"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("rules.json"),
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(File.self, from: data) { return file.rules }
        }
        return []
    }

    private struct File: Codable { let rules: [CleanupRule] }

    /// The title and the reason in the interface language. A rule without English shows its
    /// Portuguese.
    var displayTitle: String { L10n.isPortuguese ? title : (titleEn ?? title) }
    var displayWhy: String { L10n.isPortuguese ? why : (whyEn ?? why) }
}

struct CleanupItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let ruleID: String
    /// Why this one starts unselected (an open app, for instance).
    var hold: String? = nil
    var name: String { (path as NSString).lastPathComponent }
}

struct CleanupGroup: Identifiable, Hashable {
    var id: String { rule.id }
    let rule: CleanupRule
    var items: [CleanupItem]
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

enum CleanupScanner {
    /// Bundle identifiers of the apps open right now; their caches are left alone by default.
    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    static func scan(rules: [CleanupRule], running: Set<String>) async -> [CleanupGroup] {
        await withTaskGroup(of: CleanupGroup?.self) { group in
            for rule in rules { group.addTask { scan(rule, running: running) } }
            var out: [CleanupGroup] = []
            for await g in group { if let g, !g.items.isEmpty { out.append(g) } }
            // Keep rules.json order: it reads from safest to most specific.
            return out.sorted { a, b in
                (rules.firstIndex(of: a.rule) ?? 0) < (rules.firstIndex(of: b.rule) ?? 0)
            }
        }
    }

    static func scan(_ rule: CleanupRule, running: Set<String>) -> CleanupGroup? {
        let fm = FileManager.default
        var items: [CleanupItem] = []
        let cutoff = rule.minAgeDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }

        for raw in rule.paths {
            let base = expand(raw)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: base, isDirectory: &isDir) else { continue }

            switch rule.mode {
            case .self:
                let size = DiskUsage.size(of: base)
                if size > 0 { items.append(CleanupItem(path: base, size: size, ruleID: rule.id)) }

            case .children, .files:
                guard isDir.boolValue, let names = try? fm.contentsOfDirectory(atPath: base) else { continue }
                for name in names {
                    if matches(name, rule.exclude ?? []) { continue }
                    let path = (base as NSString).appendingPathComponent(name)
                    if rule.mode == .files {
                        let ext = (name as NSString).pathExtension.lowercased()
                        guard let exts = rule.extensions, exts.contains(ext) else { continue }
                    }
                    if let cutoff, let date = modified(path), date > cutoff { continue }
                    let size = DiskUsage.size(of: path)
                    guard size > 0 else { continue }
                    var item = CleanupItem(path: path, size: size, ruleID: rule.id)
                    if rule.skipRunningApps == true, running.contains(where: { name == $0 || name.hasPrefix($0 + ".") }) {
                        item.hold = L("app open")
                    }
                    items.append(item)
                }
            }
        }
        items.sort { $0.size > $1.size }
        return CleanupGroup(rule: rule, items: items)
    }

    static func matches(_ name: String, _ patterns: [String]) -> Bool {
        patterns.contains { fnmatch($0, name, 0) == 0 }
    }

    static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
