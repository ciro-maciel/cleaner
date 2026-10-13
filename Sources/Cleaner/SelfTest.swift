import Foundation

/// `Cleaner --selftest`: runs every engine piece against this Mac and prints what it found.
/// The quarantine round trip runs in a temporary folder and touches nothing real.
enum SelfTest {
    static func run() async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "  ok  \(what)" : "  FAIL \(what)")
            if !ok { failures += 1 }
        }

        print("Cleaner self-test")
        print("Full Disk Access: \(Permissions.hasFullDiskAccess ? "on" : "off")")

        // Disk
        if let v = DiskUsage.volume() {
            print("Disk: \(Format.bytes(v.used)) used of \(Format.bytes(v.total)), \(Format.bytes(v.available)) free")
            check(v.total > 0 && v.available > 0, "volume capacity")
        } else { check(false, "volume capacity") }

        // Sizes: fts against du on a known folder
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-selftest-\(UUID().uuidString.prefix(6))")
        let src = tmp.appendingPathComponent("source/inner")
        try? FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let payload = Data(count: 3_000_000)
        try? payload.write(to: src.appendingPathComponent("a.bin"))
        try? payload.write(to: tmp.appendingPathComponent("source/b.bin"))
        let measured = DiskUsage.size(of: tmp.appendingPathComponent("source").path)
        check(measured >= 6_000_000 && measured < 6_200_000, "fts size \(Format.bytes(measured)) for 2 × 3 MB")

        let index = DiskIndex(root: tmp.path)
        await index.build(cancelled: { false })
        check((index.size(of: src.path) ?? 0) >= 3_000_000, "disk index records nested folders")

        // The index adjusts in place when something leaves (no second walk)
        let rootSize = index.size(of: tmp.path) ?? 0
        let sourceSize = index.size(of: tmp.appendingPathComponent("source").path) ?? 0
        let innerSize = index.size(of: src.path) ?? 0
        index.removed(src.path, size: innerSize)
        check(index.size(of: src.path) == nil
              && index.size(of: tmp.appendingPathComponent("source").path) == sourceSize - innerSize
              && index.size(of: tmp.path) == rootSize - innerSize, "index drops a moved folder and shrinks its parents")
        index.added(tmp.appendingPathComponent("q/0-inner").path, size: innerSize)
        check(index.size(of: tmp.path) == rootSize && index.size(of: tmp.appendingPathComponent("q").path) == innerSize,
              "index adds the quarantine copy back inside the tree")

        // Quarantine round trip in a sandbox
        let q = Quarantine(root: tmp.appendingPathComponent("quarantine"))
        let file = tmp.appendingPathComponent("source/b.bin").path
        let moved = q.move([(file, 3_000_000)], reason: "Autoteste")
        check(moved.batch != nil && !FileManager.default.fileExists(atPath: file), "move into quarantine")
        check(q.batches().count == 1, "batch listed with manifest")
        if let id = moved.batch?.id {
            let n = (try? q.restore(batchID: id)) ?? 0
            check(n == 1 && FileManager.default.fileExists(atPath: file), "restore to the original path")
        }
        let again = q.move([(file, 3_000_000)], reason: "Autoteste")
        check(q.purgeExpired(now: Date().addingTimeInterval(8 * 86_400)) == 1 && q.batches().isEmpty && again.batch != nil, "purge after 7 days")
        try? FileManager.default.removeItem(at: tmp)

        // A file macOS refuses to move (EPERM: privacy, SIP, or here the immutable flag) stays in
        // place with a message, and never asks for the administrator password, which would not
        // unlock it. Before 0.1.23 this asked for the password on every cleanup of a new Mac.
        let lockedRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-eperm-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: lockedRoot, withIntermediateDirectories: true)
        let locked = lockedRoot.appendingPathComponent("travado.txt").path
        FileManager.default.createFile(atPath: locked, contents: Data("x".utf8))
        Privileged.run("/usr/bin/chflags", ["uchg", locked])
        let lockedQ = Quarantine(root: lockedRoot.appendingPathComponent("Quarantine"))
        let lockedStart = Date()
        let lockedResult = lockedQ.move([(locked, 1)], reason: "Autoteste EPERM")
        let lockedTime = Date().timeIntervalSince(lockedStart)
        let lockedMessage = lockedResult.failures.first?.message ?? ""
        let expected = Permissions.hasFullDiskAccess ? "O macOS protege este item" : Quarantine.fullDiskAccessMessage
        check(lockedResult.batch == nil && FileManager.default.fileExists(atPath: locked) && lockedMessage == expected && lockedTime < 2,
              "a refused move (EPERM) stays in place, says \"\(lockedMessage)\", and asks for no password")
        Privileged.run("/usr/bin/chflags", ["nouchg", locked])
        try? FileManager.default.removeItem(at: lockedRoot)

        // A big batch leaves the list instantly; the deleting is a separate, slow step
        let bigRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-purge-\(UUID().uuidString.prefix(6))")
        let bigQ = Quarantine(root: bigRoot.appendingPathComponent("Quarantine"))
        let bigSrc = bigRoot.appendingPathComponent("many")
        for d in 0..<50 {
            let dir = bigSrc.appendingPathComponent("d\(d)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in 0..<1000 { FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(f)").path, contents: Data(count: 64)) }
        }
        let bigBatch = bigQ.move([(bigSrc.path, 0)], reason: "Autoteste grande")
        let t0 = Date()
        let staged = bigBatch.batch.map { bigQ.stage(batchID: $0.id) } ?? false
        let stageTime = Date().timeIntervalSince(t0)
        let t1 = Date()
        bigQ.finishPurges()
        let purgeTime = Date().timeIntervalSince(t1)
        let leftoverStaged = (try? FileManager.default.contentsOfDirectory(atPath: bigQ.purging.path))?.count ?? 0
        check(staged && stageTime < 0.1 && bigQ.batches().isEmpty,
              String(format: "50.000 files leave the list in %.3f s (the window waits only for this)", stageTime))
        check(leftoverStaged == 0, String(format: "background delete finished in %.1f s, nothing left", purgeTime))
        try? FileManager.default.removeItem(at: bigRoot)

        // Cleanup rules against this Mac (read only)
        let rules = CleanupRule.loadAll()
        check(!rules.isEmpty, "rules.json loaded (\(rules.count) rules)")
        let started = Date()
        let groups = await CleanupScanner.scan(rules: rules, running: CleanupScanner.runningBundleIDs())
        let total = groups.reduce(Int64(0)) { $0 + $1.size }
        print(String(format: "Cleanup: %@ in %d groups (%.1f s)", Format.bytes(total), groups.count, Date().timeIntervalSince(started)))
        for g in groups { print("    \(g.rule.title): \(Format.bytes(g.size)), \(g.items.count) itens") }
        let home = NSHomeDirectory()
        let outside = groups.flatMap(\.items).filter { !$0.path.hasPrefix(home) }
        check(outside.isEmpty, "every cleanup item lives in the home folder")

        // Apps
        let apps = AppCatalog.list()
        check(!apps.isEmpty, "apps listed (\(apps.count))")
        if let sample = apps.first(where: { !$0.fromAppStore }) ?? apps.first {
            let left = AppCatalog.leftovers(for: sample)
            print("    \(sample.name) (\(sample.bundleID)): \(left.count) leftovers, \(Format.bytes(left.reduce(0) { $0 + $1.size }))")
            for l in left.prefix(5) { print("      \(l.kind): \(Format.path(l.path)) \(Format.bytes(l.size))") }
        }

        // Full uninstall: Dock ghosts and leftovers of apps already gone (read only)
        let ghosts = Dock.entries().filter { !$0.exists }
        print("Dock: \(Dock.entries().count) pinned apps, \(ghosts.count) missing on disk")
        for g in ghosts {
            let left = AppCatalog.leftovers(bundleID: g.bundleID ?? "", name: g.name)
            print("    ghost \(g.name) (\(g.bundleID ?? "?")): \(left.count) leftovers")
            for l in left { print("      \(l.kind): \(Format.path(l.path))\(l.protected ? " [protected]" : "")") }
        }

        // A moved .plist must not come back from cfprefsd's memory
        let domain = "click.ciromaciel.cleaner-selftest"
        Privileged.run("/usr/bin/defaults", ["write", domain, "key", "value"])
        let plist = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Preferences/\(domain).plist")
        try? await Task.sleep(for: .milliseconds(500))
        let qp = Quarantine(root: tmp.appendingPathComponent("prefs-q"))
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let movedPrefs = qp.move([(plist, 4096)], reason: "Autoteste preferências")
        // Touch the domain the way an app would; without the fix cfprefsd writes it back.
        Privileged.run("/usr/bin/defaults", ["read", domain])
        try? await Task.sleep(for: .seconds(1))
        let reborn = FileManager.default.fileExists(atPath: plist) &&
            Privileged.run("/usr/bin/defaults", ["read", domain, "key"]).output.contains("value")
        check(movedPrefs.batch != nil && !reborn, "moved .plist does not come back from cfprefsd")
        Privileged.run("/usr/bin/defaults", ["delete", domain])
        try? FileManager.default.removeItem(atPath: plist)
        try? FileManager.default.removeItem(at: tmp)

        // Startup
        let items = Startup.list()
        print("Startup: \(items.count) items, \(items.filter { $0.domain == .user }.count) of the user")
        print("    running now: \(items.filter(\.running).map(\.label))")
        let bg = Background.scan(startup: items)
        print("Background: \(bg.count) apps with no window")
        for b in bg {
            print("    \(b.name) — \(b.pids.count) proc, \(Format.bytes(b.memory)), cpu \(Format.decimal(b.cpu))%\(b.rootOwned ? ", root" : "")\(b.startupItems.isEmpty ? "" : ", starts by itself: \(b.startupItems.map(\.label))")")
            print("      \(Format.path(b.bundlePath)): \(b.processNames.prefix(4).joined(separator: ", "))")
        }
        check(!bg.contains { $0.bundlePath == Bundle.main.bundlePath }, "Cleaner does not list itself")
        check(true, "launchd items read")

        // Monitor: two readings a second apart, so the rates exist
        let reader = SystemReader()
        _ = reader.sample()
        try? await Task.sleep(for: .seconds(1))
        let m = reader.sample()
        print(String(format: "Monitor: CPU %.0f%% (%d cores), GPU %@, memory %@ of %@ (pressure %d), swap %@",
                     m.cpu.total * 100, m.cpu.cores.count, m.gpu.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a",
                     Format.bytes(m.memory.used), Format.bytes(m.memory.total), m.memory.pressure, Format.bytes(m.memory.swapUsed)))
        print("    disk \(Format.bytes(m.disk.free)) free, read \(Format.rate(m.disk.readPerSec)), write \(Format.rate(m.disk.writePerSec))")
        print("    network \(m.network.interface) \(m.network.address): in \(Format.rate(m.network.inPerSec)), out \(Format.rate(m.network.outPerSec)), since boot \(Format.bytes(m.network.totalIn)) / \(Format.bytes(m.network.totalOut))")
        if let b = m.battery {
            print("    battery \(b.percent)% charging=\(b.charging) ac=\(b.onAC) cycles=\(b.cycles.map(String.init) ?? "?") health=\(b.health.map { String(format: "%.0f%%", $0 * 100) } ?? "?") temp=\(b.temperature.map { String(format: "%.1f °C", $0) } ?? "?") watts=\(b.watts.map { String(format: "%.1f", $0) } ?? "?")")
        }
        check(m.cpu.cores.count == ProcessInfo.processInfo.processorCount && m.cpu.total >= 0 && m.cpu.total <= 1, "CPU per core and total in range")
        check(m.memory.used > 0 && m.memory.used <= m.memory.total, "memory used within physical memory")
        check(m.network.totalIn > 0, "network counters read")
        let procs = SystemReader.topProcesses()
        check(procs.count > 50, "process list (\(procs.count) processes)")
        if let top = procs.max(by: { $0.cpu < $1.cpu }) { print("    top CPU: \(top.name) \(top.cpu)%") }

        print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
