import SwiftUI
import AppKit

struct CleanupScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Limpeza",
                       subtitle: "Só entra o que as regras públicas do Cleaner nomeiam: pastas que os apps recriam sozinhos. Revise, desmarque o que quiser manter e mova para a quarentena.") {
                Button { Task { await model.scanCleanup() } } label: {
                    ButtonLabel(title: model.cleanupScanning ? "Varrendo…" : "Varrer de novo", icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.cleanupScanning || model.cleanupGroups == nil)

                HoldButton(title: model.cleanupSelectedCount == 0 ? "Nada marcado" : "Mover \(Format.bytes(model.cleanupSelectedBytes))",
                           icon: "trash") { Task { await model.cleanSelected() } }
                    .disabled(model.cleanupSelectedCount == 0 || model.cleanupScanning)
            }

            if model.cleanupScanning && model.cleanupGroups == nil {
                VStack(spacing: 16) {
                    ScanningAnimation(size: 200)
                    Text("Medindo as pastas das regras…").zenLabel(11, color: Zen.gray5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 56)
            } else if let groups = model.cleanupGroups {
                if groups.isEmpty {
                    EmptyState(illustration: "done", title: "Nada para limpar",
                               subtitle: "Nenhuma regra encontrou o que tirar. Volte daqui a alguns dias: caches crescem com o uso.")
                } else {
                    summary(groups).padding(.bottom, 32)
                    table(groups)
                    Text("Segure o botão por 3 segundos para mover. Tudo fica 7 dias na Quarentena e volta ao lugar com um clique. Itens de apps abertos começam desmarcados.")
                        .zenNote().padding(.top, 16)
                }
            } else {
                EmptyState(illustration: "cleanup", title: "Ainda não varremos",
                           subtitle: "A varredura só lê. Ela mede caches, registros, Lixeira, instaladores velhos e caches de desenvolvimento.") {
                    Button { Task { await model.scanCleanup() } } label: { ButtonLabel(title: "Varrer agora", icon: "scan", color: .white) }
                        .buttonStyle(ZenButtonStyle(kind: .primary))
                }
            }
        }
    }

    private func summary(_ groups: [CleanupGroup]) -> some View {
        HStack(alignment: .bottom, spacing: 48) {
            BigMetric(label: "Marcado para sair", bytes: model.cleanupSelectedBytes,
                      note: "\(Format.plural(model.cleanupSelectedCount, "item marcado", "itens marcados")) de \(Format.count(groups.flatMap(\.items).count)), em \(Format.plural(groups.count, "regra", "regras")). Total encontrado: \(Format.bytes(model.cleanupTotal)).",
                      size: 72)
            Spacer()
            if let at = model.cleanupScannedAt {
                Text("Varrido \(Format.date(at))").zenData(12, color: Zen.gray5)
            }
        }
    }

    private func table(_ groups: [CleanupGroup]) -> some View {
        TableCard {
            TableHeader(columns: [("Regra", nil), ("Itens", 80), ("Tamanho", 100)], leading: 30)
            ForEach(Array(groups.enumerated()), id: \.element.id) { i, group in
                GroupRow(group: group)
                if model.expandedGroups.contains(group.id) {
                    ForEach(group.items) { item in
                        RowDivider()
                        ItemRow(item: item)
                    }
                }
                if i < groups.count - 1 { RowDivider() }
            }
        }
    }
}

private struct GroupRow: View {
    @Environment(AppModel.self) private var model
    let group: CleanupGroup

    var body: some View {
        let expanded = model.expandedGroups.contains(group.id)
        HStack(alignment: .center, spacing: 12) {
            Button { model.toggleGroup(group) } label: { CheckBox(state: model.groupState(group)) }
                .buttonStyle(.plain).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(group.rule.title).font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                    if group.rule.risk == .medium { DotBadge(text: "Revise", color: Zen.gray5) }
                }
                Text(group.rule.why).zenData(12, color: Zen.gray6).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.count(group.items.count)).zenData().frame(width: 80, alignment: .trailing)
            Text(Format.bytes(group.size)).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).frame(width: 100, alignment: .trailing)
            Icon(name: expanded ? "chevron-down" : "chevron-right", size: 14, color: Zen.gray5)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded { model.expandedGroups.remove(group.id) } else { model.expandedGroups.insert(group.id) }
        }
        .rowHover()
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanupItem

    var body: some View {
        let on = model.cleanupSelection.contains(item.path)
        HStack(spacing: 12) {
            Color.clear.frame(width: 18)
            Button { model.toggleItem(item) } label: { CheckBox(state: on ? .on : .off) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(item.name).zenData(13, color: Zen.gray9).lineLimit(1)
                    if let hold = item.hold { DotBadge(text: hold, color: Zen.gray5) }
                }
                Text(Format.path(item.path)).zenData(12, color: Zen.gray5).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(icon: "external-link", help: "Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            Text(Format.bytes(item.size)).zenData().frame(width: 100, alignment: .trailing)
            Color.clear.frame(width: 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Zen.gray1.opacity(0.5))
        .contentShape(Rectangle())
        .onTapGesture { model.toggleItem(item) }
    }
}
