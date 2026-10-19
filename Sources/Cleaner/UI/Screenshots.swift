import SwiftUI
import AppKit

/// `Cleaner --screenshots <dir> [--width 1440 --height 900]`: scans, visits every screen and
/// saves a PNG of the window for each one, then quits. For visual review before a release.
enum Screenshots {
    @MainActor
    static func runIfAsked(_ model: AppModel) async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let width = value(args, "--width") ?? 1440
        let height = value(args, "--height") ?? 900

        Debug.log("screenshots: start → \(dir.path)")
        try? await Task.sleep(for: .milliseconds(600))
        guard let window = MainWindow.current else { Debug.log("screenshots: no main window"); return }
        window.setContentSize(NSSize(width: width, height: height))
        window.center()

        // Empty states first, then the same screens with data.
        for screen in [Screen.overview, .cleanup, .diskmap, .quarantine] {
            model.screen = screen
            try? await Task.sleep(for: .milliseconds(500))
            save(window, to: dir.appendingPathComponent("0-empty-\(screen.rawValue).png"))
        }

        model.screen = .overview
        await model.scanEverything()
        Debug.log("screenshots: scanning")
        // A real but small folder, so a capture run takes under a minute.
        await model.scanDisk(root: (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches"))
        Debug.log("screenshots: scanned")
        model.expandedGroups = Set(model.cleanupGroups?.prefix(2).map(\.id) ?? [])
        try? await Task.sleep(for: .milliseconds(500))
        model.diskSelection = Set(model.diskListing.dropFirst(3).prefix(2).map(\.path))
        for (n, screen) in Screen.allCases.enumerated() {
            model.screen = screen
            try? await Task.sleep(for: .milliseconds(1500))
            save(window, to: dir.appendingPathComponent("\(n + 1)-\(screen.rawValue).png"))
        }

        let sample = Array(model.apps.filter { ($0.size ?? 0) > 0 && !$0.fromAppStore }.prefix(2))
        if !sample.isEmpty {
            model.screen = .uninstaller
            model.appSelection = Set(sample.map(\.path))
            try? await Task.sleep(for: .milliseconds(900))
            save(window, to: dir.appendingPathComponent("7-uninstaller-selected.png"))
            await model.prepareUninstall()
            try? await Task.sleep(for: .milliseconds(900))
            if let sheet = window.attachedSheet { save(sheet, to: dir.appendingPathComponent("8-uninstall-sheet.png")) }
            model.closeUninstall()
            model.appSelection = []
        }
        // The menu bar item and its panel.
        let monitor = SystemMonitor.shared
        monitor.renderMenuImage()
        if let tiff = monitor.menuImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("9-menubar-item.png"))
        }
        monitor.watchProcesses(true)
        try? await Task.sleep(for: .seconds(2))
        let panel = NSHostingView(rootView: MenuPanel().environment(model).environment(monitor))
        panel.frame = NSRect(origin: .zero, size: panel.fittingSize)
        let host = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.contentView = panel
        host.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(800))
        save(host, to: dir.appendingPathComponent("9-menubar-panel.png"))
        host.orderOut(nil)
        // With the menu bar item on, a plain quit only hides the window: a capture run must end.
        AppDelegate.allowQuit = true
        NSApp.terminate(nil)
    }

    private static func value(_ args: [String], _ key: String) -> CGFloat? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count, let v = Double(args[i + 1]) else { return nil }
        return CGFloat(v)
    }

    @MainActor
    private static func save(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { Debug.log("save: no content view"); return }
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { Debug.log("save: no bitmap, bounds \(view.bounds)"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let png = rep.representation(using: .png, properties: [:]) else { Debug.log("save: no png for \(url.lastPathComponent)"); return }
            try png.write(to: url)
            Debug.log("saved \(url.lastPathComponent) \(Int(view.bounds.width))×\(Int(view.bounds.height))")
        } catch { Debug.log("save failed \(url.lastPathComponent): \(error)") }
    }
}
