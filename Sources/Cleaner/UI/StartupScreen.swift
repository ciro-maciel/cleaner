import SwiftUI
import AppKit

struct StartupScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Segundo plano",
                       subtitle: "Apps que rodam sem janela e programas que o macOS liga sozinho. Encerre, impeça de abrir sozinho ou exclua; o que sai fica 7 dias na Quarentena.") {
                Button { Permissions.openLoginItemsSettings() } label: { ButtonLabel(title: "Itens de início", icon: "settings") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                Button { Task { await model.loadStartup() } } label: { ButtonLabel(title: "Atualizar", icon: "refresh") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                    .disabled(model.startupLoading)
            }

            BackgroundSection().padding(.bottom, 40)

            Text("Abrem sozinhos").zenLabel(10, color: Zen.gray5).padding(.bottom, 12)
            if model.startupItems.isEmpty {
                if model.startupLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 56)
                } else {
                    EmptyState(illustration: "startup", title: "Nada liga sozinho",
                               subtitle: "Nenhum agente ou serviço de terceiros nas pastas de inicialização.")
                }
            } else {
                let on = model.startupItems.filter { !$0.disabled }.count
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ligados").zenLabel(11)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Format.count(on)).zenDisplay(72)
                            Text("de \(model.startupItems.count)").font(Zen.font(22, .black)).foregroundStyle(Zen.gray9)
                        }
                        Text("Contados nas pastas LaunchAgents e LaunchDaemons do usuário e do sistema. Os itens que os apps registram pelo macOS ficam em Ajustes, em Itens de início.")
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
                            TableHeader(columns: [("Item", nil), ("Situação", 100), ("", 216)])
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                StartupRow(item: item)
                                if i < items.count - 1 { RowDivider() }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
                Text("Itens do sistema pedem a senha de administrador para ligar ou desligar.").zenNote()
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
        case .user: return "Só para você · ~/Library/LaunchAgents"
        case .systemAgent: return "Para todos os usuários · /Library/LaunchAgents"
        case .systemDaemon: return "Serviços do sistema · /Library/LaunchDaemons"
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
            DotBadge(text: item.disabled ? "Desligado" : (item.running ? "Rodando" : "Ligado"),
                     color: item.disabled ? Zen.gray3 : Zen.gray9)
                .fixedSize()
                .frame(width: 100, alignment: .trailing)
            HStack(spacing: 8) {
                Button {
                    busy = true
                    Task { await model.setStartup(item, enabled: item.disabled); busy = false }
                } label: {
                    ButtonLabel(title: busy ? "…" : (item.disabled ? "Ligar" : "Desligar"), icon: "power")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                .disabled(busy)
                .fixedSize()
                HoldButton(title: "Excluir", icon: "trash", kind: .danger, height: 30) {
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
            Text("Rodando agora, sem janela").zenLabel(10, color: Zen.gray5)
            TableCard {
                TableHeader(columns: [("App", nil), ("CPU", 70), ("Memória", 90), ("", 360)])
                if model.backgroundApps.isEmpty {
                    Text(model.startupLoading ? "Lendo os processos…" : "Nenhum app de terceiros rodando escondido agora.")
                        .zenData(13, color: Zen.gray5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16)
                }
                ForEach(Array(model.backgroundApps.enumerated()), id: \.element.id) { i, app in
                    BackgroundRow(app: app)
                    if i < model.backgroundApps.count - 1 { RowDivider() }
                }
            }
            Text("Apps de terceiros com processos rodando e nenhuma janela no Dock: atualizadores, agentes da barra de menus, ajudantes de apps fechados. Encerrar vale até o app abrir de novo; Impedir de abrir desliga o que o liga sozinho.")
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
                    if autostart { DotBadge(text: "Abre sozinho", color: Zen.gray9) }
                    if app.rootOwned { DotBadge(text: "Sistema", color: Zen.gray5) }
                }
                Text("\(Format.plural(app.pids.count, "processo", "processos")): \(app.processNames.prefix(3).joined(separator: ", "))")
                    .zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Format.decimal(app.cpu))%").zenData().monospacedDigit().frame(width: 70, alignment: .trailing)
            Text(Format.bytes(app.memory)).zenData().frame(width: 90, alignment: .trailing)
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button { Task { await model.quitBackground(app) } } label: { ButtonLabel(title: "Encerrar", icon: "player-stop") }
                        .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30)).fixedSize()
                    if autostart {
                        Button { Task { await model.stopAutostart(app) } } label: { ButtonLabel(title: "Impedir", icon: "power") }
                            .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30)).fixedSize()
                            .help("Desliga o que faz \(app.name) abrir sozinho e encerra agora")
                    }
                    Button { Task { await model.uninstallBackground(app) } } label: { ButtonLabel(title: "Desinstalar", icon: "trash", color: Zen.red7) }
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
                HoldButton(title: "Sair", icon: "power", kind: .secondary, height: 30) {}
                HoldButton(title: "Sair", icon: "power", kind: .secondary, height: 30, previewHint: true) {}
                HoldButton(title: "Excluir", icon: "trash", kind: .danger, height: 30) {}
                HoldButton(title: "Excluir", icon: "trash", kind: .danger, height: 30, previewHint: true) {}
                HoldButton(title: "Mover 17,8 GB", icon: "trash") {}
                HoldButton(title: "Mover 17,8 GB", icon: "trash", previewHint: true) {}
            }
            TableCard {
                TableHeader(columns: [("App", nil), ("CPU", 70), ("Memória", 90), ("", 360)])
                BackgroundRow(app: app)
            }
            TableCard {
                TableHeader(columns: [("Item", nil), ("Situação", 100), ("", 216)])
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
