import Foundation

/// `Cleaner --uninstall-test`: builds a fake app that leaves every kind of trace a real one
/// does, uninstalls it with the same routine as the app, checks nothing is left, restores it,
/// checks it came back, then removes it for good. Uses its own quarantine folder.
enum UninstallTest {
    static func run() -> Int32 {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let lib = home + "/Library"
        let id = "click.ciromaciel.cleaner-teste-full"
        let name = "Cleaner Teste Completo"
        let app = home + "/Applications/\(name).app"
        let label = id + ".agent"
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print(ok ? "  ok  \(what)" : "  FAIL \(what)")
            if !ok { failures += 1 }
        }
        func write(_ path: String, _ bytes: Int = 4096) {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: Data(count: bytes))
        }

        print("Uninstall test: \(name) (\(id))")
        // The app: a bundle with a helper binary that will be running.
        try? fm.createDirectory(atPath: app + "/Contents/MacOS", withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleShortVersionString": "1.0",
                                   "CFBundlePackageType": "APPL", "CFBundleExecutable": "helper"]
        (info as NSDictionary).write(toFile: app + "/Contents/Info.plist", atomically: true)
        // A real Mach-O helper (a copied system binary is killed by code signing checks).
        let src = fm.temporaryDirectory.appendingPathComponent("cleaner-helper.c")
        try? "#include <unistd.h>\nint main(void){ sleep(600); return 0; }\n".write(to: src, atomically: true, encoding: .utf8)
        let cc = Privileged.run("/usr/bin/cc", ["-o", app + "/Contents/MacOS/helper", src.path])
        if cc.status != 0 { print("      cc failed: \(cc.output)") }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: app + "/Contents/MacOS/helper")
        helper.arguments = ["600"]
        try? helper.run()

        // Traces in the Library.
        let files = [
            "\(lib)/Application Support/\(id)/data.bin",
            "\(lib)/Application Support/ciromaciel/cleaner-teste-full/data.bin",   // vendor folder
            "\(lib)/Caches/\(id)/cache.bin",
            "\(lib)/Preferences/ByHost/\(id).0000-TEST.plist",
            "\(lib)/Saved Application State/\(id).savedState/window.data",
            "\(lib)/HTTPStorages/\(id)/httpstorages.sqlite",
            "\(lib)/Logs/DiagnosticReports/\(name)-2026-10-10-000000.ips",
        ]
        files.forEach { write($0) }
        Privileged.run("/usr/bin/defaults", ["write", id, "chave", "valor"])   // cached by cfprefsd
        let agent = "\(lib)/LaunchAgents/\(label).plist"
        (["Label": label, "ProgramArguments": ["/bin/sleep", "600"], "RunAtLoad": true] as NSDictionary).write(toFile: agent, atomically: true)
        Privileged.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agent])
        Privileged.run(Uninstaller.lsregister, ["-f", app])
        // A Dock tile.
        let tile: [String: Any] = ["tile-type": "file-tile", "tile-data": [
            "file-label": name, "bundle-identifier": id,
            "file-data": ["_CFURLString": URL(fileURLWithPath: app).absoluteString, "_CFURLStringType": 15]]]
        if let data = try? PropertyListSerialization.data(fromPropertyList: tile, format: .binary, options: 0) { Dock.restore([data]) }
        Thread.sleep(forTimeInterval: 1.5)

        func jobLoaded() -> Bool { Privileged.run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"]).status == 0 }
        func helperRunning() -> Bool { helper.isRunning }
        func inDock() -> Bool { Dock.entries().contains { $0.path == app } }
        func prefsAlive() -> Bool { Privileged.run("/usr/bin/defaults", ["read", id, "chave"]).output.contains("valor") }

        check(helperRunning() && jobLoaded() && inDock() && prefsAlive(),
              "fake app set up: helper \(helperRunning()), agent \(jobLoaded()), Dock \(inDock()), prefs \(prefsAlive())")

        // Find, as the Uninstaller screen does.
        let installed = AppCatalog.read(app)
        check(installed != nil, "app listed by the catalog (exists \(fm.fileExists(atPath: app)))")
        guard let target = installed else { return 1 }
        let leftovers = AppCatalog.leftovers(for: target)
        for l in leftovers { print("      found \(l.kind): \(Format.path(l.path))") }
        let expected = files.map { path -> String in
            // The leftover is the top folder under the Library place, or the file itself.
            for base in ["\(lib)/Application Support/ciromaciel/", "\(lib)/Application Support/", "\(lib)/Caches/", "\(lib)/Saved Application State/", "\(lib)/HTTPStorages/"] where path.hasPrefix(base) {
                return base + path.dropFirst(base.count).split(separator: "/")[0]
            }
            return path
        } + ["\(lib)/Preferences/\(id).plist", agent]
        let found = Set(leftovers.map(\.path))
        let missing = expected.filter { !found.contains($0) }
        check(missing.isEmpty, "every trace found (\(expected.count))" + (missing.isEmpty ? "" : ", missing: \(missing.map(Format.path))"))

        // Uninstall with the app's routine.
        let q = Quarantine(root: fm.temporaryDirectory.appendingPathComponent("cleaner-uninstall-test-\(UUID().uuidString.prefix(6))"))
        let report = Uninstaller.run(apps: [app], files: leftovers.map { ($0.path, $0.size) }, dockPaths: [], quarantine: q,
                                     reason: "Desinstalar \(name)")
        Thread.sleep(forTimeInterval: 1.5)
        check(!fm.fileExists(atPath: app), "app bundle gone")
        let left = AppCatalog.leftovers(bundleID: id, name: name)
        check(left.isEmpty, "no leftovers on a second search" + (left.isEmpty ? "" : ": \(left.map { Format.path($0.path) })"))
        check(report.stayed.isEmpty && report.failures.isEmpty, "nothing reported as stayed or failed")
        check(!helperRunning() && report.stoppedProcesses >= 1, "helper process stopped (\(report.stoppedProcesses))")
        check(!jobLoaded(), "launch agent unloaded")
        check(!inDock() && report.dockTiles == 1, "removed from the Dock (tiles \(report.dockTiles), still listed \(inDock()))")
        check(!prefsAlive() && !fm.fileExists(atPath: "\(lib)/Preferences/\(id).plist"), "preferences gone and not reborn")

        // Restore and check it all came back.
        if let batch = report.batch {
            var n = 0
            do { n = try q.restore(batchID: batch.id) } catch { print("      restore error: \(error.localizedDescription)") }
            Thread.sleep(forTimeInterval: 1.5)
            print("      restored \(n) of \(batch.items.count)")
            for f in [app] + files where !fm.fileExists(atPath: f) { print("      not back: \(Format.path(f))") }
            for f in fm.enumerator(atPath: "\(lib)/Application Support/ciromaciel")?.allObjects as? [String] ?? [] { print("      vendor has: \(f)") }
            check(n == batch.items.count && fm.fileExists(atPath: app) && files.allSatisfy { fm.fileExists(atPath: $0) },
                  "restore puts back the app and all \(batch.items.count - 1) leftovers")
            check(inDock(), "restore puts the Dock tile back")
            check(prefsAlive(), "restored preferences readable again")
        }

        // Clean up for good.
        Privileged.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        _ = Dock.remove(appPaths: [app])
        Privileged.run(Uninstaller.lsregister, ["-u", app])
        Privileged.run("/usr/bin/defaults", ["delete", id])
        for p in [app, agent, "\(lib)/Application Support/\(id)", "\(lib)/Application Support/ciromaciel", "\(lib)/Caches/\(id)",
                  "\(lib)/Preferences/\(id).plist", files[3], "\(lib)/Saved Application State/\(id).savedState",
                  "\(lib)/HTTPStorages/\(id)", files[6]] {
            try? fm.removeItem(atPath: p)
        }
        try? fm.removeItem(at: q.root)
        print(failures == 0 ? "All uninstall checks passed." : "\(failures) uninstall check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}
