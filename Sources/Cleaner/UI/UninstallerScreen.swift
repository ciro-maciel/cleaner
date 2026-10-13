import SwiftUI
import AppKit

struct UninstallerScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page {
            PageHeader(crumb: "Cleaner", title: "Desinstalador",
                       subtitle: "Arrastar para a Lixeira deixa preferências, caches e contêineres para trás. Marque os apps, revise o que cada um espalhou e tire tudo de uma vez. Volta se você mudar de ideia.") {
                SearchField(text: $model.appQuery)
                Button { Task { await model.loadApps() } } label: {
                    ButtonLabel(title: model.appsLoading ? "Medindo…" : "Atualizar", icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.appsLoading)
                Button { Task { await model.prepareUninstall() } } label: {
                    ButtonLabel(title: model.appSelection.isEmpty ? "Marque os apps" : "Revisar \(Format.plural(model.appSelection.count, "app", "apps"))",
                                icon: "package", color: .white)
                }
                .buttonStyle(ZenButtonStyle(kind: .primary))
                .disabled(model.appSelection.isEmpty)
            }

            if model.apps.isEmpty {
                if model.appsLoading {
                    VStack(spacing: 16) {
                        ScanningAnimation(size: 200)
                        Text("Listando os apps…").zenLabel(11, color: Zen.gray5)
                    }.frame(maxWidth: .infinity).padding(.vertical, 56)
                } else {
                    EmptyState(illustration: "uninstall", title: "Lista vazia",
                               subtitle: "Listamos os apps de Aplicativos e da sua pasta de Aplicativos, com o tamanho de cada um.") {
                        Button { Task { await model.loadApps() } } label: { ButtonLabel(title: "Listar apps", icon: "apps", color: .white) }
                            .buttonStyle(ZenButtonStyle(kind: .primary))
                    }
                }
            } else {
                if !model.orphans.isEmpty { OrphanSection().padding(.bottom, 40) }
                if !model.appSelection.isEmpty {
                    Text("\(Format.plural(model.appSelection.count, "app marcado", "apps marcados")) · \(Format.bytes(model.selectedAppsBytes)) sem contar os restos")
                        .zenData(13, color: Zen.gray9).padding(.bottom, 12)
                }
                list
                Text("Clique na linha para marcar. Tamanhos medidos no disco. Apps da App Store e do sistema pedem a senha de administrador para sair. O macOS e o Safari não aparecem: são parte do sistema.")
                    .zenNote().padding(.top, 16)
            }
        }
        .task { if model.apps.isEmpty && !model.appsLoading { await model.loadApps() } }
    }

    private var list: some View {
        let apps = model.filteredApps
        let marked = apps.filter { model.appSelection.contains($0.path) }.count
        let state: CheckBox.State = marked == 0 ? .off : (marked == apps.count ? .on : .mixed)
        return TableCard {
            HStack(spacing: 12) {
                Button {
                    if state == .on { apps.forEach { model.appSelection.remove($0.path) } }
                    else { apps.forEach { model.appSelection.insert($0.path) } }
                } label: { CheckBox(state: state) }
                .buttonStyle(.plain)
                .help(state == .on ? "Desmarcar todos" : "Marcar todos da lista")
                Color.clear.frame(width: 28, height: 1)
                Text("App").zenLabel(10, color: Zen.gray5).frame(maxWidth: .infinity, alignment: .leading)
                Text("Versão").zenLabel(10, color: Zen.gray5).frame(width: 110, alignment: .trailing)
                Text("Último uso").zenLabel(10, color: Zen.gray5).frame(width: 110, alignment: .trailing)
                Text("Tamanho").zenLabel(10, color: Zen.gray5).frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Zen.gray1)
            .overlay(alignment: .bottom) { Rectangle().fill(Zen.gray2).frame(height: 1) }

            if apps.isEmpty {
                VStack(spacing: 8) {
                    Text("Nenhum resultado para «\(model.appQuery)»").zenLabel(10)
                    Button("Limpar busca") { model.appQuery = "" }.buttonStyle(ZenButtonStyle(kind: .subtle, height: 30))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, app in
                AppRow(app: app)
                if i < apps.count - 1 { RowDivider() }
            }
        }
    }
}

private struct AppRow: View {
    @Environment(AppModel.self) private var model
    let app: InstalledApp

