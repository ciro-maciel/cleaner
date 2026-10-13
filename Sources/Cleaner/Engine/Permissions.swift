import Foundation
import AppKit

enum Permissions {
    /// Full Disk Access cannot be asked for: the user turns it on in System Settings, and no
    /// API says whether it is on. The probe opens places only it unlocks; any one that opens
    /// means yes. (The user TCC.db, the usual single probe, is gone from recent macOS, which
    /// left the old check stuck on "off".)
    static var hasFullDiskAccess: Bool { probe().granted }

    static func probe() -> (granted: Bool, results: [(path: String, result: String)]) {
        let home = NSHomeDirectory()
        let places = [
            "\(home)/Library/Safari",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/.Trash",
            "\(home)/Library/Containers/com.apple.mail",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        var results: [(String, String)] = []
        var granted = false
        for path in places {
            var isDir: ObjCBool = false
            let r: String
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                if let dir = opendir(path) { closedir(dir); r = "ok"; granted = true } else { r = errno == EPERM || errno == EACCES ? "negado" : "erro \(errno)" }
            } else {
                let fd = open(path, O_RDONLY)
                if fd >= 0 { close(fd); r = "ok"; granted = true } else { r = errno == ENOENT ? "não existe" : (errno == EPERM || errno == EACCES ? "negado" : "erro \(errno)") }
            }
            results.append((path, r))
        }
        return (granted, results)
    }

    /// macOS may apply a new grant only to a fresh process: relaunch Cleaner.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// The Full Disk Access list itself (15-app-mac.md), with the older address as a fallback.
    static func openFullDiskAccessSettings() {
        for address in ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"] {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
