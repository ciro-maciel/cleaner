import SwiftUI
import AppKit

struct MonitorScreen: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = monitor.sample
        Page {
            PageHeader(crumb: "Cleaner", title: "Monitor",
                       subtitle: "Como o seu Mac está agora: processador, memória, disco, rede e bateria, medidos a cada \(Int(monitor.interval)) segundos. O mesmo resumo fica na barra de menus.") {
                IntervalPicker()
            }

            grid(s).padding(.bottom, 40)

            HStack(alignment: .top, spacing: 32) {
                ProcessTable(title: "Mais processador", rows: monitor.topByCPU(8)) { "\(Format.decimal($0.cpu))%" }
                ProcessTable(title: "Mais memória", rows: monitor.topByMemory(8)) { Format.bytes($0.memory) }
            }
            .padding(.bottom, 16)
            Text("Processador por processo é a média recente do ps, em % de um núcleo: um app pesado passa de 100% num Mac com vários núcleos. Atualiza a cada 4 segundos.")
                .zenNote().padding(.bottom, 40)

            MenuBarSettings().padding(.bottom, 16)

            Text("\(machine) · ligado há \(Format.uptime(s.uptime)). Temperatura do processador e ventoinhas ficam de fora: o macOS só as entrega por interfaces privadas. A da bateria vem do sensor dela, por leitura pública.")
                .zenNote()
        }
        .onAppear { monitor.watchProcesses(true) }
        .onDisappear { monitor.watchProcesses(false) }
    }

    private var machine: String {
        let l = monitor.reader.coreLayout
        let cores = l.efficiency > 0 ? "\(l.performance) núcleos de desempenho e \(l.efficiency) de eficiência" : "\(l.performance) núcleos"
        return "\(monitor.reader.model), \(cores), \(Format.bytes(monitor.sample.memory.total)) de memória"
    }

    private func grid(_ s: SystemSample) -> some View {
        let cap = monitor.historyLength
        let memPct = Double(s.memory.used) / Double(max(s.memory.total, 1))
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                MetricCell(icon: "cpu", label: "Processador", value: Format.percentValue(s.cpu.total), unit: "%",
                           lines: ["Usuário \(Format.percent(s.cpu.user)) · sistema \(Format.percent(s.cpu.system))",
                                   "Carga média \(Format.decimal(s.cpu.load.0)) · \(Format.decimal(s.cpu.load.1)) · \(Format.decimal(s.cpu.load.2))"]) {
                    VStack(spacing: 10) {
                        Sparkline(values: monitor.cpu, capacity: cap)
                        CoreBars(cores: s.cpu.cores, height: 28)
                    }
                }
                rule
                MetricCell(icon: "gauge", label: "GPU", value: s.gpu.map(Format.percentValue) ?? "—", unit: s.gpu == nil ? "" : "%",
                           lines: [s.gpu == nil ? "Esta GPU não informa o uso." : "Uso do processador gráfico", thermalLine(s.thermal)],
                           alert: s.thermal == .serious || s.thermal == .critical) {
                    Sparkline(values: monitor.gpu, capacity: cap)
                }
                rule
                MetricCell(icon: "stack-2", label: "Memória", value: Format.percentValue(memPct), unit: "%",
                           lines: ["\(Format.bytes(s.memory.used)) de \(Format.bytes(s.memory.total)) · pressão \(pressure(s.memory.pressure))",
                                   "Apps \(Format.bytes(s.memory.app)) · fixa \(Format.bytes(s.memory.wired)) · comprimida \(Format.bytes(s.memory.compressed))",
                                   "Troca \(Format.bytes(s.memory.swapUsed))"],
                           alert: s.memory.pressure >= 4) {
                    VStack(alignment: .leading, spacing: 10) {
                        Sparkline(values: monitor.memory, capacity: cap)
                        HStack {
                            Text("Livre \(Format.bytes(s.memory.free)) · cache de arquivos \(Format.bytes(s.memory.cached))")
                                .zenData(12, color: Zen.gray6).lineLimit(1)
                            Spacer(minLength: 8)
                            FreeMemoryButton()
                        }
                    }
                }
            }
            Rectangle().fill(Zen.gray2).frame(height: 1)
            HStack(spacing: 0) {
                MetricCell(icon: "device-sd-card", label: "Disco", value: Format.split(s.disk.free).0, unit: Format.split(s.disk.free).1 + " livres",
                           lines: ["Lendo \(Format.rate(s.disk.readPerSec)) · gravando \(Format.rate(s.disk.writePerSec))",
                                   "\(Format.bytes(s.disk.total - s.disk.free)) usados de \(Format.bytes(s.disk.total))"]) {
                    Sparkline(values: monitor.diskRead, second: monitor.diskWrite, ceiling: nil, capacity: cap)
                }
                rule
                MetricCell(icon: "arrows-down-up", label: "Rede", value: Format.split(s.network.inPerSec).0,
                           unit: (Format.split(s.network.inPerSec).1 == "bytes" ? "B" : Format.split(s.network.inPerSec).1) + "/s baixando",
                           lines: ["Enviando \(Format.rate(s.network.outPerSec))",
                                   s.network.interface.isEmpty ? "Sem conexão Wi-Fi ou cabo" : "\(s.network.interface) · \(s.network.address)",
                                   "Desde que ligou: \(Format.bytes(s.network.totalIn)) baixados, \(Format.bytes(s.network.totalOut)) enviados"]) {
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
            MetricCell(icon: b.charging ? "battery-charging" : "battery", label: "Bateria", value: "\(b.percent)", unit: "%",
                       lines: Self.batteryLines(b), alert: !b.onAC && b.percent <= 10) {
                ShareBar(fraction: Double(b.percent) / 100, height: 10).padding(.vertical, 23)
            }
        } else {
            MetricCell(icon: "bolt", label: "Energia", value: "Tomada", unit: "",
                       lines: ["Este Mac não tem bateria.", thermalLine(s.thermal)]) {
                Color.clear.frame(height: 56)
            }
        }
    }

    static func batteryLines(_ b: SystemSample.Battery) -> [String] {
        var lines: [String] = []
        let state = b.charging ? "Carregando" : (b.onAC ? "Na tomada, sem carregar" : "Na bateria")
        lines.append(b.minutesLeft.map { "\(state) · \(b.charging ? "cheia em" : "dura mais") \(Format.minutes($0))" } ?? state)
        var health: [String] = []
        if let h = b.health { health.append("saúde \(Format.percent(h))") }
        if let c = b.cycles { health.append("\(c) ciclos") }
        if !health.isEmpty { lines.append(health.joined(separator: " · ").capitalizedFirst) }
        var phys: [String] = []
        if let t = b.temperature { phys.append("\(Format.decimal(t)) °C") }
        if let w = b.watts, abs(w) >= 0.1 { phys.append("\(w > 0 ? "entrando" : "saindo") \(Format.decimal(abs(w))) W") }
        if let a = b.adapterWatts, b.onAC { phys.append("carregador de \(a) W") }
        if !phys.isEmpty { lines.append(phys.joined(separator: " · ").capitalizedFirst) }
        return lines
    }

    private var rule: some View { Rectangle().fill(Zen.gray2).frame(width: 1) }

    private func pressure(_ level: Int) -> String {
        switch level { case 4: return "crítica"; case 2: return "alta"; default: return "normal" }
    }

    private func thermalLine(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "Temperatura normal"
        case .fair: return "Esquentando um pouco"
        case .serious: return "Quente: o macOS reduz o ritmo"
        case .critical: return "Muito quente: desempenho reduzido"
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
                    Text("Lendo os processos…").zenData(12, color: Zen.gray5)
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
        .help("De quanto em quanto tempo o Cleaner mede")
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
                    Text("Barra de menus").font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                    Text("O resumo fica ao lado do relógio. Com ele ligado, fechar a janela não fecha o Cleaner.")
                        .zenData(12, color: Zen.gray6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { enabled.toggle(); StatusItem.shared.sync() } label: {
                    HStack(spacing: 8) { CheckBox(state: enabled ? .on : .off); Text(enabled ? "Ligada" : "Desligada").zenData(13, color: Zen.gray9) }
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
    /// 1.234 → "1,2"
    static func decimal(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
