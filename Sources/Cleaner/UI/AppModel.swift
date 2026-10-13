import SwiftUI
import AppKit
import Observation

enum Screen: String, CaseIterable, Identifiable {
    case overview, monitor, cleanup, uninstaller, diskmap, startup, quarantine, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Visão geral"
        case .monitor: return "Monitor"
        case .cleanup: return "Limpeza"
        case .uninstaller: return "Desinstalador"
        case .diskmap: return "Mapa do disco"
        case .startup: return "Segundo plano"
        case .quarantine: return "Quarentena"
        case .settings: return "Geral"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "layout-dashboard"
        case .monitor: return "activity"
        case .cleanup: return "sparkles"
        case .uninstaller: return "package"
        case .diskmap: return "chart-treemap"
        case .startup: return "rocket"
        case .quarantine: return "shield-check"
        case .settings: return "settings"
        }
    }

    /// The sidebar's groups (15-app-mac.md): the tools, then Ajustes.
    static let tools: [Screen] = [.overview, .monitor, .cleanup, .uninstaller, .diskmap, .startup, .quarantine]
    static let settingsGroup: [Screen] = [.settings]
}

struct DiskEntry: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let isFolder: Bool
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    var screen: Screen = .overview
    var toast: Toast?

    // Basics
    var hasFullDiskAccess = Permissions.hasFullDiskAccess
    var volume = DiskUsage.volume()
    let quarantine = Quarantine()
    var batches: [Quarantine.Batch] = []

    // Cleanup
    let rules = CleanupRule.loadAll()
    var cleanupGroups: [CleanupGroup]? = nil
    var cleanupSelection = Set<String>()
    var cleanupScanning = false
    var cleanupScannedAt: Date?
    var expandedGroups = Set<String>()

    // Uninstaller
    var apps: [InstalledApp] = []
    var appsLoading = false
    var appQuery = ""
    /// Apps ticked in the list; the review sheet opens for all of them at once.
    var appSelection = Set<String>()
    var uninstallTargets: [InstalledApp] = []
    var showUninstall = false
    var leftovers: [String: [Leftover]] = [:]   // app path → what it left
    var leftoverSelection = Set<String>()
    var leftoversLoading = false
    var uninstalling = false

    // Disk map
    var diskIndex: DiskIndex?
    var diskRoot = NSHomeDirectory()
    var diskPath = NSHomeDirectory()
    var diskScanning = false
    var diskFilesSeen = 0
    /// Ticked rows of the folder on screen; cleared when the folder changes.
    var diskSelection = Set<String>()
    var diskMoving = false
    /// Bumped when the index changes in place, so the screen reads the new sizes.
    var diskRevision = 0

    // Background and startup
    var startupItems: [StartupItem] = []
    var startupLoading = false
    var backgroundApps: [BackgroundApp] = []
    var backgroundBusy = Set<String>()

    var scanningAnything: Bool { cleanupScanning || appsLoading || diskScanning || startupLoading }

    init() {
        quarantine.stageExpired()
        batches = quarantine.batches()
        purgingBytes = quarantine.purgingBytes()
        if purgingBytes > 0 { Task { await finishPurging(announce: false) } }
    }

    func refreshBasics() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        volume = DiskUsage.volume()
        batches = quarantine.batches()
    }

    /// A move left items in place because Full Disk Access is off: say which permission, in
    /// Portuguese, and open the screen whose button leads to the switch (15-app-mac.md). Never
    /// a password prompt: the password does not unlock what macOS keeps behind privacy.
    func pointToFullDiskAccess(_ count: Int) {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        screen = .settings
        show("\(Quarantine.fullDiskAccessMessage): \(Format.plural(count, "item ficou", "itens ficaram")) no lugar. Ligue em Ajustes.", error: true)
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, error: error)
        withAnimation(.easeOut(duration: 0.2)) { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(error ? 6 : 4))
            if toast == t { withAnimation(.easeIn(duration: 0.2)) { toast = nil } }
        }
    }

    // MARK: Overview: one scan for everything that is cheap to measure

    func scanEverything() async {
        refreshBasics()
        async let a: Void = scanCleanup()
        async let b: Void = loadApps()
        async let c: Void = loadStartup()
        _ = await (a, b, c)
        Debug.log("scan done: cleanup \(Format.bytes(cleanupTotal)) in \(cleanupGroups?.count ?? 0) rules, \(apps.count) apps, \(startupItems.count) startup items")
    }

    // MARK: Cleanup

    var cleanupTotal: Int64 { cleanupGroups?.reduce(0) { $0 + $1.size } ?? 0 }
    var cleanupSelectedBytes: Int64 {
        cleanupGroups?.flatMap(\.items).filter { cleanupSelection.contains($0.path) }.reduce(0) { $0 + $1.size } ?? 0
    }
    var cleanupSelectedCount: Int { cleanupSelection.count }

    func scanCleanup() async {
        guard !cleanupScanning else { return }
        cleanupScanning = true
        let rules = self.rules
        let running = CleanupScanner.runningBundleIDs()
        let groups = await Task.detached { await CleanupScanner.scan(rules: rules, running: running) }.value
        cleanupGroups = groups
        cleanupSelection = Set(groups.filter { $0.rule.defaultOn }.flatMap(\.items).filter { $0.hold == nil }.map(\.path))
        cleanupScannedAt = Date()
        cleanupScanning = false
    }

    func groupState(_ g: CleanupGroup) -> CheckBox.State {
        let n = g.items.filter { cleanupSelection.contains($0.path) }.count
        return n == 0 ? .off : (n == g.items.count ? .on : .mixed)
    }

    func toggleGroup(_ g: CleanupGroup) {
        if groupState(g) == .on { g.items.forEach { cleanupSelection.remove($0.path) } }
        else { g.items.forEach { cleanupSelection.insert($0.path) } }
    }

    func toggleItem(_ item: CleanupItem) {
        if cleanupSelection.contains(item.path) { cleanupSelection.remove(item.path) } else { cleanupSelection.insert(item.path) }
    }

    func cleanSelected() async {
        guard let groups = cleanupGroups else { return }
        let entries = groups.flatMap(\.items).filter { cleanupSelection.contains($0.path) }.map { ($0.path, $0.size) }
        guard !entries.isEmpty else { return }
        let q = quarantine
        let result = await Task.detached { q.move(entries, reason: "Limpeza") }.value
        let moved = Set(result.batch?.items.map(\.original) ?? [])
        cleanupGroups = groups.map { g in
            var g = g; g.items.removeAll { moved.contains($0.path) }; return g
        }.filter { !$0.items.isEmpty }
        cleanupSelection.subtract(moved)
        refreshBasics()
        let bytes = result.batch?.size ?? 0
        if !result.needsFullDiskAccess.isEmpty {
            pointToFullDiskAccess(result.needsFullDiskAccess.count)
        } else if result.failures.isEmpty {
            show("\(Format.bytes(bytes)) na quarentena. Dá para desfazer por 7 dias.")
        } else {
            show("\(Format.bytes(bytes)) na quarentena; \(Format.plural(result.failures.count, "item não saiu", "itens não saíram")) do lugar.", error: true)
        }
    }

    // MARK: Uninstaller

    var filteredApps: [InstalledApp] {
        let q = appQuery.trimmingCharacters(in: .whitespaces)
        let list = q.count < 2 ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q) }
        return list.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
    }
    var appsTotal: Int64 { apps.reduce(0) { $0 + ($1.size ?? 0) } }

    func loadApps() async {
        guard !appsLoading else { return }
        appsLoading = true
        let list = await Task.detached { AppCatalog.list() }.value
        // Keep sizes we already know so a refresh does not blank the list.
        let known = Dictionary(apps.map { ($0.path, $0.size) }, uniquingKeysWith: { a, _ in a })
        apps = list.map { var a = $0; a.size = known[a.path] ?? nil; return a }
        await withTaskGroup(of: (String, Int64).self) { group in
            var running = 0
            for app in list where known[app.path] == nil {
                if running >= 6, let (path, size) = await group.next() { setSize(path, size); running -= 1 }
                running += 1
                group.addTask { (app.path, DiskUsage.size(of: app.path)) }
            }
            for await (path, size) in group { setSize(path, size) }
        }
        appsLoading = false
        await loadOrphans()
    }

    private func setSize(_ path: String, _ size: Int64) {
        if let i = apps.firstIndex(where: { $0.path == path }) { apps[i].size = size }
    }

    func toggleApp(_ app: InstalledApp) {
        if appSelection.contains(app.path) { appSelection.remove(app.path) } else { appSelection.insert(app.path) }
    }

    var selectedApps: [InstalledApp] { apps.filter { appSelection.contains($0.path) } }
    var selectedAppsBytes: Int64 { selectedApps.reduce(0) { $0 + ($1.size ?? 0) } }

    /// Opens the review for the given apps (the ticked ones by default) and looks for leftovers.
    func prepareUninstall(_ targets: [InstalledApp]? = nil) async {
        let list = targets ?? selectedApps
        guard !list.isEmpty else { return }
        uninstallTargets = list
        leftovers = [:]
        leftoverSelection = []
        leftoversLoading = true
        showUninstall = true
        let found = await withTaskGroup(of: (String, [Leftover]).self) { group in
            for app in list { group.addTask { (app.path, AppCatalog.leftovers(for: app)) } }
            var out: [String: [Leftover]] = [:]
            for await (path, left) in group { out[path] = left }
            return out
        }
        guard uninstallTargets.map(\.path) == list.map(\.path) else { return }
        // A folder two apps share (a vendor folder) is listed once, under the first app.
        var seen = Set<String>()
        leftovers = Dictionary(uniqueKeysWithValues: list.map { app in
            (app.path, (found[app.path] ?? []).filter { seen.insert($0.path).inserted })
        })
        leftoverSelection = Set(leftovers.values.flatMap { $0.map(\.path) })
        leftoversLoading = false
    }

    func closeUninstall() {
        showUninstall = false
        uninstallTargets = []
    }

    var uninstallBytes: Int64 {
        uninstallTargets.reduce(0) { $0 + ($1.size ?? 0) }
            + leftovers.values.flatMap { $0 }.filter { leftoverSelection.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    var runningTargets: [InstalledApp] { uninstallTargets.filter { AppCatalog.isRunning($0) != nil } }

    func quitRunningTargets() {
        for app in uninstallTargets { AppCatalog.isRunning(app)?.terminate() }
    }

    func uninstall() async {
        let targets = uninstallTargets
        guard !targets.isEmpty, !uninstalling else { return }
        let open = runningTargets
        if !open.isEmpty {
            show("Feche antes: \(open.map(\.name).joined(separator: ", ")).", error: true)
            return
        }
        uninstalling = true
        var entries: [(String, Int64)] = []
        var seen = Set<String>()
        for app in targets {
            if seen.insert(app.path).inserted { entries.append((app.path, app.size ?? 0)) }
            for left in leftovers[app.path] ?? [] where leftoverSelection.contains(left.path) {
                if seen.insert(left.path).inserted { entries.append((left.path, left.size)) }
            }
        }
        let names = targets.map(\.name)
        let reason = names.count == 1 ? "Desinstalar \(names[0])" : "Desinstalar \(names.count) apps: \(names.joined(separator: ", "))"
        let q = quarantine
        let appPaths = targets.map(\.path)
        let files = entries.filter { !appPaths.contains($0.0) }
        let report = await Task.detached {
            Uninstaller.run(apps: appPaths, files: files, dockPaths: [], quarantine: q, reason: reason)
        }.value
        let moved = Set(report.batch?.items.map(\.original) ?? [])
        let gone = targets.filter { moved.contains($0.path) }
        if !gone.isEmpty {
            UninstallHistory.add(gone.map { UninstallHistory.Record(bundleID: $0.bundleID, name: $0.name, path: $0.path, date: Date()) })
        }
        uninstalling = false
        apps.removeAll { moved.contains($0.path) }
        appSelection.subtract(moved)
        refreshBasics()

        let stayed = report.stayed.filter { !appPaths.contains($0) }
        let containersBlocked = stayed.contains { $0.contains("/Library/Containers/") || $0.contains("/Library/Group Containers/") } && !hasFullDiskAccess
        if gone.count == targets.count {
            closeUninstall()
            let what = gone.count == 1 ? "\(gone[0].name) desinstalado" : "\(gone.count) apps desinstalados"
            if !report.needsFullDiskAccess.isEmpty {
                pointToFullDiskAccess(report.needsFullDiskAccess.count)
            } else if stayed.isEmpty {
                var extras: [String] = []
                if report.dockTiles > 0 { extras.append("fora do Dock") }
                if report.stoppedProcesses > 0 { extras.append(Format.plural(report.stoppedProcesses, "processo parado", "processos parados")) }
                show("\(what) por completo: \(Format.bytes(report.batch?.size ?? 0)) na quarentena\(extras.isEmpty ? "" : ", " + extras.joined(separator: ", ")).")
            } else {
                show("\(what), mas \(Format.plural(stayed.count, "resto ficou", "restos ficaram"))\(containersBlocked ? ": ligue o Acesso Total ao Disco e use Restos de apps" : ". Veja em Restos de apps").", error: true)
            }
        } else {
            uninstallTargets = targets.filter { !moved.contains($0.path) }
            let why = report.failures.first?.message ?? "sem detalhe do sistema"
            show("\(Format.plural(targets.count - gone.count, "app não saiu", "apps não saíram")): \(why)", error: true)
        }
        await loadOrphans()
    }

    // MARK: Leftovers of apps already gone

    struct Orphan: Identifiable, Hashable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
        let path: String
        let inDock: Bool
        let leftovers: [Leftover]
        var size: Int64 { leftovers.reduce(0) { $0 + $1.size } }
        var dockKey: String { "dock:" + path }
    }

    var orphans: [Orphan] = []
    var orphanSelection = Set<String>()
    var orphansCleaning = false

    /// Apps known to be gone (removed by Cleaner, or pinned in the Dock but missing on disk)
    /// whose files are still around.
    func loadOrphans() async {
        let installed = Set(apps.map(\.bundleID))
        let found = await Task.detached { () -> [Orphan] in
            var known: [String: (name: String, path: String)] = [:]
            for r in UninstallHistory.all() { known[r.bundleID] = (r.name, r.path) }
            let dock = Dock.entries()
            for e in dock where !e.exists { if let id = e.bundleID { known[id] = (e.name, e.path) } }
            let ghostPaths = Set(dock.filter { !$0.exists }.map(\.path))
            return known.filter { !installed.contains($0.key) }.compactMap { id, info in
                let left = AppCatalog.leftovers(bundleID: id, name: info.name)
                let inDock = ghostPaths.contains(info.path)
                guard inDock || !left.isEmpty else { return nil }
                return Orphan(bundleID: id, name: info.name, path: info.path, inDock: inDock, leftovers: left)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
        orphans = found
        orphanSelection = Set(found.flatMap { o in o.leftovers.map(\.path) + (o.inDock ? [o.dockKey] : []) })
    }

    var orphanSelectedBytes: Int64 {
        orphans.flatMap(\.leftovers).filter { orphanSelection.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    func cleanOrphans() async {
        guard !orphansCleaning else { return }
        orphansCleaning = true
        let chosen = orphans.flatMap(\.leftovers).filter { orphanSelection.contains($0.path) }
        let dockPaths = Set(orphans.filter { $0.inDock && orphanSelection.contains($0.dockKey) }.map(\.path))
        let names = orphans.filter { o in o.leftovers.contains { orphanSelection.contains($0.path) } || dockPaths.contains(o.path) }.map(\.name)
        let q = quarantine
        let entries = chosen.map { ($0.path, $0.size) }
        let report = await Task.detached {
            Uninstaller.run(apps: [], files: entries, dockPaths: dockPaths, quarantine: q, reason: "Restos de \(names.joined(separator: ", "))")
        }.value
        let result = (batch: report.batch, failures: report.failures)
        orphansCleaning = false
        refreshBasics()
        await loadOrphans()
        let stayed = chosen.filter { FileManager.default.fileExists(atPath: $0.path) }
        if stayed.isEmpty {
            show("Restos limpos: \(Format.bytes(result.batch?.size ?? 0)) na quarentena\(dockPaths.isEmpty ? "" : ", \(Format.plural(dockPaths.count, "ícone saiu", "ícones saíram")) do Dock").")
        } else if !report.needsFullDiskAccess.isEmpty {
            pointToFullDiskAccess(report.needsFullDiskAccess.count)
        } else {
            let blocked = stayed.contains { $0.protected } && !hasFullDiskAccess
            show("\(Format.plural(stayed.count, "resto não saiu", "restos não saíram"))\(blocked ? ": o macOS protege os contêineres; ligue o Acesso Total ao Disco" : ": \(result.failures.first?.message ?? "sem detalhe")").", error: true)
        }
    }

    // MARK: Disk map

    func scanDisk(root: String? = nil) async {
        guard !diskScanning else { return }
        if let root { diskRoot = root }
        diskPath = diskRoot
        diskSelection = []
        diskScanning = true
        diskFilesSeen = 0
        let index = DiskIndex(root: diskRoot)
        diskIndex = nil
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                diskFilesSeen = index.scannedFiles
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        await Task.detached { await index.build(cancelled: { false }) }.value
        ticker.cancel()
        diskFilesSeen = index.scannedFiles
        diskIndex = index
        diskScanning = false
        refreshDiskListing()
    }

    /// The folder on screen, read off the main thread and kept here: a folder can hold tens
    /// of thousands of entries, and reading it inside a view body froze the window.
    var diskListing: [DiskEntry] = []
    var diskListingLoading = false
    private var listingRequest = 0

    func refreshDiskListing() {
        guard let index = diskIndex else { diskListing = []; return }
        listingRequest += 1
        let request = listingRequest, path = diskPath
        diskListingLoading = true
        Task {
            let entries = await Task.detached { AppModel.listing(path, index: index) }.value
            guard request == listingRequest else { return }   // a newer folder was opened meanwhile
            diskListing = entries
            diskListingLoading = false
        }
    }

    nonisolated static func listing(_ path: String, index: DiskIndex) -> [DiskEntry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        var out: [DiskEntry] = []
        out.reserveCapacity(names.count)
        for name in names {
            let full = (path as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(full, &st) == 0 else { continue }
            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            let size = isDir ? (index.size(of: full) ?? 0) : Int64(st.st_blocks) * 512
            if size == 0 { continue }
            out.append(DiskEntry(path: full, name: name, size: size, isFolder: isDir))
        }
        return out.sorted { $0.size > $1.size }
    }

    var diskSelectedEntries: [DiskEntry] { diskListing.filter { diskSelection.contains($0.path) } }

    func diskSize(_ path: String) -> Int64 {
        _ = diskRevision
        return diskIndex?.size(of: path) ?? 0
    }

    func openDiskFolder(_ path: String) {
        diskPath = path
        diskSelection = []
        diskListing = []
        refreshDiskListing()
    }

    func toggleDiskEntry(_ entry: DiskEntry) {
        if diskSelection.contains(entry.path) { diskSelection.remove(entry.path) } else { diskSelection.insert(entry.path) }
    }

    /// Moves the ticked rows to the quarantine and fixes the measured tree in place.
    func moveDiskSelection() async {
        let chosen = diskSelectedEntries
        guard !chosen.isEmpty, !diskMoving else { return }
        diskMoving = true
        let q = quarantine
        let list = chosen.map { ($0.path, $0.size) }
        let reason = chosen.count == 1 ? "Mapa do disco: \(chosen[0].name)" : "Mapa do disco: \(chosen.count) itens de \((diskPath as NSString).lastPathComponent)"
        let result = await Task.detached { q.move(list, reason: reason) }.value
        if let index = diskIndex, let batch = result.batch {
            for item in batch.items {
                index.removed(item.original, size: item.size)
                index.added(item.stored, size: item.size)
            }
        }
        let moved = Set(result.batch?.items.map(\.original) ?? [])
        diskSelection.subtract(moved)
        diskListing.removeAll { moved.contains($0.path) }
        diskRevision += 1
        diskMoving = false
        refreshBasics()
        let bytes = result.batch?.size ?? 0
        if !result.needsFullDiskAccess.isEmpty {
            pointToFullDiskAccess(result.needsFullDiskAccess.count)
        } else if result.failures.isEmpty {
            show("\(Format.plural(moved.count, "item", "itens")) na quarentena (\(Format.bytes(bytes))). O espaço volta quando ela esvaziar.")
        } else {
            show("\(Format.plural(moved.count, "item saiu", "itens saíram")); \(Format.plural(result.failures.count, "não saiu", "não saíram")): \(result.failures[0].message)", error: true)
        }
    }

    // MARK: Startup

    func loadStartup() async {
        startupLoading = true
        let (items, bg) = await Task.detached { () -> ([StartupItem], [BackgroundApp]) in
            let items = Startup.list()
            return (items, Background.scan(startup: items))
        }.value
        startupItems = items
        backgroundApps = bg
        startupLoading = false
    }

    /// Lighter refresh for the open screen: processes only.
    func refreshBackground() async {
        let items = startupItems
        backgroundApps = await Task.detached { Background.scan(startup: items) }.value
    }

    func quitBackground(_ app: BackgroundApp) async {
        backgroundBusy.insert(app.id)
        do {
            try await Task.detached { try Background.quit(app) }.value
            let restarts = app.startupItems.contains { !$0.disabled }
            show(restarts ? "\(app.name) encerrado. Ele abre sozinho de novo: use Impedir de abrir." : "\(app.name) encerrado.")
        } catch {
            show(error.localizedDescription, error: true)
        }
        backgroundBusy.remove(app.id)
        await loadStartup()
    }

    /// Turns off what starts the app by itself, then stops it.
    func stopAutostart(_ app: BackgroundApp) async {
        backgroundBusy.insert(app.id)
        var failed: String?
        for item in app.startupItems where !item.disabled {
            do { try await Task.detached { try Startup.setEnabled(item, false) }.value } catch { failed = error.localizedDescription }
        }
        if failed == nil { try? await Task.detached { try Background.quit(app) }.value }
        backgroundBusy.remove(app.id)
        if let failed { show(failed, error: true) } else { show("\(app.name) não abre mais sozinho. Dá para religar em Abrem sozinhos.") }
        await loadStartup()
    }

    /// Opens the uninstall review for the app a background process belongs to.
    func uninstallBackground(_ app: BackgroundApp) async {
        if let installed = apps.first(where: { $0.path == app.bundlePath }) ?? AppCatalog.read(app.bundlePath) {
            if AppCatalog.isRunning(installed) == nil { try? await Task.detached { try Background.quit(app) }.value }
            await prepareUninstall([installed])
        } else {
            show("\(app.name) faz parte de outro app ou do sistema; desinstale pelo app principal.", error: true)
        }
    }

    /// Removes a startup item for good: unloaded now, its plist into the quarantine.
    func deleteStartup(_ item: StartupItem) async {
        let q = quarantine
        let size = DiskUsage.size(of: item.plist)
        let report = await Task.detached {
            Uninstaller.run(apps: [], files: [(item.plist, size)], dockPaths: [], quarantine: q, reason: "Item de inicialização: \(item.label)")
        }.value
        refreshBasics()
        if report.stayed.isEmpty {
            show("\(item.label) excluído: parado agora e guardado 7 dias na Quarentena.")
        } else {
            show(report.failures.first?.message ?? "Não deu para excluir \(item.label).", error: true)
        }
        await loadStartup()
    }

    func setStartup(_ item: StartupItem, enabled: Bool) async {
        do {
            try await Task.detached { try Startup.setEnabled(item, enabled) }.value
            show(enabled ? "\(item.label) ligado." : "\(item.label) desligado. Dá para religar aqui mesmo.")
        } catch {
            show(error.localizedDescription, error: true)
        }
        await loadStartup()
    }

    // MARK: Quarantine

    var quarantineBytes: Int64 { batches.reduce(0) { $0 + $1.size } }

    func restore(_ batch: Quarantine.Batch, item: Quarantine.Item? = nil) async {
        let q = quarantine
        let only = item.map { Set([$0.stored]) }
        do {
            let n = try await Task.detached { try q.restore(batchID: batch.id, items: only) }.value
            show(n == 1 ? "1 item devolvido ao lugar." : "\(n) itens devolvidos ao lugar.")
        } catch where error.localizedDescription == Quarantine.fullDiskAccessMessage {
            pointToFullDiskAccess(1)
        } catch {
            show(error.localizedDescription, error: true)
        }
        refreshBasics()
        // Restored apps and caches show up again in their screens.
        if batch.reason.hasPrefix("Desinstalar") { await loadApps() }
    }

    /// Bytes on their way out: staged batches the background is deleting.
    var purgingBytes: Int64 = 0
    private var purgeRunning = false

    func purge(_ batch: Quarantine.Batch) {
        guard quarantine.stage(batchID: batch.id) else { show("Não deu para apagar este lote.", error: true); return }
        refreshBasics()
        Task { await finishPurging(announce: true) }
    }

    func purgeAll() {
        for b in batches { quarantine.stage(batchID: b.id) }
        refreshBasics()
        Task { await finishPurging(announce: true) }
    }

    /// Deletes what is staged, off the main thread; the window stays free meanwhile.
    func finishPurging(announce: Bool) async {
        purgingBytes = quarantine.purgingBytes()
        guard !purgeRunning, purgingBytes > 0 else { return }
        purgeRunning = true
        let total = purgingBytes
        if announce { show("Apagando \(Format.bytes(total)) em segundo plano. Pode continuar usando o Cleaner.") }
        let q = quarantine
        await Task.detached(priority: .utility) { q.finishPurges() }.value
        purgeRunning = false
        purgingBytes = quarantine.purgingBytes()
        refreshBasics()
        if announce { show("\(Format.bytes(total)) apagados de vez e devolvidos ao disco.") }
        // Something staged while this ran gets its own pass.
        if purgingBytes > 0 { await finishPurging(announce: announce) }
    }

}