    var body: some View {
        let on = model.appSelection.contains(app.path)
        HStack(spacing: 12) {
            CheckBox(state: on ? .on : .off)
            Image(nsImage: AppIcon.image( app.path)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(app.name).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).lineLimit(1)
                    if app.fromAppStore { DotBadge(text: "App Store", color: Zen.gray5) }
                }
                Text(app.bundleID).zenData(12, color: Zen.gray5).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(app.version).zenData().lineLimit(1).frame(width: 110, alignment: .trailing)
            Text(app.lastUsed.map(Format.relative) ?? "—").zenData().frame(width: 110, alignment: .trailing)
            Group {
                if let size = app.size { Text(Format.bytes(size)).zenData() }
                else { ProgressView().controlSize(.small) }
            }
            .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(on ? Zen.gray1 : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.toggleApp(app) }
        .rowHover(!on)
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Icon(name: "search", size: 16, color: Zen.gray5)
            TextField("Buscar app", text: $text)
                .textFieldStyle(.plain)
                .font(Zen.font(13, .medium))
                .foregroundStyle(Zen.gray9)
                .frame(width: 180)
                .onExitCommand { text = "" }
        }
        .frame(height: 36)
        .overlay(alignment: .bottom) { Rectangle().fill(Zen.gray3).frame(height: 1) }
    }
}

/// The uninstall modal: every ticked app, what each one left, and one hold-to-confirm button.
struct UninstallSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let targets = model.uninstallTargets
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                if targets.count == 1, let app = targets.first {
                    Image(nsImage: AppIcon.image( app.path)).resizable().frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Desinstalar").zenLabel(10)
                    Text(targets.count == 1 ? targets[0].name : "\(targets.count) apps").zenDisplay(28).lineLimit(1)
                    Text(targets.count == 1 ? "\(targets[0].bundleID)\(targets[0].version.isEmpty ? "" : " · versão \(targets[0].version)")"
                                            : targets.map(\.name).joined(separator: ", "))
                        .zenData(12, color: Zen.gray5).lineLimit(2)
                }
                Spacer()
                IconButton(icon: "x", help: "Fechar") { model.closeUninstall() }
            }
            .padding(32)

            let open = model.runningTargets
            if !open.isEmpty {
                Banner(icon: "alert-triangle", title: open.count == 1 ? "\(open[0].name) está aberto" : "\(open.count) apps estão abertos",
                       text: "Feche antes de desinstalar, senão o app recria os arquivos na hora.") {
                    Button("Encerrar") { model.quitRunningTargets() }.buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                }
                .padding(.horizontal, 32).padding(.bottom, 16)
            }

            Text("O que sai").zenLabel(10, color: Zen.gray5).padding(.horizontal, 32).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { i, app in
                        if i > 0 { Rectangle().fill(Zen.gray3).frame(height: 1) }
                        appBlock(app)
                    }
                }
                .zenBorder()
            }
            .frame(maxHeight: 380)
            .padding(.horizontal, 32)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total").zenLabel(10, color: Zen.gray5)
                    Text(Format.bytes(model.uninstallBytes)).zenDisplay(24)
                }
                Spacer()
                if model.uninstalling {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Movendo para a quarentena…").zenData(12, color: Zen.gray6)
                    }
                } else {
                    HoldButton(title: targets.count == 1 ? "Desinstalar" : "Desinstalar \(targets.count) apps", icon: "trash") {
                        Task { await model.uninstall() }
                    }
                    .disabled(model.leftoversLoading)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 20)
            .background(Zen.gray1)
            .overlay(alignment: .top) { Rectangle().fill(Zen.gray2).frame(height: 1) }
            .padding(.top, 24)
        }
        .frame(width: 680)
        .background(Zen.gray0)
    }

    @ViewBuilder
    private func appBlock(_ app: InstalledApp) -> some View {
        let multi = model.uninstallTargets.count > 1
        line(icon: "package", title: multi ? app.name : "O app", path: app.path, size: app.size ?? 0, locked: true, on: true,
             appIcon: multi ? app.path : nil) {}
        if model.leftoversLoading {
            RowDivider()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Procurando o que o app deixou…").zenData(12, color: Zen.gray5)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
        } else if (model.leftovers[app.path] ?? []).isEmpty {
            RowDivider()
            Text("Nenhum resto encontrado nas pastas da Biblioteca\(model.hasFullDiskAccess ? "" : " (com o Acesso Total ao Disco desligado, parte delas fica oculta)").")
                .zenData(12, color: Zen.gray5)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 50).padding(.trailing, 20).padding(.vertical, 10)
        }
        ForEach(model.leftovers[app.path] ?? []) { left in
            RowDivider()
            line(icon: left.system ? "lock" : "folder", title: left.kind, path: left.path, size: left.size,
                 locked: false, on: model.leftoverSelection.contains(left.path), appIcon: nil,
                 note: left.protected && !model.hasFullDiskAccess ? "Precisa do Acesso Total ao Disco" : nil) {
                if model.leftoverSelection.contains(left.path) { model.leftoverSelection.remove(left.path) }
                else { model.leftoverSelection.insert(left.path) }
            }
        }
    }

    private func line(icon: String, title: String, path: String, size: Int64, locked: Bool, on: Bool, appIcon: String?,
                      note: String? = nil, toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if locked { Icon(name: "square-check", size: 18, color: Zen.gray4) }
            else { Button(action: toggle) { CheckBox(state: on ? .on : .off) }.buttonStyle(.plain) }
            if let appIcon {
                Image(nsImage: AppIcon.image( appIcon)).resizable().frame(width: 20, height: 20)
            } else {
                Icon(name: icon, size: 16, color: Zen.gray5).frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(title).font(Zen.font(13, locked ? .bold : .medium)).foregroundStyle(Zen.gray9)
                    if let note { DotBadge(text: note, color: Zen.red7) }
                }
                Text(Format.path(path)).zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(size)).zenData().frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(locked ? Zen.gray1 : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if !locked { toggle() } }
    }
}

