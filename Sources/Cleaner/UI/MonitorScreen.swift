import SwiftUI
import AppKit

struct MonitorScreen: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = monitor.sample
        Page {
            PageHeader(crumb: "Cleaner", title: L("Monitor"),
                       subtitle: L("How your Mac is doing right now: processor, memory, disk, network and battery, measured every %@ seconds. The same summary lives in the menu bar.", String(Int(monitor.interval)))) {
                IntervalPicker()
            }

            grid(s).padding(.bottom, 40)

            HStack(alignment: .top, spacing: 32) {
                ProcessTable(title: L("Top CPU"), rows: monitor.topByCPU(8)) { "\(Format.decimal($0.cpu))%" }
                ProcessTable(title: L("Top Memory"), rows: monitor.topByMemory(8)) { Format.bytes($0.memory) }
            }
            .padding(.bottom, 16)
            Text(L("CPU per process is the recent average from ps, in % of one core: a heavy app goes past 100% on a Mac with several cores. Updates every 4 seconds."))
                .zenNote().padding(.bottom, 40)

            MenuBarSettings().padding(.bottom, 16)

            Text(L("%1$@ · up for %2$@. CPU temperature and fans are left out: macOS only provides them through private interfaces. The battery's comes from its own sensor, through a public reading.", machine, Format.uptime(s.uptime)))
                .zenNote()
        }
        .onAppear { monitor.watchProcesses(true) }
        .onDisappear { monitor.watchProcesses(false) }
    }

    private var machine: String {
        let l = monitor.reader.coreLayout
        let cores = l.efficiency > 0 ? L("%1$@ performance cores and %2$@ efficiency cores", String(l.performance), String(l.efficiency)) : L("%@ cores", String(l.performance))
        return L("%1$@, %2$@, %3$@ of memory", monitor.reader.model, cores, Format.bytes(monitor.sample.memory.total))
    }

    private func grid(_ s: SystemSample) -> some View {
        let cap = monitor.historyLength
        let memPct = Double(s.memory.used) / Double(max(s.memory.total, 1))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                MetricCell(icon: "cpu", label: L("CPU"), value: Format.percentValue(s.cpu.total), unit: "%",
                           lines: [L("User %1$@ · system %2$@", Format.percent(s.cpu.user), Format.percent(s.cpu.system)),
                                   L("Load average %1$@ · %2$@ · %3$@", Format.decimal(s.cpu.load.0), Format.decimal(s.cpu.load.1), Format.decimal(s.cpu.load.2))]) {
                    VStack(spacing: 10) {
                        Sparkline(values: monitor.cpu, capacity: cap)
                        CoreBars(cores: s.cpu.cores, height: 28)
                    }
                }
                rule
                MetricCell(icon: "gauge", label: "GPU", value: s.gpu.map(Format.percentValue) ?? "—", unit: s.gpu == nil ? "" : "%",
                           lines: [s.gpu == nil ? L("This GPU does not report its usage.") : L("Graphics processor usage"), thermalLine(s.thermal)],
                           alert: s.thermal == .serious || s.thermal == .critical) {
                    Sparkline(values: monitor.gpu, capacity: cap)
                }
                rule
                MetricCell(icon: "stack-2", label: L("Memory"), value: Format.percentValue(memPct), unit: "%",
                           lines: [L("%1$@ of %2$@ · pressure %3$@", Format.bytes(s.memory.used), Format.bytes(s.memory.total), pressure(s.memory.pressure)),
                                   L("Apps %1$@ · wired %2$@ · compressed %3$@", Format.bytes(s.memory.app), Format.bytes(s.memory.wired), Format.bytes(s.memory.compressed)),
                                   L("Swap %@", Format.bytes(s.memory.swapUsed))],
                           alert: s.memory.pressure >= 4) {
                    VStack(alignment: .leading, spacing: 10) {
                        Sparkline(values: monitor.memory, capacity: cap)
                        HStack {
                            Text(L("Free %1$@ · file cache %2$@", Format.bytes(s.memory.free), Format.bytes(s.memory.cached)))
                                .zenData(12, color: Zen.gray6).lineLimit(1)
                            Spacer(minLength: 8)
                            FreeMemoryButton()
                        }
                    }
                }
            }
            Rectangle().fill(Zen.gray2).frame(height: 1)
            HStack(spacing: 0) {
                MetricCell(icon: "device-sd-card", label: L("Disk"), value: Format.split(s.disk.free).0, unit: L("%@ free", Format.split(s.disk.free).1),
                           lines: [L("Reading %1$@ · writing %2$@", Format.rate(s.disk.readPerSec), Format.rate(s.disk.writePerSec)),
                                   L("%1$@ used of %2$@", Format.bytes(s.disk.total - s.disk.free), Format.bytes(s.disk.total))]) {
                    Sparkline(values: monitor.diskRead, second: monitor.diskWrite, ceiling: nil, capacity: cap)
                }
                rule
                MetricCell(icon: "arrows-down-up", label: L("Network"), value: Format.split(s.network.inPerSec).0,
                           unit: L("%@/s downloading", Format.split(s.network.inPerSec).1 == "bytes" ? "B" : Format.split(s.network.inPerSec).1),
                           lines: [L("Uploading %@", Format.rate(s.network.outPerSec)),
                                   s.network.interface.isEmpty ? L("No Wi-Fi or cable connection") : "\(s.network.interface) · \(s.network.address)",
                                   L("Since startup: %1$@ down, %2$@ up", Format.bytes(s.network.totalIn), Format.bytes(s.network.totalOut))]) {
                    Sparkline(values: monitor.netIn, second: monitor.netOut, ceiling: nil, capacity: cap)
                }
                rule
                batteryCell(s)
            }
        }
        .zenBorder()
    }

    @ViewBuilder
    private func batteryCell(_ s: SystemSample) -> some View {
        if let b = s.battery {
            MetricCell(icon: b.charging ? "battery-charging" : "battery", label: L("Battery"), value: "\(b.percent)", unit: "%",
                       lines: Self.batteryLines(b), alert: !b.onAC && b.percent <= 10) {
                ShareBar(fraction: Double(b.percent) / 100, height: 10).padding(.vertical, 23)
            }
        } else {
            MetricCell(icon: "bolt", label: L("Power"), value: L("Plugged In"), unit: "",
                       lines: [L("This Mac has no battery."), thermalLine(s.thermal)]) {
                Color.clear.frame(height: 56)
            }
        }
    }

    static func batteryLines(_ b: SystemSample.Battery) -> [String] {
        var lines: [String] = []
        let state = b.charging ? L("Charging") : (b.onAC ? L("Plugged in, not charging") : L("On battery"))
        lines.append(b.minutesLeft.map { b.charging ? L("%1$@ · full in %2$@", state, Format.minutes($0)) : L("%1$@ · %2$@ left", state, Format.minutes($0)) } ?? state)
        var health: [String] = []
        if let h = b.health { health.append(L("health %@", Format.percent(h))) }
        if let c = b.cycles { health.append(L("%@ cycles", Format.count(c))) }
        if !health.isEmpty { lines.append(health.joined(separator: " · ").capitalizedFirst) }
        var phys: [String] = []
        if let t = b.temperature { phys.append("\(Format.decimal(t)) °C") }
        if let w = b.watts, abs(w) >= 0.1 { phys.append(w > 0 ? L("in %@ W", Format.decimal(abs(w))) : L("out %@ W", Format.decimal(abs(w)))) }
        if let a = b.adapterWatts, b.onAC { phys.append(L("%@ W charger", String(a))) }
        if !phys.isEmpty { lines.append(phys.joined(separator: " · ").capitalizedFirst) }
        return lines
    }

    private var rule: some View { Rectangle().fill(Zen.gray2).frame(width: 1) }

    private func pressure(_ level: Int) -> String {
        switch level { case 4: return L("critical"); case 2: return L("high"); default: return L("normal") }
    }

    private func thermalLine(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return L("Normal temperature")
        case .fair: return L("Warming up a little")
        case .serious: return L("Hot: macOS slows down")
        case .critical: return L("Very hot: reduced performance")
        @unknown default: return ""
        }
    }
}

