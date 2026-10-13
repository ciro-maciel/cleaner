import SwiftUI
import AppKit

struct CleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        MonitorSettings.register()
        Zen.registerFonts()
        // The design system is light-only until 12-modo-escuro.md is approved.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    /// The scene reads no changing state on purpose. The main window and the menu bar item are
    /// AppKit's (MainWindow, StatusItem): a SwiftUI MenuBarExtra with an isInserted binding
    /// and a live image re-evaluated the whole scene in a loop (beach ball, memory climbing).
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Janela do Cleaner") { MainWindow.show() }.keyboardShortcut("0")
                }
                CommandMenu("Varredura") {
                    Button("Varrer o Mac") { Task { await AppModel.shared.scanEverything() } }.keyboardShortcut("r")
                }
            }
    }
}

/// The menu bar item: the monitor strip as its image, the panel in a popover.
@MainActor
final class StatusItem: NSObject {
    static let shared = StatusItem()
    private var item: NSStatusItem?
    private let popover = NSPopover()

    func sync() {
        let enabled = UserDefaults.standard.bool(forKey: MonitorSettings.enabledKey)
        if enabled && item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(toggle)
            item.button?.imagePosition = .imageOnly
            self.item = item
            setImage(SystemMonitor.shared.menuImage)
        } else if !enabled, let item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func setImage(_ image: NSImage) {
        item?.button?.image = image
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.behavior = .transient
        // Light like the rest of the app; under a dark menu bar the panel would inherit dark
        // and paint template icons white on white.
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = NSHostingController(rootView: MenuPanel()
            .environment(AppModel.shared)
            .environment(SystemMonitor.shared))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() { popover.performClose(nil) }
}

/// The one main window: created on launch, brought back from the Dock or the menu bar panel.
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static let watcher = Watcher()

    static var current: NSWindow? { window }

    static var menuBarOn: Bool { UserDefaults.standard.bool(forKey: MonitorSettings.enabledKey) }

    /// With the menu bar item on, Cleaner lives there when its window is away: no Dock icon.
    final class Watcher: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            if MainWindow.menuBarOn { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// ⌘Q with the menu bar item on: the window goes, Cleaner stays in the menu bar.
    static func hideToMenuBar() {
        window?.orderOut(nil)
        StatusItem.shared.close()
        NSApp.setActivationPolicy(.accessory)
    }

    /// With the menu bar item on, Cleaner never shows in the Dock, window open or not (the Ciro,
    /// 10/10/2026: "deixe só no menu bar"). Without it, the Dock is the way back to the window.
    static func show() {
        NSApp.setActivationPolicy(menuBarOn ? .accessory : .regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = RootView()
            .environment(AppModel.shared)
            .environment(SystemMonitor.shared)
            .frame(minWidth: 1180, minHeight: 720)
            .task { await Screenshots.runIfAsked(AppModel.shared) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Cleaner"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.identifier = NSUserInterfaceItemIdentifier("main")
        w.delegate = watcher
        w.contentView = NSHostingView(rootView: root)
        w.contentMinSize = NSSize(width: 1180, height: 720)
        if !w.setFrameUsingName("CleanerMain") { w.center() }
        w.setFrameAutosaveName("CleanerMain")
        window = w
        w.makeKeyAndOrderFront(nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var mainWindow: NSWindow? { MainActor.assumeIsolated { MainWindow.current } }

    /// Set by the panel's Sair (held 3 s): the one way, besides the system, to really quit.
    static var allowQuit = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.allowQuit || !MainActor.assumeIsolated({ MainWindow.menuBarOn }) || systemIsQuitting() { return .terminateNow }
        MainActor.assumeIsolated { MainWindow.hideToMenuBar() }
        return .terminateCancel
    }

    /// Log out, restart and shut down send a quit event with a reason; never hold those up.
    private func systemIsQuitting() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication else { return false }
        return event.attributeDescriptor(forKeyword: kAEQuitReason) != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Debug.log("didFinishLaunching")
        Debug.startWatchdog()
        MainActor.assumeIsolated {
            SystemMonitor.shared.start()
            StatusItem.shared.sync()
            MainWindow.show()
            // Reading is free of risk: measure everything at launch so the overview opens
            // with numbers. Screenshot runs drive their own scans.
            if !CommandLine.arguments.contains("--screenshots") {
                Task { await AppModel.shared.scanEverything() }
            }
        }
        Debug.log("window shown: \(MainWindow.current != nil)")
    }

    /// Clicking the Dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MainWindow.show() }
        return true
    }

    /// With the menu bar item on, closing the window keeps Cleaner running there.
    func applicationWillTerminate(_ notification: Notification) { Debug.log("willTerminate") }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: MonitorSettings.enabledKey)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        // Coming back from System Settings: Full Disk Access may have changed.
        NotificationCenter.default.post(name: .cleanerBecameActive, object: nil)
    }
}