/// Apps that already left (removed by Cleaner or missing behind a Dock tile) but left files or
/// a "?" in the Dock. One hold clears what is ticked.
struct OrphanSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restos de apps que já saíram").zenLabel(10, color: Zen.gray5)
                    Text("Apps que não estão mais no disco, mas deixaram arquivos ou um ícone com ? no Dock.")
                        .zenData(12, color: Zen.gray6)
                }
                Spacer()
                if model.orphansCleaning {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Limpando…").zenData(12, color: Zen.gray6) }
                } else {
                    HoldButton(title: model.orphanSelection.isEmpty ? "Nada marcado" : "Limpar restos", icon: "trash", kind: .secondary) {
                        Task { await model.cleanOrphans() }
                    }
                    .disabled(model.orphanSelection.isEmpty)
                }
            }
            TableCard {
                ForEach(Array(model.orphans.enumerated()), id: \.element.id) { i, orphan in
                    if i > 0 { Rectangle().fill(Zen.gray3).frame(height: 1) }
                    HStack(spacing: 12) {
                        Icon(name: "package", size: 16, color: Zen.gray5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(orphan.name).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9)
                            Text(orphan.bundleID).zenData(12, color: Zen.gray5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.bytes(orphan.size)).zenData().frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Zen.gray1)
                    if orphan.inDock {
                        RowDivider()
                        row(key: orphan.dockKey, icon: "apps", title: "Ícone no Dock", detail: "\(Format.path(orphan.path)) não existe mais", size: nil, note: nil)
                    }
                    ForEach(orphan.leftovers) { left in
                        RowDivider()
                        row(key: left.path, icon: left.system ? "lock" : "folder", title: left.kind, detail: Format.path(left.path), size: left.size,
                            note: left.protected && !model.hasFullDiskAccess ? "Precisa do Acesso Total ao Disco" : nil)
                    }
                }
            }
        }
    }

    private func row(key: String, icon: String, title: String, detail: String, size: Int64?, note: String?) -> some View {
        let on = model.orphanSelection.contains(key)
        return HStack(spacing: 12) {
            CheckBox(state: on ? .on : .off)
            Icon(name: icon, size: 16, color: Zen.gray5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(title).zenData(13, color: Zen.gray9)
                    if let note { DotBadge(text: note, color: Zen.red7) }
                }
                Text(detail).zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(size.map(Format.bytes) ?? "").zenData().frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .contentShape(Rectangle())
        .onTapGesture {
            if on { model.orphanSelection.remove(key) } else { model.orphanSelection.insert(key) }
        }
    }
}
