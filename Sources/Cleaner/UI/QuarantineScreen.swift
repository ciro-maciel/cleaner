import SwiftUI
import AppKit

struct QuarantineScreen: View {
    @Environment(AppModel.self) private var model
    @State private var expanded = Set<String>()

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: L("Quarantine"),
                       subtitle: L("Everything Cleaner moves stays here for 7 days, with the path it came from. Restore it with one click; after that, it is gone for good.")) {
                if !model.batches.isEmpty {
                    HoldButton(title: L("Empty Now"), icon: "trash", kind: .danger) { model.purgeAll() }
                }
            }

            if model.purgingBytes > 0 {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Deleting %@ in the background. You can keep using Cleaner.", Format.bytes(model.purgingBytes)))
                        .zenData(13, color: Zen.gray9)
                }
                .padding(.bottom, 24)
            }
            if model.batches.isEmpty {
                EmptyState(illustration: "quarantine", title: L("Quarantine is empty"),
                           subtitle: L("When you clean up, uninstall or remove something from the Disk Map, the items wait here 7 days before they are gone."))
            } else {
                HStack(alignment: .bottom) {
                    BigMetric(label: L("Kept"), bytes: model.quarantineBytes,
                              note: L("In %@. This space goes back to the disk when each batch expires or when you empty it.", Format.plural(model.batches.count, L("batch"), L("batches"))),
                              size: 72)
                    Spacer()
                    Illustration(name: "quarantine", size: 150)
                }
                .padding(.bottom, 32)

                TableCard {
                    TableHeader(columns: [(L("Batch"), nil), (L("Items"), 70), (L("Size"), 100), (L("Gone in"), 100), ("", 196)])
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
                Text(L("Emptying deletes for good and cannot be undone: hold for 3 seconds. Expired batches are deleted when Cleaner opens."))
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
                Button { Task { await model.restore(batch) } } label: { ButtonLabel(title: L("Restore"), icon: "arrow-back-up") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                HoldButton(title: L("Delete"), icon: nil, kind: .danger, height: 30) { model.purge(batch) }
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
        if left < 1 { return L("today") }
        let d = Int(left.rounded(.up))
        return d == 1 ? L("1 day") : L("%@ days", Format.count(d))
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
                Text(L("from %@", Format.path((item.original as NSString).deletingLastPathComponent))).zenData(12, color: Zen.gray5)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(item.size)).zenData().frame(width: 100, alignment: .trailing)
            IconButton(icon: "external-link", help: L("Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.stored)])
            }
            IconButton(icon: "arrow-back-up", help: L("Restore this item")) { Task { await model.restore(batch, item: item) } }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(Zen.gray1.opacity(0.5))
    }
}
