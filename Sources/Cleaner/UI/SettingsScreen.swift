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
            PageHeader(crumb: "Cleaner", title: L("General"),
                       subtitle: L("How Cleaner opens, where it lives and what it needs from macOS to work."))

            LaunchAtLoginRow().padding(.bottom, 16)
            MenuBarSettings().padding(.bottom, 40)

            Text(L("Permissions")).zenLabel(10, color: Zen.gray5).padding(.bottom, 12)
            VStack(spacing: 0) {
                PermissionRow(
                    title: L("Full Disk Access"),
                    text: model.hasFullDiskAccess
                        ? L("On. Cleaner measures and cleans the Trash, Mail and app containers.")
                        : L("Off. Without it, macOS hides the Trash, Mail and app containers: the scan only sees half and those items cannot be removed. In System Settings, turn on Cleaner in the list."),
                    isOn: model.hasFullDiskAccess
                ) {
                    if !model.hasFullDiskAccess {
                        HStack(spacing: 8) {
                            Button { Permissions.openFullDiskAccessSettings() } label: { ButtonLabel(title: L("Open System Settings"), icon: "settings", color: .white) }
                                .buttonStyle(ZenButtonStyle(kind: .primary))
                            Button { Permissions.relaunch() } label: { ButtonLabel(title: L("Turned on: reopen"), icon: "refresh") }
                                .buttonStyle(ZenButtonStyle(kind: .subtle))
                                .help(L("macOS may apply the permission only after Cleaner reopens"))
                        }
                    }
                }
                RowDivider()
                HelperRow()
                RowDivider()
                PermissionRow(
                    title: L("Administrator password"),
                    text: L("Asked only when you move, restore or delete items that live outside your home folder and belong to the system, or turn a system startup item on or off. Each request says what it will do and to which items. The Trash, caches and Mail never ask for a password: they depend on Full Disk Access."),
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
                Text(L("Open at Login")).font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                Text(note).zenData(12, color: error == nil ? Zen.gray6 : Zen.red7)
                if status == .requiresApproval {
                    Button { SMAppService.openSystemSettingsLoginItems() } label: { ButtonLabel(title: L("Open Login Items"), icon: "settings") }
                        .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggle) {
                HStack(spacing: 8) { CheckBox(state: isOn ? .on : .off); Text(isOn ? L("On") : L("Off")).zenData(13, color: Zen.gray9) }
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
        case .enabled: return L("Cleaner opens by itself when you log in to your Mac, straight into the menu bar.")
        case .requiresApproval: return L("Cleaner still needs your approval in System Settings, General, Login Items.")
        default: return L("Off: Cleaner opens only when you open it.")
        }
    }

    private func toggle() {
        error = nil
        do {
            if isOn { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            self.error = L("macOS did not accept the change: %@", error.localizedDescription)
        }
        status = SMAppService.mainApp.status
    }
}

/// The privileged helper behind "Liberar memória": approved once in Itens de início.
private struct HelperRow: View {
    @State private var state = Helper.state

    var body: some View {
        PermissionRow(title: L("Helper to free up memory"), text: text, isOn: state == .ready) {
            if state == .needsApproval {
                Button { Helper.openApproval() } label: { ButtonLabel(title: L("Open Login Items"), icon: "settings") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cleanerBecameActive)) { _ in state = Helper.state }
    }

    private var text: String {
        switch state {
        case .ready: return L("Approved. The Free Up button in the menu bar gives back the memory macOS keeps as cache.")
        case .needsApproval: return L("Waiting for your approval in System Settings, General, Login Items. Only the Free Up button depends on it.")
        case .notRegistered: return L("Not requested yet. macOS asks for approval the first time you use the Free Up button.")
        case .unavailable(let why): return L("macOS did not register the helper (%@). The rest of Cleaner works without it.", why)
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
