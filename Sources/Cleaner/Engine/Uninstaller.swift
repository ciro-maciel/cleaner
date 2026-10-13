import Foundation

/// The whole uninstall, in order. Files are only half of it: an app also leaves processes
/// running from its bundle (extensions, helpers), launchd jobs loaded in memory, its
/// LaunchServices registration (extensions, "Open With") and a Dock tile.
enum Uninstaller {
    struct Report {
        var batch: Quarantine.Batch?
        var failures: [(path: String, message: String)] = []
        var stayed: [String] = []           // asked to leave but still on disk
        var needsFullDiskAccess: [String] = []  // stayed because Full Disk Access is off
        var stoppedProcesses = 0
        var unloadedJobs = 0
        var dockTiles = 0
    }

    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// `apps` are app bundles to remove (may be empty when only leftovers of a gone app are
    /// cleaned); `files` are the leftovers chosen; `dockPaths` the Dock tiles to drop.
    static func run(apps: [String], files: [(path: String, size: Int64)], dockPaths: Set<String>,
                    quarantine: Quarantine, reason: String) -> Report {
        var report = Report()

        // 1. Processes running from inside the bundles: Finder Sync, widgets, helpers.
        for app in apps { report.stoppedProcesses += stopProcesses(inside: app) }

        // 2. launchd jobs whose plist is leaving: stop them now, not at the next restart.
        var prelude: [String] = []
        for file in files.map(\.path) where file.hasSuffix(".plist") && file.contains("/Launch") {
            guard let label = (NSDictionary(contentsOfFile: file) as? [String: Any])?["Label"] as? String else { continue }
            if file.hasPrefix(NSHomeDirectory()) {
                if Privileged.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"]).status == 0 { report.unloadedJobs += 1 }
            } else {
                // System jobs: inside the same password prompt as the move.
                prelude.append("/bin/launchctl bootout system/\(Privileged.quoted(label))")
                report.unloadedJobs += 1
            }
        }

        // 3. LaunchServices forgets the app: its extensions and "Open With" entries go with it.
        for app in apps { Privileged.run(lsregister, ["-u", app]) }

        // 4. Everything into one quarantine batch (cfprefsd is flushed for moved plists there).
        let entries = apps.map { ($0, DiskUsage.size(of: $0)) } + files
        if !entries.isEmpty {
            let result = quarantine.move(entries, reason: reason, adminPrelude: prelude)
            report.batch = result.batch
            report.failures = result.failures
            report.needsFullDiskAccess = result.needsFullDiskAccess
        }

        // 5. The Dock: tiles of the removed apps and the ones asked for.
        let movedApps = Set(report.batch?.items.map(\.original).filter { apps.contains($0) } ?? [])
        let tiles = Dock.remove(appPaths: movedApps.union(dockPaths))
        report.dockTiles = tiles.count
        if let id = report.batch?.id { quarantine.attachDockTiles(tiles, to: id) }

        // An app that did not move gets its registration back.
        for app in apps where !movedApps.contains(app) { Privileged.run(lsregister, ["-f", app]) }

        // 6. What is still there.
        report.stayed = entries.map(\.0).filter { FileManager.default.fileExists(atPath: $0) }
        return report
    }

    /// Terminates this user's processes whose executable lives inside `bundle`. Returns how
    /// many stopped. Root-owned ones are left (they stop with their launchd job).
    static func stopProcesses(inside bundle: String) -> Int {
        let prefix = bundle.hasSuffix("/") ? bundle : bundle + "/"
        func pids() -> [pid_t] {
            Privileged.run("/bin/ps", ["-xo", "pid=,comm="]).output.split(separator: "\n").compactMap { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard let space = t.firstIndex(of: " "), let pid = pid_t(t[..<space]) else { return nil }
                let path = t[space...].trimmingCharacters(in: .whitespaces)
                return path.hasPrefix(prefix) && pid != getpid() ? pid : nil
            }
        }
        let first = pids()
        guard !first.isEmpty else { return 0 }
        first.forEach { kill($0, SIGTERM) }
        for _ in 0..<20 where !pids().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
        pids().forEach { kill($0, SIGKILL) }
        return first.count
    }
}
