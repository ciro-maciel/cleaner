import Foundation
import AppKit

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            let done = DispatchSemaphore(value: 0)
            var status: Int32 = 1
            Task.detached {
                status = await SelfTest.run()
                done.signal()
            }
            done.wait()
            exit(status)
        }
        if let i = args.firstIndex(of: "--fda-report"), i + 1 < args.count {
            // Run through `open -n` so macOS judges this app, not the terminal.
            let r = Permissions.probe()
            let text = (["granted: \(r.granted)"] + r.results.map { "\($0.result)  \($0.path)" }).joined(separator: "\n")
            try? text.write(toFile: args[i + 1], atomically: true, encoding: .utf8)
            exit(0)
        }
        if let i = args.firstIndex(of: "--helper"), i + 2 < args.count {
            // --helper status|register|purge <report file>; run through `open -n`.
            let action = args[i + 1], file = args[i + 2]
            let report = ReportFile(path: file)
            let line: @Sendable (String) -> Void = { report.add($0) }
            if action == "register" { line("register: \(Helper.register())") }
            line("state: \(Helper.state)")
            if action == "purge" {
                let done = DispatchSemaphore(value: 0)
                Task.detached {
                    let reader = SystemReader()
                    let before = reader.freeBytes()
                    do {
                        line("version: \(try await Helper.version())")
                        let t = Date()
                        try await Helper.purgeMemory()
                        line(String(format: "purge ok in %.1f s", Date().timeIntervalSince(t)))
                        try? await Task.sleep(for: .milliseconds(500))
                        line("free before \(Format.bytes(before)), after \(Format.bytes(reader.freeBytes()))")
                    } catch { line("error: \(error.localizedDescription)") }
                    done.signal()
                }
                done.wait()
            }
            exit(0)
        }
        if args.contains("--uninstall-test") { exit(UninstallTest.run()) }
        if args.contains("--migrate") {
            Quarantine.migrateFromBroom()
            for b in Quarantine().batches() {
                let ok = b.activeItems.allSatisfy { FileManager.default.fileExists(atPath: $0.stored) }
                print("\(ok ? "ok  " : "LOST") \(b.reason): \(b.activeItems.count) itens, \(Format.bytes(b.size))")
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--rows-preview"), i + 1 < args.count {
            Zen.registerFonts()
            MainActor.assumeIsolated { RowsPreview.run(URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--menubar-preview"), i + 1 < args.count {
            Zen.registerFonts()
            MainActor.assumeIsolated { MenuBarPreview.run(URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        Debug.log("main")
        CleanerApp.main()
        Debug.log("CleanerApp.main returned")
    }
}

/// Lines written to a file as they come, from any thread (for the CLI checks).
final class ReportFile: @unchecked Sendable {
    private let path: String
    private var lines: [String] = []
    private let lock = NSLock()
    init(path: String) { self.path = path }
    func add(_ line: String) {
        lock.withLock {
            lines.append(line)
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
