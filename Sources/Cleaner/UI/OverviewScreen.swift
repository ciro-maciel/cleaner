import SwiftUI

struct OverviewScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: "Visão geral",
                       subtitle: "O que ocupa o seu Mac e o que dá para liberar sem perder nada. Tudo o que sai passa 7 dias na quarentena.") {
                Button { Task { await model.scanEverything() } } label: {
                    ButtonLabel(title: model.scanningAnything ? "Varrendo…" : "Varrer o Mac", icon: "scan", color: .white)
                }
                .buttonStyle(ZenButtonStyle(kind: .primary))
                .disabled(model.scanningAnything)
            }

            if !model.hasFullDiskAccess { AccessBanner().padding(.bottom, 32) }

            hero.padding(.bottom, 40)
            disk.padding(.bottom, 40)
            cells
        }
    }

    // The big number: what a cleanup frees right now.
    private var hero: some View {
        HStack(alignment: .center, spacing: 48) {
            if model.cleanupGroups == nil && !model.cleanupScanning {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dá para liberar").zenLabel(11)
                    Text("Ainda não varremos").zenDisplay(56)
                    Text("A varredura só lê: mede caches, registros, instaladores esquecidos, apps e itens de inicialização. Nada sai do lugar sem você revisar.")
                        .zenNote().frame(maxWidth: 460, alignment: .leading)
                }
            } else if model.cleanupScanning {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dá para liberar").zenLabel(11)
                    Text("Medindo…").zenDisplay(56)
                    Text("Lendo as pastas das regras de limpeza. Leva de alguns segundos a um minuto.").zenNote()
                }
            } else {
                BigMetric(label: "Dá para liberar", bytes: model.cleanupTotal,
                          note: "Soma do que a Limpeza encontrou agora, em \(Format.plural(model.cleanupGroups?.flatMap(\.items).count ?? 0, "item", "itens")). Medido em blocos ocupados no disco, como o Finder.")
            }
            Spacer(minLength: 0)
            Group {
                if model.scanningAnything { ScanningAnimation(size: 220) }
                else { Illustration(name: model.cleanupGroups == nil ? "scan" : "done", size: 220) }
            }
        }
    }

    private var disk: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Disco").zenLabel(10, color: Zen.gray5)
                Spacer()
                if let v = model.volume {
                    Text("\(Format.bytes(v.used)) usados de \(Format.bytes(v.total)) · \(Format.bytes(v.available)) livres")
                        .zenData(13)
                }
            }
            if let v = model.volume {
                ShareBar(fraction: Double(v.used) / Double(max(v.total, 1)), height: 10)
                Text("Livres conta o espaço que o macOS consegue liberar sozinho, como o Finder mostra.").zenNote()
            }
        }
    }

    // StatsGrid: cells that touch, divided by 1px rules.
    private var cells: some View {
        HStack(spacing: 0) {
            OverviewCell(screen: .cleanup, value: model.cleanupGroups.map { _ in Format.bytes(model.cleanupTotal) } ?? "—",
                         note: model.cleanupGroups.map { $0.isEmpty ? "nada a limpar agora" : "em \(Format.plural($0.count, "regra", "regras")) de limpeza" }
                               ?? (model.cleanupScanning ? "medindo…" : "varra para medir"))
            divider
            OverviewCell(screen: .uninstaller, value: model.apps.isEmpty ? "—" : Format.count(model.apps.count),
                         note: model.apps.isEmpty ? (model.appsLoading ? "listando…" : "varra para listar") : "apps, \(Format.bytes(model.appsTotal)) ao todo")
            divider
            OverviewCell(screen: .startup, value: model.startupItems.isEmpty ? "—" : Format.count(model.startupItems.filter { !$0.disabled }.count),
                         note: model.startupItems.isEmpty ? (model.startupLoading ? "lendo…" : "varra para listar")
                               : "abrem sozinhos · \(Format.plural(model.backgroundApps.count, "app", "apps")) rodando sem janela")
            divider
            OverviewCell(screen: .quarantine, value: Format.bytes(model.quarantineBytes),
                         note: model.batches.isEmpty ? "nada guardado agora" : "em \(Format.plural(model.batches.count, "lote", "lotes")), some em 7 dias")
        }
        .zenBorder()
    }

    private var divider: some View { Rectangle().fill(Zen.gray2).frame(width: 1) }
}

struct OverviewCell: View {
    @Environment(AppModel.self) private var model
    let screen: Screen
    let value: String
    let note: String
    @State private var hover = false

    var body: some View {
        Button { model.screen = screen } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(screen.title).zenLabel(10, color: Zen.gray5)
                    Spacer()
                    Icon(name: "chevron-right", size: 14, color: hover ? Zen.gray9 : Zen.gray4)
                }
                Text(value).zenDisplay(32).lineLimit(1).minimumScaleFactor(0.6)
                Text(note).zenData(12, color: Zen.gray6).lineLimit(2)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hover ? Zen.gray1 : Zen.gray0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct AccessBanner: View {
    var body: some View {
        Banner(icon: "lock", title: "Ligue o Acesso Total ao Disco",
               text: "Sem ele o macOS esconde a Lixeira, o Mail e os contêineres dos apps, e a varredura fica pela metade. Em Ajustes, ligue o Cleaner na lista; se o aviso continuar, reabra o Cleaner.") {
            HStack(spacing: 8) {
                Button { Permissions.openFullDiskAccessSettings() } label: {
                    ButtonLabel(title: "Abrir Ajustes", icon: "settings")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                Button { Permissions.relaunch() } label: {
                    ButtonLabel(title: "Já liguei: reabrir", icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .subtle))
                .help("O macOS pode aplicar a permissão só depois de reabrir o Cleaner")
            }
        }
    }
}
