import SwiftUI
import AppKit

struct QuarantineScreen: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = Set<String>()

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Quarentena",
                       subtitle: "Tudo o que o Cleaner tira do lugar fica aqui por 7 dias, com o caminho de onde veio. Devolva com um clique; depois do prazo, some de vez.") {
                if !model.batches.isEmpty {
                    HoldButton(title: "Esvaziar agora", icon: "trash", kind: .danger) { model.purgeAll() }
                }
            }

            if model.purgingBytes > 0 {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Apagando \(Format.bytes(model.purgingBytes)) em segundo plano. Pode continuar usando o Cleaner.")
                        .zenData(13, color: Zen.gray9)
                }
                .padding(.bottom, 24)
            }
            if model.batches.isEmpty {
                EmptyState(illustration: "quarantine", title: "Quarentena vazia",
                           subtitle: "Quando você limpar, desinstalar ou tirar algo pelo Mapa do disco, os itens esperam aqui 7 dias antes de sumir.")
            } else {
                HStack(alignment: .bottom) {
                    BigMetric(label: "Guardado", bytes: model.quarantineBytes,
                              note: "Em \(Format.plural(model.batches.count, "lote", "lotes")). Esse espaço volta para o disco quando cada lote vence ou quando você esvazia.",
                              size: 72)
                    Spacer()
                    Illustration(name: "quarantine", size: 150)
                }
                .padding(.bottom, 32)

                TableCard {
                    TableHeader(columns: [("Lote", nil), ("Itens", 70), ("Tamanho", 100), ("Some em", 100), ("", 196)])
                    ForEach(Array(model.batches.enumerated()), id: \.element.id) { i, batch in
                        BatchRow(batch: batch, expanded: expanded.contains(batch.id)) {
                            if expanded.contains(batch.id) { expanded.remove(batch.id) } else { expanded.insert(batch.id) }
                        }
                        if expanded.contains(batch.id) {
                            ForEach(batch.activeItems) { item in
                                RowDivider()
                                QuarantineItemRow(batch: batch, item: item)
                            }
                        }
                        if i < model.batches.count - 1 { RowDivider() }
                    }
                }
                Text("Esvaziar apaga de vez e não tem volta: segure 3 segundos. Lotes vencidos são apagados quando o Cleaner abre.")
                    .zenNote().padding(.top, 16)
            }
        }
        .onAppear { model.refreshBasics() }
    }
}

private struct BatchRow: View {
    @Environment(AppModel.self) private var model
    let batch: Quarantine.Batch
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Icon(name: expanded ? "chevron-down" : "chevron-right", size: 14, color: Zen.gray5)
            VStack(alignment: .leading, spacing: 2) {
                Text(batch.reason).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).lineLimit(1)
                Text(Format.date(batch.createdAt)).zenData(12, color: Zen.gray5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.count(batch.activeItems.count)).zenData().frame(width: 70, alignment: .trailing)
            Text(Format.bytes(batch.size)).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).frame(width: 100, alignment: .trailing)
            Text(daysLeft).zenData().frame(width: 100, alignment: .trailing)
            HStack(spacing: 8) {
                Button { Task { await model.restore(batch) } } label: { ButtonLabel(title: "Devolver", icon: "arrow-back-up") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                HoldButton(title: "Apagar", icon: nil, kind: .danger, height: 30) { model.purge(batch) }
            }
            .frame(width: 196, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .rowHover()
    }

    private var daysLeft: String {
        let left = batch.expiresAt.timeIntervalSinceNow / 86_400
        if left < 1 { return "hoje" }
        let d = Int(left.rounded(.up))
        return d == 1 ? "1 dia" : "\(d) dias"
    }
}

private struct QuarantineItemRow: View {
    @Environment(AppModel.self) private var model
    let batch: Quarantine.Batch
    let item: Quarantine.Item

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text((item.original as NSString).lastPathComponent).zenData(13, color: Zen.gray9).lineLimit(1)
                Text("veio de \(Format.path((item.original as NSString).deletingLastPathComponent))").zenData(12, color: Zen.gray5)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(item.size)).zenData().frame(width: 100, alignment: .trailing)
            IconButton(icon: "external-link", help: "Mostrar no Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.stored)])
            }
            IconButton(icon: "arrow-back-up", help: "Devolver este item") { Task { await model.restore(batch, item: item) } }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Zen.gray1.opacity(0.5))
    }
}
