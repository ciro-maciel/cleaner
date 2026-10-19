import SwiftUI
import AppKit

struct DiskMapScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: L("Disk Map"),
                       subtitle: L("Every folder by the space it really takes. Go into the biggest ones, tick what you no longer need and send it all to the quarantine at once.")) {
                Button { choose() } label: { ButtonLabel(title: L("Other Folder"), icon: "folder-open") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                    .disabled(model.diskScanning)
                Button { Task { await model.scanDisk() } } label: {
                    ButtonLabel(title: model.diskScanning ? L("Measuring…") : (model.diskIndex == nil ? L("Measure") : L("Measure Again")), icon: "scan")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.diskScanning)
                if model.diskIndex != nil && !model.diskScanning {
                    if model.diskMoving {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Moving…")).zenData(12, color: Zen.gray6) }
                            .frame(height: 36)
                    } else {
                        let picked = model.diskSelectedEntries
                        HoldButton(title: picked.isEmpty ? L("Nothing Selected") : L("Move %@", Format.bytes(picked.reduce(0) { $0 + $1.size })), icon: "trash") {
                            Task { await model.moveDiskSelection() }
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }

            if model.diskScanning {
                VStack(spacing: 16) {
                    ScanningAnimation(size: 200)
                    Text(L("%@ files read", Format.count(model.diskFilesSeen))).zenLabel(11, color: Zen.gray5)
                    Text(displayName(model.diskRoot)).zenData(12, color: Zen.gray5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 56)
            } else if model.diskIndex != nil {
                content
            } else {
                EmptyState(illustration: "diskmap", title: L("Start with your home folder"),
                           subtitle: L("The measurement reads all of %@, in parallel. On a full Mac it takes a minute or two.", Format.path(NSHomeDirectory()))) {
                    Button { Task { await model.scanDisk() } } label: { ButtonLabel(title: L("Measure Now"), icon: "scan", color: .white) }
                        .buttonStyle(ZenButtonStyle(kind: .primary))
                }
            }
        }
    }

    private var content: some View {
        let path = model.diskPath
        let total = model.diskSize(path)
        let entries = model.diskListing
        let biggest = entries.first?.size ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            if path != model.diskRoot { breadcrumb.padding(.bottom, 24) }
            BigMetric(label: displayName(path), bytes: total,
                      note: L("%@ in this folder. Measured in blocks used; APFS clones count in full in each copy.", Format.plural(entries.count, L("item"), L("items"))),
                      size: 72)
                .padding(.bottom, 32)
            if !model.diskSelection.isEmpty {
                let picked = entries.filter { model.diskSelection.contains($0.path) }
                Text(L("%1$@ · %2$@ · hold the Move button for 3 seconds", Format.plural(picked.count, L("item selected"), L("items selected")), Format.bytes(picked.reduce(0) { $0 + $1.size })))
                    .zenData(13, color: Zen.gray9).padding(.bottom, 12)
            }
            TableCard {
                header(entries)
                ForEach(Array(entries.prefix(300).enumerated()), id: \.element.id) { i, entry in
                    DiskRow(entry: entry, share: Double(entry.size) / Double(max(total, 1)), bar: Double(entry.size) / Double(max(biggest, 1)))
                    if i < min(entries.count, 300) - 1 { RowDivider() }
                }
            }
            Text(L("Click a folder to go in; the box ticks it. What is removed stays 7 days in the Quarantine and comes back with one click; the space returns to the disk only when it is emptied."))
                .zenNote().padding(.top, 16)
            if let denied = model.diskIndex?.denied, denied > 0 {
                Text(L("%1$@ read for lack of permission%2$@.", Format.plural(denied, L("folder could not be"), L("folders could not be")),
                        model.hasFullDiskAccess ? "" : L(". Turn on Full Disk Access to measure everything")))
                    .zenNote().padding(.top, 16)
            }
        }
    }

    private func header(_ entries: [DiskEntry]) -> some View {
        let shown = Array(entries.prefix(300))
        let marked = shown.filter { model.diskSelection.contains($0.path) }.count
        let state: CheckBox.State = marked == 0 ? .off : (marked == shown.count ? .on : .mixed)
        return HStack(spacing: 12) {
            Button {
                if state == .on { shown.forEach { model.diskSelection.remove($0.path) } }
                else { shown.forEach { model.diskSelection.insert($0.path) } }
            } label: { CheckBox(state: state) }
            .buttonStyle(.plain)
            .help(state == .on ? L("Untick all") : L("Tick all in this folder"))
            Color.clear.frame(width: 16, height: 1)
            Text(L("Name")).zenLabel(10, color: Zen.gray5).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Share")).zenLabel(10, color: Zen.gray5).frame(width: 220, alignment: .leading)
            Text(L("Size")).zenLabel(10, color: Zen.gray5).frame(width: 100, alignment: .trailing)
            Color.clear.frame(width: 28, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Zen.gray1)
        .overlay(alignment: .bottom) { Rectangle().fill(Zen.gray2).frame(height: 1) }
    }

    private var breadcrumb: some View {
        let root = model.diskRoot
        let rel = model.diskPath.dropFirst(root.count).split(separator: "/").map(String.init)
        var paths: [(String, String)] = [(root, displayName(root))]
        var acc = root
        for part in rel { acc = (acc as NSString).appendingPathComponent(part); paths.append((acc, part)) }
        return HStack(spacing: 6) {
            if paths.count > 1 {
                IconButton(icon: "arrow-left", help: L("Up one folder")) { model.openDiskFolder(paths[paths.count - 2].0) }
            }
            ForEach(Array(paths.enumerated()), id: \.offset) { i, p in
                if i > 0 { Icon(name: "chevron-right", size: 12, color: Zen.gray4) }
                Button(p.1) { model.openDiskFolder(p.0) }
                    .buttonStyle(.plain)
                    .font(Zen.font(13, i == paths.count - 1 ? .bold : .medium))
                    .foregroundStyle(i == paths.count - 1 ? Zen.gray9 : Zen.gray5)
            }
        }
    }

    private func displayName(_ path: String) -> String {
        path == NSHomeDirectory() ? L("Home folder") : (path as NSString).lastPathComponent
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Measure")
        panel.directoryURL = URL(fileURLWithPath: model.diskRoot)
        if panel.runModal() == .OK, let url = panel.url { Task { await model.scanDisk(root: url.path) } }
    }
}

private struct DiskRow: View {
    @Environment(AppModel.self) private var model
    let entry: DiskEntry
    let share: Double
    let bar: Double

    var body: some View {
        let on = model.diskSelection.contains(entry.path)
        HStack(spacing: 12) {
            Button { model.toggleDiskEntry(entry) } label: { CheckBox(state: on ? .on : .off) }
                .buttonStyle(.plain)
            Icon(name: entry.isFolder ? "folder" : "file", size: 16, color: Zen.gray5)
            Text(entry.name).zenData(13, color: Zen.gray9).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ShareBar(fraction: bar, height: 6)
                Text(Format.percent(entry.size, of: model.diskSize(model.diskPath))).zenData(12, color: Zen.gray5).frame(width: 40, alignment: .trailing)
            }
            .frame(width: 220)
            Text(Format.bytes(entry.size)).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).frame(width: 100, alignment: .trailing)
            IconButton(icon: "external-link", help: L("Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(on ? Zen.gray1 : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if entry.isFolder { model.openDiskFolder(entry.path) } else { model.toggleDiskEntry(entry) } }
        .rowHover(!on)
    }
}