/// One cell of the monitor grid: label, the big number, a chart, the details under it.
struct MetricCell<Chart: View>: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    var lines: [String] = []
    var alert = false
    @ViewBuilder var chart: Chart

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Icon(name: icon, size: 14, color: Zen.gray5)
                Text(label).zenLabel(10, color: Zen.gray5)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).zenDisplay(44).lineLimit(1).minimumScaleFactor(0.6).monospacedDigit()
                Text(unit).font(Zen.font(13, .extraBold)).foregroundStyle(Zen.gray9).lineLimit(1)
            }
            chart
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line).zenData(12, color: alert && i == 0 ? Zen.red7 : Zen.gray6).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProcessTable: View {
    let title: String
    let rows: [ProcessRow]
    let value: (ProcessRow) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).zenLabel(10, color: Zen.gray5)
            TableCard {
                if rows.isEmpty {
                    Text(L("Reading processes…")).zenData(12, color: Zen.gray5)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 14)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 10) {
                        if let app = NSRunningApplication(processIdentifier: row.pid), let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Icon(name: "app-window", size: 16, color: Zen.gray4).frame(width: 18)
                        }
                        Text(NSRunningApplication(processIdentifier: row.pid)?.localizedName ?? row.name)
                            .zenData(13, color: Zen.gray9).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(value(row)).font(Zen.font(13, .bold)).foregroundStyle(Zen.gray9).monospacedDigit()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    if i < rows.count - 1 { RowDivider() }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 1 s · 2 s · 5 s, as three joined buttons: the active one filled gray.9.
