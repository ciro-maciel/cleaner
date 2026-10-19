import SwiftUI
import AppKit

struct StartupScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: L("Background"),
                       subtitle: L("Apps running without a window and programs macOS starts by itself. Quit them, block them from starting, or delete them; whatever is removed stays 7 days in the Quarantine.")) {
                Button { Permissions.openLoginItemsSettings() } label: { ButtonLabel(title: L("Login Items"), icon: "settings") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                Button { Task { await model.loadStartup() } } label: { ButtonLabel(title: L("Refresh"), icon: "refresh") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                    .disabled(model.startupLoading)
            }

            BackgroundSection().padding(.bottom, 40)

            Text(L("Start automatically")).zenLabel(10, color: Zen.gray5).padding(.bottom, 12)
            if model.startupItems.isEmpty {
                if model.startupLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 56)
                } else {
                    EmptyState(illustration: "startup", title: L("Nothing starts by itself"),
                               subtitle: L("No third-party agent or service in the startup folders."))
                }
            } else {
                let on = model.startupItems.filter { !$0.disabled }.count
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Enabled")).zenLabel(11)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Format.count(on)).zenDisplay(72)
                            Text(L("of %@", Format.count(model.startupItems.count))).font(Zen.font(22, .black)).foregroundStyle(Zen.gray9)
                        }
                        Text(L("Counted in the user's and the system's LaunchAgents and LaunchDaemons folders. Items that apps register through macOS are in System Settings, under Login Items."))
                            .zenNote().frame(maxWidth: 520, alignment: .leading)
                    }
                    Spacer()
                    Illustration(name: "startup", size: 150)
                }
                .padding(.bottom, 32)

                ForEach([StartupItem.Domain.user, .systemAgent, .systemDaemon], id: \.self) { domain in
                    let items = model.startupItems.filter { $0.domain == domain }
                    if !items.isEmpty {
                        Text(title(domain)).zenLabel(10, color: Zen.gray5).padding(.bottom, 8)
                        TableCard {
                            TableHeader(columns: [(L("Item"), nil), (L("Status"), 100), ("", 216)])
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                StartupRow(item: item)
                                if i < items.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
                Text(L("System items ask for the administrator password to turn on or off.")).zenNote()
            }
        }
        .task {
            if model.startupItems.isEmpty && !model.startupLoading { await model.loadStartup() }
            // While the screen is open, the running list follows reality every 5 seconds.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { await model.refreshBackground() }
            }
        }
    }

    private func title(_ d: StartupItem.Domain) -> String {
        switch d {
        case .user: return L("Just for you · %@", "~/Library/LaunchAgents")
        case .systemAgent: return L("For all users · %@", "/Library/LaunchAgents")
        case .systemDaemon: return L("System services · %@", "/Library/LaunchDaemons")
        }
    }
}

struct StartupRow: View {
    @Environment(AppModel.self) private var model
    let item: StartupItem
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            Icon(name: item.domain == .user ? "rocket" : "lock", size: 16, color: Zen.gray5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).font(Zen.font(13, .bold)).foregroundStyle(item.disabled ? Zen.gray5 : Zen.gray9).lineLimit(1)
                Text(item.program.isEmpty ? Format.path(item.plist) : Format.path(item.program))
                    .zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DotBadge(text: item.disabled ? L("Off") : (item.running ? L("Running") : L("On")),
                     color: item.disabled ? Zen.gray3 : Zen.gray9)
                .fixedSize()
                .frame(width: 100, alignment: .trailing)
            HStack(spacing: 8) {
                Button {
                    busy = true
                    Task { await model.setStartup(item, enabled: item.disabled); busy = false }
                } label: {
                    ButtonLabel(title: busy ? "…" : (item.disabled ? L("Turn On") : L("Turn Off")), icon: "power")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                .disabled(busy)
                .fixedSize()
                HoldButton(title: L("Delete [startup item]"), icon: "trash", kind: .danger, height: 30) {
                    busy = true
                    Task { await model.deleteStartup(item); busy = false }
                }
                .disabled(busy)
                .fixedSize()
            }
            .fixedSize()
            .frame(width: 216, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .rowHover()
    }
}

/// Apps running with no window: what they cost now, and the three ways out.
struct BackgroundSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Running now, without a window")).zenLabel(10, color: Zen.gray5)
            TableCard {
                TableHeader(columns: [(L("App"), nil), ("CPU", 70), (L("Memory"), 90), ("", 360)])
                if model.backgroundApps.isEmpty {
                    Text(model.startupLoading ? L("Reading processes…") : L("No third-party app running hidden right now."))
                        .zenData(13, color: Zen.gray5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16)
                }
                ForEach(Array(model.backgroundApps.enumerated()), id: \.element.id) { i, app in
                    BackgroundRow(app: app)
                    if i < model.backgroundApps.count - 1 { RowDivider() }
                }
            }
            Text(L("Third-party apps with processes running and no window in the Dock: updaters, menu bar agents, helpers of closed apps. Quit lasts until the app opens again; Block turns off what starts it by itself."))
                .zenNote()
        }
    }
}

