import SwiftUI
import AppKit

struct CleanupScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: L("Cleanup"),
                       subtitle: L("Only what Cleaner's public rules name gets in: folders that apps recreate by themselves. Review, untick what you want to keep, and move the rest to the quarantine.")) {
                Button { Task { await model.scanCleanup() } } label: {
                    ButtonLabel(title: model.cleanupScanning ? L("Scanning…") : L("Scan Again"), icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.cleanupScanning || model.cleanupGroups == nil)

                HoldButton(title: model.cleanupSelectedCount == 0 ? L("Nothing Selected") : L("Move %@", Format.bytes(model.cleanupSelectedBytes)),
                           icon: "trash") { Task { await model.cleanSelected() } }
                    .disabled(model.cleanupSelectedCount == 0 || model.cleanupScanning)
            }

            if model.cleanupScanning && model.cleanupGroups == nil {
                VStack(spacing: 16) {
                    ScanningAnimation(size: 200)
                    Text(L("Measuring the rule folders…")).zenLabel(11, color: Zen.gray5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 56)
            } else if let groups = model.cleanupGroups {
                if groups.isEmpty {
                    EmptyState(illustration: "done", title: L("Nothing to clean"),
                               subtitle: L("No rule found anything to remove. Come back in a few days: caches grow with use."))
                } else {
                    summary(groups).padding(.bottom, 32)
                    table(groups)
                    Text(L("Hold the button for 3 seconds to move. Everything stays 7 days in the Quarantine and goes back with one click. Items of open apps start unticked."))
                        .zenNote().padding(.top, 16)
                }
            } else {
                EmptyState(illustration: "cleanup", title: L("Not scanned yet"),
                           subtitle: L("The scan only reads. It measures caches, logs, the Trash, old installers and developer caches.")) {
                    Button { Task { await model.scanCleanup() } } label: { ButtonLabel(title: L("Scan Now"), icon: "scan", color: .white) }
                        .buttonStyle(ZenButtonStyle(kind: .primary))
                }
            }
        }
    }

    private func summary(_ groups: [CleanupGroup]) -> some View {
        HStack(alignment: .bottom, spacing: 48) {
            BigMetric(label: L("Selected to remove"), bytes: model.cleanupSelectedBytes,
                      note: L("%1$@ of %2$@, in %3$@. Total found: %4$@.", Format.plural(model.cleanupSelectedCount, L("item selected"), L("items selected")),
                              Format.count(groups.flatMap(\.items).count), Format.plural(groups.count, L("rule"), L("rules")), Format.bytes(model.cleanupTotal)),
                      size: 72)
            Spacer()
            if let at = model.cleanupScannedAt {
                Text(L("Scanned %@", Format.date(at))).zenData(12, color: Zen.gray5)
            }
        }
    }

    private func table(_ groups: [CleanupGroup]) -> some View {
        TableCard {
            TableHeader(columns: [(L("Rule"), nil), (L("Items"), 80), (L("Size"), 100)], leading: 30)
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
                    Text(group.rule.displayTitle).font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                    if group.rule.risk == .medium { DotBadge(text: L("Review [badge]"), color: Zen.gray5) }
                }
                Text(group.rule.displayWhy).zenData(12, color: Zen.gray6).lineLimit(2)
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
            IconButton(icon: "external-link", help: L("Show in Finder")) {
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