struct IntervalPicker: View {
    @Environment(SystemMonitor.self) private var monitor
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            ForEach([1.0, 2.0, 5.0], id: \.self) { v in
                let on = monitor.interval == v
                Button { monitor.interval = v } label: {
                    Text("\(Int(v)) s")
                        .font(Zen.font(11, .extraBold)).tracking(1)
                        .frame(width: 44, height: height)
                        .foregroundStyle(on ? .white : Zen.gray7)
                        .background(on ? Zen.gray9 : Zen.gray0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .zenBorder(Zen.gray3)
        .help(L("How often Cleaner measures"))
    }
}

/// Which metrics go to the menu bar, and whether the item is there at all.
struct MenuBarSettings: View {
    @AppStorage(MonitorSettings.enabledKey) private var enabled = true
    @Environment(SystemMonitor.self) private var monitor
    @State private var tick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Menu Bar")).font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                    Text(L("The summary sits next to the clock. With it on, closing the window does not quit Cleaner."))
                        .zenData(12, color: Zen.gray6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { enabled.toggle(); StatusItem.shared.sync() } label: {
                    HStack(spacing: 8) { CheckBox(state: enabled ? .on : .off); Text(enabled ? L("On [menu bar]") : L("Off [menu bar]")).zenData(13, color: Zen.gray9) }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            if enabled {
                RowDivider()
                HStack(spacing: 24) {
                    ForEach(MenuMetric.allCases) { m in
                        let on = UserDefaults.standard.bool(forKey: m.key)
                        Button {
                            UserDefaults.standard.set(!on, forKey: m.key)
                            tick += 1
                            monitor.renderMenuImage()
                        } label: {
                            HStack(spacing: 8) { CheckBox(state: on ? .on : .off); Text(m.title).zenData(13, color: Zen.gray9) }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .id(tick)
                .padding(20)
            }
        }
        .zenBorder()
    }
}

extension Format {
    /// 0.123 → "12"
    static func percentValue(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))" }
    /// 0.123 → "12%"
    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }
    /// 1.234 → "1,2" in Portuguese, "1.2" in English
    static func decimal(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = L10n.locale
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
