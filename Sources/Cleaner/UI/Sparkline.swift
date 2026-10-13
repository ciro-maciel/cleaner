import SwiftUI

/// Two minutes of a metric as a line. Ink gray.9, a faint area under it, the baseline in
/// gray.2. `ceiling` fixes the top (1 for percentages); nil scales to the largest value seen.
/// A second series, when given, is drawn dashed in gray.5 (upload against download, say).
struct Sparkline: View {
    let values: [Double]
    var second: [Double]? = nil
    var ceiling: Double? = 1
    var capacity: Int = 60
    var height: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let top = ceiling ?? max((values + (second ?? [])).max() ?? 0, 1)
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Zen.gray2).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
                area(values, top: top, in: geo.size).fill(Zen.gray9.opacity(0.06))
                line(values, top: top, in: geo.size).stroke(Zen.gray9, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                if let second {
                    line(second, top: top, in: geo.size).stroke(Zen.gray5, style: StrokeStyle(lineWidth: 1.25, lineJoin: .round, dash: [3, 3]))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func points(_ data: [Double], top: Double, in size: CGSize) -> [CGPoint] {
        guard !data.isEmpty else { return [] }
        let step = size.width / CGFloat(max(capacity - 1, 1))
        let start = size.width - step * CGFloat(data.count - 1)
        return data.enumerated().map { i, v in
            CGPoint(x: start + step * CGFloat(i), y: size.height - CGFloat(min(max(v / top, 0), 1)) * (size.height - 2) - 1)
        }
    }

    private func line(_ data: [Double], top: Double, in size: CGSize) -> Path {
        Path { p in
            let pts = points(data, top: top, in: size)
            guard let first = pts.first else { return }
            p.move(to: first)
            pts.dropFirst().forEach { p.addLine(to: $0) }
        }
    }

    private func area(_ data: [Double], top: Double, in size: CGSize) -> Path {
        Path { p in
            let pts = points(data, top: top, in: size)
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { p.addLine(to: $0) }
            p.addLine(to: CGPoint(x: last.x, y: size.height))
            p.closeSubpath()
        }
    }
}

/// Per-core bars: one thin column per logical core, height = use.
struct CoreBars: View {
    let cores: [Double]
    var height: CGFloat = 40
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Zen.gray2)
                    Rectangle().fill(Zen.gray9).frame(height: max(1, CGFloat(v) * height))
                }
                .frame(height: height)
            }
        }
    }
}

/// "Liberar" next to memory: runs purge, then says what it freed for a few seconds.
struct FreeMemoryButton: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if monitor.freeingMemory {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Liberando…").zenData(11, color: Zen.gray6)
                }
                .frame(height: 26)
            } else if let note = monitor.helperNote, Helper.state == .needsApproval {
                Button { Helper.openApproval() } label: {
                    HStack(spacing: 6) {
                        Icon(name: "settings", size: 13, color: Zen.gray9)
                        Text(note).font(Zen.font(11, .bold)).foregroundStyle(Zen.gray9).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 26)
                .help("Em Ajustes → Geral → Itens de início, ligue o Cleaner em Permitir em segundo plano. Depois disso, Liberar não pede senha.")
            } else if let freed = monitor.recentlyFreed {
                HStack(spacing: 6) {
                    Icon(name: "check", size: 13, color: Zen.gray9)
                    Text("\(Format.bytes(freed)) livres a mais").font(Zen.font(11, .bold)).foregroundStyle(Zen.gray9)
                }
                .frame(height: 26)
            } else {
                Button { Task { await monitor.freeMemory() } } label: { ButtonLabel(title: "Liberar", icon: "sparkles") }
                    .buttonStyle(ZenButtonStyle(kind: .secondary, height: 26))
                    .help("Esvazia o cache de arquivos que o macOS guarda na memória (comando purge), pelo ajudante do Cleaner, sem senha.")
            }
        }
    }
}
