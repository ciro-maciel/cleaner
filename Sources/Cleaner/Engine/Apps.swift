import Foundation
import AppKit
import CoreServices

/// An installed app and, once asked, everything it left in the Library folders.
struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String
    let version: String
    let fromAppStore: Bool
    var size: Int64?
    var lastUsed: Date?

    static func == (a: InstalledApp, b: InstalledApp) -> Bool { a.path == b.path && a.size == b.size }
    func hash(into h: inout Hasher) { h.combine(path) }
}

struct Leftover: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let kind: String
    /// Outside the home folder: moving it asks for the administrator password.
    let system: Bool
    /// macOS protects app containers: they only move with Full Disk Access on.
    var protected: Bool { path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") }
}

enum AppCatalog {
    /// Apps that are part of macOS itself and cannot be removed.
    static let protected: Set<String> = ["com.apple.Safari"]

    static func list() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = (root as NSString).appendingPathComponent(name)
                if name.hasSuffix(".app") {
                    if let app = read(path), seen.insert(app.bundleID + app.path).inserted { apps.append(app) }
                } else if !name.hasPrefix("."), (try? fm.destinationOfSymbolicLink(atPath: path)) == nil,
                          let inner = try? fm.contentsOfDirectory(atPath: path) {
                    // One level of folders, like /Applications/Utilities or a vendor folder.
                    for sub in inner where sub.hasSuffix(".app") {
                        if let app = read((path as NSString).appendingPathComponent(sub)) { apps.append(app) }
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func read(_ path: String) -> InstalledApp? {
        let url = URL(fileURLWithPath: path)
        // Apps that live on the sealed system volume (Safari) resolve outside /Applications.
        if url.resolvingSymlinksInPath().path.hasPrefix("/System/") { return nil }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !protected.contains(id) else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let fileName = url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let store = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
        return InstalledApp(path: path, name: fileName.count >= name.count ? fileName : name, bundleID: id,
                            version: version, fromAppStore: store, size: nil, lastUsed: lastUsed(path))
    }

    static func lastUsed(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func isRunning(_ app: InstalledApp) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == app.bundleID }
    }

    // MARK: leftovers

    private struct Place { let path: String; let kind: String; let match: Match }
    private enum Match {
        case name       // a folder named after the bundle id or the app
        case plist      // bundleid.plist, bundleid.*.plist
        case group      // group containers: group.bundleid, TEAM.bundleid
        case prefix     // bundleid or bundleid.*
        case report     // crash and diagnostic reports: AppName-date.ips, AppName_UUID.plist
        case plugin     // a bundle named after the app or the bundle id: Foo.prefPane, Foo.qlgenerator
    }

    /// Where apps leave files on macOS. Matching is strict on purpose: the bundle identifier,
    /// or the app's own name, never a loose "contains". Reviewed 10/10/2026 against the places
    /// an app can write: user and system Library, crash reports, plug-in folders, pkg receipts.
    private static func places() -> [Place] {
        let lib = (NSHomeDirectory() as NSString).appendingPathComponent("Library")
        return [
            Place(path: "\(lib)/Application Support", kind: "Dados do app", match: .name),
            Place(path: "\(lib)/Caches", kind: "Cache", match: .name),
            Place(path: "\(lib)/Preferences", kind: "Preferências", match: .plist),
            Place(path: "\(lib)/Preferences/ByHost", kind: "Preferências desta máquina", match: .prefix),
            Place(path: "\(lib)/Containers", kind: "Contêiner", match: .name),
            Place(path: "\(lib)/Group Containers", kind: "Contêiner de grupo", match: .group),
            Place(path: "\(lib)/Saved Application State", kind: "Estado das janelas", match: .prefix),
            Place(path: "\(lib)/HTTPStorages", kind: "Dados de rede", match: .prefix),
            Place(path: "\(lib)/WebKit", kind: "Dados de navegação", match: .name),
            Place(path: "\(lib)/Cookies", kind: "Cookies", match: .prefix),
            Place(path: "\(lib)/Logs", kind: "Registros", match: .name),
            Place(path: "\(lib)/Logs/DiagnosticReports", kind: "Relatório de erro", match: .report),
            Place(path: "\(lib)/Application Support/CrashReporter", kind: "Relatório de erro", match: .report),
            Place(path: "\(lib)/Application Scripts", kind: "Scripts", match: .name),
            Place(path: "\(lib)/Autosave Information", kind: "Documentos salvos sozinhos", match: .prefix),
            Place(path: "\(lib)/LaunchAgents", kind: "Item de inicialização", match: .plist),
            Place(path: "\(lib)/Internet Plug-Ins", kind: "Plug-in de navegador", match: .plugin),
            Place(path: "\(lib)/PreferencePanes", kind: "Painel de Ajustes", match: .plugin),
            Place(path: "\(lib)/QuickLook", kind: "Plug-in do Quick Look", match: .plugin),
            Place(path: "\(lib)/Services", kind: "Serviço do menu", match: .plugin),
            Place(path: "\(lib)/Screen Savers", kind: "Protetor de tela", match: .plugin),
            Place(path: "/Library/Application Support", kind: "Dados do app (sistema)", match: .name),
            Place(path: "/Library/Caches", kind: "Cache (sistema)", match: .name),
            Place(path: "/Library/Preferences", kind: "Preferências (sistema)", match: .plist),
            Place(path: "/Library/Logs", kind: "Registros (sistema)", match: .name),
            Place(path: "/Library/Logs/DiagnosticReports", kind: "Relatório de erro (sistema)", match: .report),
            Place(path: "/Library/LaunchAgents", kind: "Item de inicialização (sistema)", match: .plist),
            Place(path: "/Library/LaunchDaemons", kind: "Serviço em segundo plano", match: .plist),
            Place(path: "/Library/PrivilegedHelperTools", kind: "Ajudante privilegiado", match: .prefix),
            Place(path: "/Library/Internet Plug-Ins", kind: "Plug-in de navegador (sistema)", match: .plugin),
            Place(path: "/Library/PreferencePanes", kind: "Painel de Ajustes (sistema)", match: .plugin),
            Place(path: "/Library/QuickLook", kind: "Plug-in do Quick Look (sistema)", match: .plugin),
            Place(path: "/Library/Screen Savers", kind: "Protetor de tela (sistema)", match: .plugin),
            Place(path: "/Library/Audio/Plug-Ins/HAL", kind: "Driver de áudio", match: .plugin),
            Place(path: "/Library/Audio/Plug-Ins/Components", kind: "Plug-in de áudio", match: .plugin),
            Place(path: "/Library/Audio/Plug-Ins/VST", kind: "Plug-in de áudio", match: .plugin),
            Place(path: "/Library/Audio/Plug-Ins/VST3", kind: "Plug-in de áudio", match: .plugin),
            Place(path: "/private/var/db/receipts", kind: "Recibo de instalação", match: .prefix),
        ]
    }

    /// Leftovers of an app that is no longer on disk, by its bundle identifier and name.
    static func leftovers(bundleID: String, name: String) -> [Leftover] {
        let ghost = InstalledApp(path: "/Applications/\(name).app", name: name, bundleID: bundleID, version: "", fromAppStore: false)
        return leftovers(for: ghost)
    }

    static func leftovers(for app: InstalledApp) -> [Leftover] {
        let home = NSHomeDirectory()
        let id = app.bundleID.lowercased()
        guard id.count >= 5 else { return [] }
        let names = Set([app.name, URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent]
            .map { $0.lowercased() }.filter { $0.count >= 3 })

        func hit(_ e: String, _ match: Match) -> Bool {
            switch match {
            case .name: return e == id || names.contains(e) || e.hasPrefix(id + ".")
            case .plist: return e == id + ".plist" || (e.hasPrefix(id + ".") && e.hasSuffix(".plist"))
            case .group: return e.hasSuffix("." + id) || e == "group." + id || e.hasPrefix("group." + id + ".")
            case .prefix: return e == id || e.hasPrefix(id + ".")
            case .report: return names.contains { e.hasPrefix($0 + "-") || e.hasPrefix($0 + "_") || e.hasPrefix($0 + ".") }
            case .plugin:
                let base = (e as NSString).deletingPathExtension
                return names.contains(base) || base == id || base.hasPrefix(id + ".")
            }
        }

        var out: [Leftover] = []
        var seen = Set<String>()
        let fm = FileManager.default
        func add(_ path: String, _ kind: String) {
            guard path != app.path, seen.insert(path).inserted else { return }
            out.append(Leftover(path: path, size: DiskUsage.size(of: path), kind: kind, system: !path.hasPrefix(home)))
        }
        for place in places() {
            guard let entries = try? fm.contentsOfDirectory(atPath: place.path) else { continue }
            for entry in entries where hit(entry.lowercased(), place.match) {
                add((place.path as NSString).appendingPathComponent(entry), place.kind)
            }
        }

        // Vendor folders: Application Support/Google/Chrome, Caches/Microsoft/Teams. Only the
        // child named exactly like the app; the vendor folder itself is shared, never touched.
        let parts = app.bundleID.split(separator: ".").map(String.init)
        if parts.count >= 3 {
            let vendor = parts[1].lowercased()
            // Inside a vendor folder the app goes by its short name too: com.google.Chrome → Chrome.
            let childNames = names.union([parts.last!.lowercased()].filter { $0.count >= 3 })
            let lib = (home as NSString).appendingPathComponent("Library")
            for base in ["\(lib)/Application Support", "\(lib)/Caches", "/Library/Application Support"] {
                guard let vendors = try? fm.contentsOfDirectory(atPath: base) else { continue }
                for v in vendors where v.lowercased() == vendor {
                    let folder = (base as NSString).appendingPathComponent(v)
                    for child in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where childNames.contains(child.lowercased()) {
                        add((folder as NSString).appendingPathComponent(child), base.hasSuffix("Caches") ? "Cache" : "Dados do app")
                    }
                }
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