extension Notification.Name {
    static let cleanerBecameActive = Notification.Name("cleanerBecameActive")
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 300)
            Rectangle().fill(Zen.gray2).frame(width: 1)
            Group {
                switch model.screen {
                case .overview: OverviewScreen()
                case .monitor: MonitorScreen()
                case .cleanup: CleanupScreen()
                case .uninstaller: UninstallerScreen()
                case .diskmap: DiskMapScreen()
                case .startup: StartupScreen()
                case .quarantine: QuarantineScreen()
                case .settings: SettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Zen.gray0)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast).padding(.bottom, 28).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanerBecameActive)) { _ in model.refreshBasics() }
        // The status line follows System Settings by itself, second by second (15-app-mac.md).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let granted = Permissions.hasFullDiskAccess
                if granted != model.hasFullDiskAccess { model.hasFullDiskAccess = granted }
            }
        }
        .sheet(isPresented: Binding(get: { model.showUninstall }, set: { if !$0 { model.closeUninstall() } })) {
            UninstallSheet().environment(model)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window buttons, then the wordmark (28px) and who made it.
            VStack(alignment: .leading, spacing: 6) {
                Text("Cleaner").zenDisplay(28)
                MakerLink(source: "oss-cleaner-app")
            }
                .padding(.top, 52)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

            group("Ferramentas", Screen.tools).padding(.bottom, 24)
            group("Ajustes", Screen.settingsGroup)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                // The status line: when off, a click opens the exact list in System Settings.
                Button {
                    if model.hasFullDiskAccess { model.screen = .settings } else { Permissions.openFullDiskAccessSettings() }
                } label: {
                    HStack(spacing: 8) {
                        Icon(name: model.hasFullDiskAccess ? "check" : "lock", size: 14, color: model.hasFullDiskAccess ? Zen.gray6 : Zen.red7)
                        Text(model.hasFullDiskAccess ? "Acesso Total ao Disco ligado" : "Acesso Total ao Disco desligado")
                            .zenData(12, color: model.hasFullDiskAccess ? Zen.gray6 : Zen.red7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.hasFullDiskAccess ? "Ver as permissões" : "Abrir a lista do Acesso Total ao Disco nos Ajustes do Sistema")
                Text("Versão \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .zenData(12, color: Zen.gray5)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Zen.gray2).frame(height: 1) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Zen.gray0)
    }

    private func group(_ title: String, _ screens: [Screen]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).zenLabel(10).padding(.horizontal, 24).padding(.bottom, 8)
            VStack(spacing: 2) {
                ForEach(screens) { screen in
                    SidebarItem(screen: screen, active: model.screen == screen, badge: badge(screen)) {
                        model.screen = screen
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func badge(_ screen: Screen) -> String? {
        switch screen {
        case .cleanup: return model.cleanupGroups.map { _ in Format.bytes(model.cleanupTotal) }
        case .uninstaller: return model.apps.isEmpty ? nil : Format.count(model.apps.count)
        case .startup: return model.startupItems.isEmpty ? nil : Format.count(model.startupItems.count)
        case .quarantine: return model.batches.isEmpty ? nil : Format.bytes(model.quarantineBytes)
        default: return nil
        }
    }
}

/// Active: gray.9 fill, white, 800. Inactive: transparent, gray.7, 500. Radius 0.
struct SidebarItem: View {
    let screen: Screen
    let active: Bool
    let badge: String?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(name: screen.icon, size: 18, color: active ? .white : Zen.gray7)
                Text(screen.title)
                    .font(Zen.font(13, active ? .extraBold : .medium))
                    .foregroundStyle(active ? .white : Zen.gray7)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge).font(Zen.font(11, .bold)).foregroundStyle(active ? Zen.gray3 : Zen.gray5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(active ? Zen.gray9 : (hover ? Zen.gray1 : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// CLEANER_DEBUG=1 prints launch milestones to stdout and watches the main thread: any stall
/// over 300 ms is printed with the screen it happened on (what a beach ball is).
enum Debug {
    static var enabled: Bool { ProcessInfo.processInfo.environment["CLEANER_DEBUG"] == "1" }

    static func startWatchdog() {
        guard enabled else { return }
        Thread.detachNewThread {
            while true {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let stall = Date().timeIntervalSince(sent)
                if stall > 0.3 {
                    DispatchQueue.main.async {
                        log(String(format: "STALL %.2f s on %@", stall, AppModel.shared.screen.rawValue))
                    }
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    static func log(_ text: String) {
        guard ProcessInfo.processInfo.environment["CLEANER_DEBUG"] == "1" else { return }
        print("[cleaner] \(text)"); fflush(stdout)
    }
}
