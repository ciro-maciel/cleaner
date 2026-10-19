import SwiftUI
import AppKit

struct UninstallerScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page {
            PageHeader(crumb: "Cleaner", title: L("Uninstaller"),
                       subtitle: L("Dragging to the Trash leaves preferences, caches and containers behind. Tick the apps, review what each one spread around and remove it all at once. It comes back if you change your mind.")) {
                SearchField(text: $model.appQuery)
                Button { Task { await model.loadApps() } } label: {
                    ButtonLabel(title: model.appsLoading ? L("Measuring…") : L("Refresh"), icon: "refresh")
                }
                .buttonStyle(ZenButtonStyle(kind: .secondary))
                .disabled(model.appsLoading)
                Button { Task { await model.prepareUninstall() } } label: {
                    ButtonLabel(title: model.appSelection.isEmpty ? L("Select Apps") : L("Review %@", Format.plural(model.appSelection.count, L("app"), L("apps"))),
                                icon: "package", color: .white)
                }
                .buttonStyle(ZenButtonStyle(kind: .primary))
                .disabled(model.appSelection.isEmpty)
            }

            if model.apps.isEmpty {
                if model.appsLoading {
                    VStack(spacing: 16) {
                        ScanningAnimation(size: 200)
                        Text(L("Listing apps…")).zenLabel(11, color: Zen.gray5)
                    }.frame(maxWidth: .infinity).padding(.vertical, 56)
                } else {
                    EmptyState(illustration: "uninstall", title: L("Empty list"),
                               subtitle: L("We list the apps in Applications and in your own Applications folder, with the size of each.")) {
                        Button { Task { await model.loadApps() } } label: { ButtonLabel(title: L("List Apps"), icon: "apps", color: .white) }
                            .buttonStyle(ZenButtonStyle(kind: .primary))
                    }
                }
            } else {
                if !model.orphans.isEmpty { OrphanSection().padding(.bottom, 40) }
                if !model.appSelection.isEmpty {
                    Text(L("%1$@ · %2$@ not counting leftovers", Format.plural(model.appSelection.count, L("app selected"), L("apps selected")), Format.bytes(model.selectedAppsBytes)))
                        .zenData(13, color: Zen.gray9).padding(.bottom, 12)
                }
                list
                Text(L("Click a row to tick it. Sizes measured on disk. App Store and system apps ask for the administrator password to be removed. macOS and Safari are not listed: they are part of the system."))
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
                .help(state == .on ? L("Untick all") : L("Tick all in the list"))
                Color.clear.frame(width: 28, height: 1)
                Text(L("App")).zenLabel(10, color: Zen.gray5).frame(maxWidth: .infinity, alignment: .leading)
                Text(L("Version")).zenLabel(10, color: Zen.gray5).frame(width: 110, alignment: .trailing)
                Text(L("Last Used")).zenLabel(10, color: Zen.gray5).frame(width: 110, alignment: .trailing)
                Text(L("Size")).zenLabel(10, color: Zen.gray5).frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Zen.gray1)
            .overlay(alignment: .bottom) { Rectangle().fill(Zen.gray2).frame(height: 1) }

            if apps.isEmpty {
                VStack(spacing: 8) {
                    Text(L("No results for “%@”", model.appQuery)).zenLabel(10)
                    Button(L("Clear Search")) { model.appQuery = "" }.buttonStyle(ZenButtonStyle(kind: .subtle, height: 30))
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
            TextField(L("Search apps"), text: $text)
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
                    Text(L("Uninstall")).zenLabel(10)
                    Text(targets.count == 1 ? targets[0].name : L("%@ apps", Format.count(targets.count))).zenDisplay(28).lineLimit(1)
                    Text(targets.count == 1 ? targets[0].bundleID + (targets[0].version.isEmpty ? "" : L(" · version %@", targets[0].version))
                                            : targets.map(\.name).joined(separator: ", "))
                        .zenData(12, color: Zen.gray5).lineLimit(2)
                }
                Spacer()
                IconButton(icon: "x", help: L("Close")) { model.closeUninstall() }
            }
            .padding(32)

            let open = model.runningTargets
            if !open.isEmpty {
                Banner(icon: "alert-triangle", title: open.count == 1 ? L("%@ is open", open[0].name) : L("%@ apps are open", Format.count(open.count)),
                       text: L("Quit it before uninstalling, or the app recreates the files right away.")) {
                    Button(L("Quit")) { model.quitRunningTargets() }.buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                }
                .padding(.horizontal, 32).padding(.bottom, 16)
            }

            Text(L("What gets removed")).zenLabel(10, color: Zen.gray5).padding(.horizontal, 32).padding(.bottom, 8)
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
                    Text(L("Total")).zenLabel(10, color: Zen.gray5)
                    Text(Format.bytes(model.uninstallBytes)).zenDisplay(24)
                }
                Spacer()
                if model.uninstalling {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L("Moving to the quarantine…")).zenData(12, color: Zen.gray6)
                    }
                } else {
                    HoldButton(title: targets.count == 1 ? L("Uninstall") : L("Uninstall %@ apps", Format.count(targets.count)), icon: "trash") {
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
        line(icon: "package", title: multi ? app.name : L("The app"), path: app.path, size: app.size ?? 0, locked: true, on: true,
             appIcon: multi ? app.path : nil) {}
        if model.leftoversLoading {
            RowDivider()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("Looking for what the app left…")).zenData(12, color: Zen.gray5)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
        } else if (model.leftovers[app.path] ?? []).isEmpty {
            RowDivider()
            Text(L("No leftovers found in the Library folders%@.", model.hasFullDiskAccess ? "" : L(" (with Full Disk Access off, some of them are hidden)")))
                .zenData(12, color: Zen.gray5)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 50).padding(.trailing, 20).padding(.vertical, 10)
        }
        ForEach(model.leftovers[app.path] ?? []) { left in
            RowDivider()
            line(icon: left.system ? "lock" : "folder", title: left.kind, path: left.path, size: left.size,
                 locked: false, on: model.leftoverSelection.contains(left.path), appIcon: nil,
                 note: left.protected && !model.hasFullDiskAccess ? L("Needs Full Disk Access") : nil) {
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
                    Text(L("Leftovers of removed apps")).zenLabel(10, color: Zen.gray5)
                    Text(L("Apps no longer on disk that left files behind or a ? icon in the Dock."))
                        .zenData(12, color: Zen.gray6)
                }
                Spacer()
                if model.orphansCleaning {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Cleaning…")).zenData(12, color: Zen.gray6) }
                } else {
                    HoldButton(title: model.orphanSelection.isEmpty ? L("Nothing Selected") : L("Clear Leftovers"), icon: "trash", kind: .secondary) {
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
                        row(key: orphan.dockKey, icon: "apps", title: L("Dock icon"), detail: L("%@ no longer exists", Format.path(orphan.path)), size: nil, note: nil)
                    }
                    ForEach(orphan.leftovers) { left in
                        RowDivider()
                        row(key: left.path, icon: left.system ? "lock" : "folder", title: left.kind, detail: Format.path(left.path), size: left.size,
                            note: left.protected && !model.hasFullDiskAccess ? L("Needs Full Disk Access") : nil)
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
