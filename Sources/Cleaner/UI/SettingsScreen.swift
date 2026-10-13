import SwiftUI
import AppKit
import ServiceManagement

/// Ajustes › Geral: opening at login, the menu bar, and every permission Cleaner depends on,
/// each with its state and the button that leads to where it is solved (15-app-mac.md: "toda
/// permissão aparece"). The administrator password is explained here too: it is asked only for
/// items outside the home folder, never for what Full Disk Access unlocks.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Geral",
                       subtitle: "Como o Cleaner abre, onde ele fica e o que ele precisa do macOS para funcionar.")

            LaunchAtLoginRow().padding(.bottom, 16)
            MenuBarSettings().padding(.bottom, 40)

            Text("Permissões").zenLabel(10, color: Zen.gray5).padding(.bottom, 12)
            VStack(spacing: 0) {
                PermissionRow(
                    title: "Acesso Total ao Disco",
                    text: model.hasFullDiskAccess
                        ? "Ligado. O Cleaner mede e limpa a Lixeira, o Mail e os contêineres dos apps."
                        : "Desligado. Sem ele o macOS esconde a Lixeira, o Mail e os contêineres dos apps: a varredura fica pela metade e esses itens não saem. Em Ajustes do Sistema, ligue o Cleaner na lista.",
                    isOn: model.hasFullDiskAccess
                ) {
                    if !model.hasFullDiskAccess {
                        HStack(spacing: 8) {
                            Button { Permissions.openFullDiskAccessSettings() } label: { ButtonLabel(title: "Abrir Ajustes do Sistema", icon: "settings", color: .white) }
                                .buttonStyle(ZenButtonStyle(kind: .primary))
                            Button { Permissions.relaunch() } label: { ButtonLabel(title: "Já liguei: reabrir", icon: "refresh") }
                                .buttonStyle(ZenButtonStyle(kind: .subtle))
                                .help("O macOS pode aplicar a permissão só depois de reabrir o Cleaner")
                        }
                    }
                }
                RowDivider()
                HelperRow()
                RowDivider()
                PermissionRow(
                    title: "Senha de administrador",
                    text: "Pedida só quando você move, devolve ou apaga itens que ficam fora da sua pasta e pertencem ao sistema, ou liga e desliga um item de inicialização do sistema. Cada pedido diz o que vai fazer e com quais itens. A Lixeira, os caches e o Mail nunca pedem senha: eles dependem do Acesso Total ao Disco.",
                    isOn: nil
                ) { EmptyView() }
            }
            .zenBorder()
        }
    }
}

/// "Abrir ao ligar o Mac": the app itself as a login item (SMAppService.mainApp), off until the
/// person turns it on. macOS may ask for approval in Itens de início; the row says so.
struct LaunchAtLoginRow: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    private var isOn: Bool { status == .enabled || status == .requiresApproval }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Abrir ao ligar o Mac").font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                Text(note).zenData(12, color: error == nil ? Zen.gray6 : Zen.red7)
                if status == .requiresApproval {
                    Button { SMAppService.openSystemSettingsLoginItems() } label: { ButtonLabel(title: "Abrir Itens de início", icon: "settings") }
                        .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                HStack(spacing: 8) { CheckBox(state: isOn ? .on : .off); Text(isOn ? "Ligado" : "Desligado").zenData(13, color: Zen.gray9) }
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .zenBorder()
        .onReceive(NotificationCenter.default.publisher(for: .cleanerBecameActive)) { _ in status = SMAppService.mainApp.status }
    }

    private var note: String {
        if let error { return error }
        switch status {
        case .enabled: return "O Cleaner abre sozinho quando você entra no Mac, direto na barra de menus."
        case .requiresApproval: return "Falta aprovar o Cleaner em Ajustes do Sistema, Geral, Itens de início."
        default: return "Desligado: o Cleaner só abre quando você abrir."
        }
    }

    private func toggle() {
        error = nil
        do {
            if isOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            self.error = "O macOS não aceitou a mudança: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}

/// The privileged helper behind "Liberar memória": approved once in Itens de início.
private struct HelperRow: View {
    @State private var state = Helper.state

    var body: some View {
        PermissionRow(title: "Ajudante para liberar memória", text: text, isOn: state == .ready) {
            if state == .needsApproval {
                Button { Helper.openApproval() } label: { ButtonLabel(title: "Abrir Itens de início", icon: "settings") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanerBecameActive)) { _ in state = Helper.state }
    }

    private var text: String {
        switch state {
        case .ready: return "Aprovado. O botão Liberar, na barra de menus, devolve a memória que o macOS guarda em cache."
        case .needsApproval: return "Esperando a sua aprovação em Ajustes do Sistema, Geral, Itens de início. Só o botão Liberar depende dele."
        case .notRegistered: return "Ainda não pedido. O macOS pede a aprovação na primeira vez que você usar o botão Liberar."
        case .unavailable(let why): return "O macOS não registrou o ajudante (\(why)). O resto do Cleaner funciona sem ele."
        }
    }
}

/// One permission: its state (check or red lock, or none for an explanation) and its fix.
private struct PermissionRow<Action: View>: View {
    let title: String
    let text: String
    let isOn: Bool?
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let isOn {
                Icon(name: isOn ? "check" : "lock", size: 16, color: isOn ? Zen.gray6 : Zen.red7).padding(.top, 2)
            } else {
                Icon(name: "info-circle", size: 16, color: Zen.gray5).padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Zen.font(14, .bold)).foregroundStyle(isOn == false ? Zen.red7 : Zen.gray9)
                Text(text).zenData(12, color: Zen.gray6).fixedSize(horizontal: false, vertical: true)
                action.padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }
}