struct BackgroundRow: View {
    @Environment(AppModel.self) private var model
    let app: BackgroundApp

    var body: some View {
        let busy = model.backgroundBusy.contains(app.id)
        let autostart = app.startupItems.contains { !$0.disabled }
        HStack(spacing: 12) {
            Image(nsImage: AppIcon.image(app.bundlePath)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(app.name).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).lineLimit(1)
                    if autostart { DotBadge(text: L("Starts by itself"), color: Zen.gray9) }
                    if app.rootOwned { DotBadge(text: L("System"), color: Zen.gray5) }
                }
                Text("\(Format.plural(app.pids.count, L("process"), L("processes"))): \(app.processNames.prefix(3).joined(separator: ", "))")
                    .zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Format.decimal(app.cpu))%").zenData().monospacedDigit().frame(width: 70, alignment: .trailing)
            Text(Format.bytes(app.memory)).zenData().frame(width: 90, alignment: .trailing)
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await model.quitBackground(app) } } label: { ButtonLabel(title: L("Quit"), icon: "player-stop") }
                        .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30)).fixedSize()
                    if autostart {
                        Button { Task { await model.stopAutostart(app) } } label: { ButtonLabel(title: L("Block"), icon: "power") }
                            .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30)).fixedSize()
                            .help(L("Turns off what makes %@ open by itself and quits it now", app.name))
                    }
                    Button { Task { await model.uninstallBackground(app) } } label: { ButtonLabel(title: L("Uninstall"), icon: "trash", color: Zen.red7) }
                        .buttonStyle(ZenButtonStyle(kind: .danger, height: 30)).fixedSize()
                }
            }
            .fixedSize()
            .frame(width: 360, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .rowHover()
    }
}

/// `Cleaner --rows-preview <dir>`: draws the Background screen's rows with every state into a
/// PNG at the window's content width, to check columns without opening the app.
@MainActor
enum RowsPreview {
    static func run(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func item(_ label: String, running: Bool, disabled: Bool) -> StartupItem {
            var i = StartupItem(label: label, plist: NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist",
                                program: "/Applications/Speech to Text.app/Contents/MacOS/speech-to-text",
                                domain: .user, runAtLoad: true, disabled: disabled, loaded: !disabled)
            i.running = running
            return i
        }
        let app = BackgroundApp(bundlePath: "/Applications/Google Chrome.app", name: "Google Updater", bundleID: "com.google.GoogleUpdater",
                                pids: [1, 2, 3], processNames: ["GoogleUpdater", "launcher", "ksfetch"], cpu: 0.4, memory: 48_000_000,
                                rootOwned: true, startupItems: [item("com.google.GoogleUpdater.wake", running: true, disabled: false)])
        let view = VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                HoldButton(title: L("Quit [app]"), icon: "power", kind: .secondary, height: 30) {}
                HoldButton(title: L("Quit [app]"), icon: "power", kind: .secondary, height: 30, previewHint: true) {}
                HoldButton(title: L("Delete [startup item]"), icon: "trash", kind: .danger, height: 30) {}
                HoldButton(title: L("Delete [startup item]"), icon: "trash", kind: .danger, height: 30, previewHint: true) {}
                HoldButton(title: L("Move %@", Format.bytes(17_800_000_000)), icon: "trash") {}
                HoldButton(title: L("Move %@", Format.bytes(17_800_000_000)), icon: "trash", previewHint: true) {}
            }
            TableCard {
                TableHeader(columns: [(L("App"), nil), ("CPU", 70), (L("Memory"), 90), ("", 360)])
                BackgroundRow(app: app)
            }
            TableCard {
                TableHeader(columns: [(L("Item"), nil), (L("Status"), 100), ("", 216)])
                StartupRow(item: item("click.ciromaciel.speech-to-text", running: true, disabled: false))
                RowDivider()
                StartupRow(item: item("com.example.sync-agent", running: false, disabled: false))
                RowDivider()
                StartupRow(item: item("com.example.backup.daily", running: false, disabled: true))
            }
        }
        .padding(24)
        .frame(width: 1140 - 48 * 2 + 48)   // 1440 window − 300 sidebar, minus page padding
        .background(Zen.gray0)
        .environment(AppModel.shared)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("rows.png"))
            print("rows: \(Int(img.size.width)) × \(Int(img.size.height)) pt")
        }
    }
}
