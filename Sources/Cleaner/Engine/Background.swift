import Foundation
import AppKit

/// Third-party apps running with no window and no Dock icon: updaters, menu bar agents,
/// helpers left behind by apps that are closed. Processes are grouped by the app bundle
/// they run from; an app counts as background when none of its processes is a Dock app.
struct BackgroundApp: Identifiable, Hashable {
    var id: String { bundlePath }
    let bundlePath: String
    let name: String
    let bundleID: String?
    let pids: [pid_t]
    let processNames: [String]
    let cpu: Double            // % of one core, summed
    let memory: Int64          // resident bytes, summed
    let rootOwned: Bool        // some process runs as root: stopping it asks for the password
    var startupItems: [StartupItem] = []   // what starts it by itself, when Cleaner can see it
}

enum Background {
    struct Proc {
        let pid: pid_t
        let uid: Int
        let cpu: Double
        let rss: Int64
        let path: String
    }

    static func processes() -> [Proc] {
        let out = Privileged.run("/bin/ps", ["-axo", "pid=,uid=,pcpu=,rss=,comm="]).output
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count == 5, let pid = pid_t(parts[0]), let uid = Int(parts[1]),
                  let cpu = Double(parts[2].replacingOccurrences(of: ",", with: ".")), let rss = Int64(parts[3]) else { return nil }
            return Proc(pid: pid, uid: uid, cpu: cpu, rss: rss * 1024, path: String(parts[4]))
        }
    }

    /// The outermost .app a path lives in, for third-party locations only.
    static func owningApp(_ path: String) -> String? {
        let home = NSHomeDirectory()
        let roots = ["/Applications/", home + "/Applications/", "/Library/", home + "/Library/"]
        guard roots.contains(where: path.hasPrefix), let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func scan(startup: [StartupItem]) -> [BackgroundApp] {
        let procs = processes()
        let me = Bundle.main.bundlePath
        let docked = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.bundleURL?.path })

        var groups: [String: [Proc]] = [:]
        for p in procs {
            guard let app = owningApp(p.path), app != me else { continue }
            groups[app, default: []].append(p)
        }
        return groups.compactMap { app, list -> BackgroundApp? in
            guard !docked.contains(app) else { return nil }
            let bundle = Bundle(path: app)
            let id = bundle?.bundleIdentifier
            let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            let items = startup.filter { item in
                item.program.hasPrefix(app + "/") || (id.map { item.label.lowercased().hasPrefix($0.lowercased()) } ?? false)
            }
            return BackgroundApp(bundlePath: app, name: name, bundleID: id, pids: list.map(\.pid),
                                 processNames: Array(Set(list.map { ($0.path as NSString).lastPathComponent })).sorted(),
                                 cpu: list.reduce(0) { $0 + $1.cpu }, memory: list.reduce(0) { $0 + $1.rss },
                                 rootOwned: list.contains { $0.uid == 0 }, startupItems: items)
        }
        .sorted { $0.memory > $1.memory }
    }

    /// Stops every process of the app. Root-owned ones go through the password; a launchd job
    /// with KeepAlive starts again unless its item is turned off too.
    static func quit(_ app: BackgroundApp) throws {
        let mine = app.pids.filter { pid in
            var info = proc_bsdinfo()
            let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            return size > 0 && info.pbi_uid == getuid()
        }
        mine.forEach { kill($0, SIGTERM) }
        let others = app.pids.filter { !mine.contains($0) }
        if !others.isEmpty {
            try Privileged.asAdmin("/bin/kill " + others.map(String.init).joined(separator: " "),
                                   prompt: "O Cleaner precisa da senha de administrador para encerrar \(app.name), que roda como sistema.")
        }
        Thread.sleep(forTimeInterval: 1)
        let left = Set(processes().map(\.pid)).intersection(mine)
        left.forEach { kill($0, SIGKILL) }
    }

    /// Paths of running programs, to mark startup items that are running right now.
    static func runningPaths() -> Set<String> { Set(processes().map(\.path)) }
}
