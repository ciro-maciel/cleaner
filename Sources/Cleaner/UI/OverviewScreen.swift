import SwiftUI

struct OverviewScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Page {
            PageHeader(crumb: "Cleaner", title: L("Overview"),
                       subtitle: L("What takes up space on your Mac and what can be freed without losing anything. Everything removed spends 7 days in the quarantine.")) {
                Button { Task { await model.scanEverything() } } label: {
                    ButtonLabel(title: model.scanningAnything ? L("Scanning…") : L("Scan Your Mac"), icon: "scan", color: .white)
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
                    Text(L("Can be freed")).zenLabel(11)
                    Text(L("Not scanned yet")).zenDisplay(56)
                    Text(L("The scan only reads: it measures caches, logs, forgotten installers, apps and startup items. Nothing moves until you review it."))
                        .zenNote().frame(maxWidth: 460, alignment: .leading)
                }
            } else if model.cleanupScanning {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Can be freed")).zenLabel(11)
                    Text(L("Measuring…")).zenDisplay(56)
                    Text(L("Reading the folders of the cleanup rules. It takes from a few seconds to a minute.")).zenNote()
                }
            } else {
                BigMetric(label: L("Can be freed"), bytes: model.cleanupTotal,
                          note: L("Everything Cleanup found just now, across %@. Measured in blocks used on disk, as the Finder does.", Format.plural(model.cleanupGroups?.flatMap(\.items).count ?? 0, L("item"), L("items"))))
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
                Text(L("Disk")).zenLabel(10, color: Zen.gray5)
                Spacer()
                if let v = model.volume {
                    Text(L("%1$@ used of %2$@ · %3$@ available", Format.bytes(v.used), Format.bytes(v.total), Format.bytes(v.available)))
                        .zenData(13)
                }
            }
            if let v = model.volume {
                ShareBar(fraction: Double(v.used) / Double(max(v.total, 1)), height: 10)
                Text(L("Available counts the space macOS can free by itself, as the Finder shows it.")).zenNote()
            }
        }
    }

    // StatsGrid: cells that touch, divided by 1px rules.
    private var cells: some View {
        HStack(spacing: 0) {
            OverviewCell(screen: .cleanup, value: model.cleanupGroups.map { _ in Format.bytes(model.cleanupTotal) } ?? "—",
                         note: model.cleanupGroups.map { $0.isEmpty ? L("nothing to clean now") : L("in %@", Format.plural($0.count, L("cleanup rule"), L("cleanup rules"))) }
                               ?? (model.cleanupScanning ? L("measuring…") : L("scan to measure")))
            divider
            OverviewCell(screen: .uninstaller, value: model.apps.isEmpty ? "—" : Format.count(model.apps.count),
                         note: model.apps.isEmpty ? (model.appsLoading ? L("listing…") : L("scan to list")) : L("apps, %@ in all", Format.bytes(model.appsTotal)))
            divider
            OverviewCell(screen: .startup, value: model.startupItems.isEmpty ? "—" : Format.count(model.startupItems.filter { !$0.disabled }.count),
                         note: model.startupItems.isEmpty ? (model.startupLoading ? L("reading…") : L("scan to list"))
                               : L("start automatically · %@ running without a window", Format.plural(model.backgroundApps.count, L("app"), L("apps"))))
            divider
            OverviewCell(screen: .quarantine, value: Format.bytes(model.quarantineBytes),
                         note: model.batches.isEmpty ? L("nothing kept now") : L("in %@, gone after 7 days", Format.plural(model.batches.count, L("batch"), L("batches"))))
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
        Banner(icon: "lock", title: L("Turn on Full Disk Access"),
               text: L("Without it, macOS hides the Trash, Mail and app containers, and the scan only sees half. In Settings, turn on Cleaner in the list; if this notice stays, reopen Cleaner.")) {
            HStack(spacing: 8) {
                Button { Permissions.openFullDiskAccessSettings() } label: {
                    ButtonLabel(title: L("Open Settings"), icon: "settings")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                Button { Permissions.relaunch() } label: {
                    ButtonLabel(title: L("Turned on: reopen"), icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .subtle))
                .help(L("macOS may apply the permission only after Cleaner reopens"))
            }
        }
    }
}
