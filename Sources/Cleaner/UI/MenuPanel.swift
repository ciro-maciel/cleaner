import SwiftUI
import AppKit

/// The panel under the menu bar item: the same numbers as the Monitor screen, compact,
/// plus what a cleanup frees and a way into the app.
struct MenuPanel: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = monitor.sample
        let cap = monitor.historyLength
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cleaner").zenDisplay(20)
                Spacer()
                Text("ligado há \(Format.uptime(s.uptime))").zenData(11, color: Zen.gray5)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)

            RowDivider()
            row(icon: "cpu", label: "Processador", value: Format.percent(s.cpu.total),
                detail: "Usuário \(Format.percent(s.cpu.user)) · sistema \(Format.percent(s.cpu.system))") {
                Sparkline(values: monitor.cpu, capacity: cap, height: 26)
            }
            RowDivider()
            row(icon: "stack-2", label: "Memória", value: Format.percent(Double(s.memory.used) / Double(max(s.memory.total, 1))),
                detail: "\(Format.bytes(s.memory.used)) de \(Format.bytes(s.memory.total)) · livre \(Format.bytes(s.memory.free))",
                alert: s.memory.pressure >= 4, trailing: AnyView(FreeMemoryButton())) {
                Sparkline(values: monitor.memory, capacity: cap, height: 26)
            }
            RowDivider()
            row(icon: "arrows-down-up", label: "Rede", value: Format.rate(s.network.inPerSec),
                detail: "Enviando \(Format.rate(s.network.outPerSec))\(s.network.interface.isEmpty ? "" : " · \(s.network.interface)")") {
                Sparkline(values: monitor.netIn, second: monitor.netOut, ceiling: nil, capacity: cap, height: 26)
            }
            RowDivider()
            row(icon: "device-sd-card", label: "Disco", value: "\(Format.bytes(s.disk.free)) livres",
                detail: "Lendo \(Format.rate(s.disk.readPerSec)) · gravando \(Format.rate(s.disk.writePerSec))") { EmptyView() }
            if let b = s.battery {
                RowDivider()
                row(icon: b.charging ? "battery-charging" : "battery", label: "Bateria", value: "\(b.percent)%",
                    detail: MonitorScreen.batteryLines(b).first ?? "", alert: !b.onAC && b.percent <= 10) {
                    ShareBar(fraction: Double(b.percent) / 100, height: 6)
                }
            }

            let top = monitor.topByCPU(3)
            if !top.isEmpty {
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mais processador").zenLabel(9, color: Zen.gray5)
                    ForEach(top) { p in
                        HStack(spacing: 8) {
                            Text(NSRunningApplication(processIdentifier: p.pid)?.localizedName ?? p.name)
                                .zenData(12, color: Zen.gray9).lineLimit(1)
                            Spacer()
                            Text("\(Format.decimal(p.cpu))%").font(Zen.font(12, .bold)).foregroundStyle(Zen.gray9).monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }

            if model.cleanupGroups != nil {
                RowDivider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dá para liberar").zenLabel(9, color: Zen.gray5)
                        Text(Format.bytes(model.cleanupTotal)).font(Zen.font(18, .black)).foregroundStyle(Zen.gray9)
                    }
                    Spacer()
                    Button { open(.cleanup) } label: { ButtonLabel(title: "Revisar", icon: "sparkles") }
                        .buttonStyle(ZenButtonStyle(kind: .secondary, height: 30))
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }

            HStack(spacing: 8) {
                Button { open(.monitor) } label: { ButtonLabel(title: "Abrir o Cleaner", icon: "app-window", color: .white) }
                    .buttonStyle(ZenButtonStyle(kind: .primary, height: 30))
                Spacer()
                HoldButton(title: "Sair", icon: "power", kind: .secondary, height: 30) {
                    AppDelegate.allowQuit = true
                    NSApp.terminate(nil)
                }
                .help("Segure 3 segundos para fechar o Cleaner de vez. ⌘Q só esconde a janela.")
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(Zen.gray1)
            .overlay(alignment: .top) { Rectangle().fill(Zen.gray2).frame(height: 1) }
        }
        .frame(width: 340)
        .background(Zen.gray0)
        .onAppear { monitor.watchProcesses(true) }
        .onDisappear { monitor.watchProcesses(false) }
    }

    private func row<Chart: View>(icon: String, label: String, value: String, detail: String, alert: Bool = false,
                                  trailing: AnyView? = nil, @ViewBuilder chart: () -> Chart) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Icon(name: icon, size: 13, color: Zen.gray5)
                Text(label).zenLabel(9, color: Zen.gray5)
                Spacer()
                Text(value).font(Zen.font(16, .black)).foregroundStyle(Zen.gray9).monospacedDigit().lineLimit(1)
            }
            chart()
            HStack(spacing: 8) {
                Text(detail).zenData(11, color: alert ? Zen.red7 : Zen.gray6).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing { trailing }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// Brings the main window back (or opens a new one if it was closed) on a screen.
    private func open(_ screen: Screen) {
        model.screen = screen
        StatusItem.shared.close()
        MainWindow.show()
    }
}
