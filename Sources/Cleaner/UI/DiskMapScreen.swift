import SwiftUI
import AppKit

struct DiskMapScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Mapa do disco",
                       subtitle: "Cada pasta pelo tamanho que ocupa de verdade. Entre nas maiores, marque o que não serve mais e mande tudo para a quarentena de uma vez.") {
                Button { choose() } label: { ButtonLabel(title: "Outra pasta", icon: "folder-open") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary))
                    .disabled(model.diskScanning)
                Button { Task { await model.scanDisk() } } label: {
                    ButtonLabel(title: model.diskScanning ? "Medindo…" : (model.diskIndex == nil ? "Medir" : "Medir de novo"), icon: "scan")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.diskScanning)
                if model.diskIndex != nil && !model.diskScanning {
                    if model.diskMoving {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Movendo…").zenData(12, color: Zen.gray6) }
                            .frame(height: 36)
                    } else {
                        let picked = model.diskSelectedEntries
                        HoldButton(title: picked.isEmpty ? "Nada marcado" : "Mover \(Format.bytes(picked.reduce(0) { $0 + $1.size }))", icon: "trash") {
                            Task { await model.moveDiskSelection() }
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }

            if model.diskScanning {
                VStack(spacing: 16) {
                    ScanningAnimation(size: 200)
                    Text("\(Format.count(model.diskFilesSeen)) arquivos lidos").zenLabel(11, color: Zen.gray5)
                    Text(displayName(model.diskRoot)).zenData(12, color: Zen.gray5)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 56)
            } else if model.diskIndex != nil {
                content
            } else {
                EmptyState(illustration: "diskmap", title: "Comece pela sua pasta pessoal",
                           subtitle: "A medição lê \(Format.path(NSHomeDirectory())) inteira, em paralelo. Num Mac cheio leva um ou dois minutos.") {
                    Button { Task { await model.scanDisk() } } label: { ButtonLabel(title: "Medir agora", icon: "scan", color: .white) }
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
                      note: "\(Format.plural(entries.count, "item", "itens")) nesta pasta. Medido em blocos ocupados; arquivos clonados do APFS contam inteiros em cada cópia.",
                      size: 72)
                .padding(.bottom, 32)
            if !model.diskSelection.isEmpty {
                let picked = entries.filter { model.diskSelection.contains($0.path) }
                Text("\(Format.plural(picked.count, "item marcado", "itens marcados")) · \(Format.bytes(picked.reduce(0) { $0 + $1.size })) · segure o botão Mover por 3 segundos")
                    .zenData(13, color: Zen.gray9).padding(.bottom, 12)
            }
            TableCard {
                header(entries)
                ForEach(Array(entries.prefix(300).enumerated()), id: \.element.id) { i, entry in
                    DiskRow(entry: entry, share: Double(entry.size) / Double(max(total, 1)), bar: Double(entry.size) / Double(max(biggest, 1)))
                    if i < min(entries.count, 300) - 1 { RowDivider() }
                }
            }
            Text("Clique numa pasta para entrar; a caixa marca. O que sai fica 7 dias na Quarentena e volta com um clique; o espaço só volta ao disco quando ela esvazia.")
                .zenNote().padding(.top, 16)
            if let denied = model.diskIndex?.denied, denied > 0 {
                Text("\(Format.plural(denied, "pasta não pôde", "pastas não puderam")) ser lidas por falta de permissão\(model.hasFullDiskAccess ? "" : ". Ligue o Acesso Total ao Disco para medir tudo").")
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
            .help(state == .on ? "Desmarcar todos" : "Marcar todos desta pasta")
            Color.clear.frame(width: 16, height: 1)
            Text("Nome").zenLabel(10, color: Zen.gray5).frame(maxWidth: .infinity, alignment: .leading)
            Text("Parte").zenLabel(10, color: Zen.gray5).frame(width: 220, alignment: .leading)
            Text("Tamanho").zenLabel(10, color: Zen.gray5).frame(width: 100, alignment: .trailing)
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
                IconButton(icon: "arrow-left", help: "Voltar uma pasta") { model.openDiskFolder(paths[paths.count - 2].0) }
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
        path == NSHomeDirectory() ? "Pasta pessoal" : (path as NSString).lastPathComponent
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Medir"
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
            IconButton(icon: "external-link", help: "Mostrar no Finder") {
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
