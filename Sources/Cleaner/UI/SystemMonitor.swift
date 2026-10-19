import SwiftUI
import AppKit
import Observation

/// What the menu bar shows. Stored in UserDefaults so the choice survives restarts.
enum MenuMetric: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, network, disk, battery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return L("CPU")
        case .gpu: return "GPU"
        case .memory: return L("Memory")
        case .network: return L("Network")
        case .disk: return L("Disk")
        case .battery: return L("Battery")
        }
    }
    var key: String { "menu.\(rawValue)" }
    static let defaults: Set<MenuMetric> = [.cpu, .memory, .network]
}

enum MonitorSettings {
    static let enabledKey = "menu.enabled"
    static let intervalKey = "monitor.interval"

    static func register() {
        var d: [String: Any] = [enabledKey: true, intervalKey: 2.0]
        for m in MenuMetric.allCases { d[m.key] = MenuMetric.defaults.contains(m) }
        UserDefaults.standard.register(defaults: d)
    }
}

/// Samples the machine on a loop and keeps two minutes of history for the charts.
/// The loop is a Task with Task.sleep, not a Timer: it keeps running while a menu is open or
/// the mouse is down (AppKit's tracking run-loop mode stops plain timers).
@MainActor
@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()
    static let historySeconds = 120.0

    private(set) var sample = SystemSample()
    private(set) var cpu: [Double] = []
    private(set) var gpu: [Double] = []
    private(set) var memory: [Double] = []
    private(set) var netIn: [Double] = []
    private(set) var netOut: [Double] = []
    private(set) var diskRead: [Double] = []
    private(set) var diskWrite: [Double] = []
    private(set) var processes: [ProcessRow] = []
    private(set) var menuImage: NSImage = SystemMonitor.placeholder
    private(set) var started = Date()

    let reader = SystemReader()
    private var loop: Task<Void, Never>?
    private var processWatchers = 0
    private var ticks = 0

    var interval: Double {
        get { access(keyPath: \.interval); return max(1, UserDefaults.standard.double(forKey: MonitorSettings.intervalKey)) }
        set { withMutation(keyPath: \.interval) { UserDefaults.standard.set(newValue, forKey: MonitorSettings.intervalKey) } }
    }

    var historyLength: Int { Int(Self.historySeconds / interval) }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    /// Process lists cost a fork of ps: only while a screen that shows them is open.
    // MARK: free memory

    var freeingMemory = false
    /// Last result, shown for a while where the button was.
    private(set) var lastFreed: (bytes: Int64, at: Date)?

    var recentlyFreed: Int64? {
        guard let last = lastFreed, Date().timeIntervalSince(last.at) < 12 else { return nil }
        return last.bytes
    }

    /// Set when the helper needs the user's one-time approval; shown in place of the button.
    var helperNote: String?

    func freeMemory() async {
        guard !freeingMemory else { return }
        freeingMemory = true
        defer { freeingMemory = false }

        var state = Helper.state
        if state == .notRegistered { state = Helper.register() }
        switch state {
        case .ready:
            helperNote = nil
            let reader = self.reader
            let before = await Task.detached { reader.freeBytes() }.value
            do {
                try await Helper.purgeMemory()
                try? await Task.sleep(for: .milliseconds(500))
                let after = await Task.detached { reader.freeBytes() }.value
                lastFreed = (max(0, after - before), Date())
                await tick()
            } catch {
                AppModel.shared.show(error.localizedDescription, error: true)
            }
        case .needsApproval:
            helperNote = L("Approve Cleaner in Login Items, once")
            Helper.openApproval()
        case .notRegistered, .unavailable:
            let why: String
            if case .unavailable(let m) = state { why = m } else { why = L("macOS did not register the helper") }
            helperNote = nil
            AppModel.shared.show(L("Could not turn on the helper: %@", why), error: true)
        }
    }

    func watchProcesses(_ on: Bool) {
        processWatchers = max(0, processWatchers + (on ? 1 : -1))
        if on && processWatchers == 1 { Task { await refreshProcesses() } }
    }

    private func tick() async {
        let reader = self.reader
        let s = await Task.detached { reader.sample() }.value
        sample = s
        let n = historyLength
        push(&cpu, s.cpu.total, n)
        push(&gpu, s.gpu ?? 0, n)
        push(&memory, s.memory.total > 0 ? Double(s.memory.used) / Double(s.memory.total) : 0, n)
        push(&netIn, Double(s.network.inPerSec), n)
        push(&netOut, Double(s.network.outPerSec), n)
        push(&diskRead, Double(s.disk.readPerSec), n)
        push(&diskWrite, Double(s.disk.writePerSec), n)
        ticks += 1
        if processWatchers > 0 && ticks % max(1, Int(4 / interval)) == 0 { await refreshProcesses() }
        renderMenuImage()
    }

    private func push(_ list: inout [Double], _ value: Double, _ n: Int) {
        list.append(value)
        if list.count > n { list.removeFirst(list.count - n) }
    }

    private func refreshProcesses() async {
        processes = await Task.detached { SystemReader.topProcesses() }.value
    }

    func topByCPU(_ n: Int) -> [ProcessRow] { Array(processes.sorted { $0.cpu > $1.cpu }.prefix(n)) }
    func topByMemory(_ n: Int) -> [ProcessRow] { Array(processes.sorted { $0.memory > $1.memory }.prefix(n)) }

    // MARK: menu bar image

    /// The status item is a template image drawn from SwiftUI: label 7 pt over value 11 pt per
    /// metric, Montserrat, black; macOS tints it for light and dark menu bars.
    func renderMenuImage() {
        let enabled = MenuMetric.allCases.filter { UserDefaults.standard.bool(forKey: $0.key) }
            .filter { $0 != .battery || sample.battery != nil }
        guard !enabled.isEmpty else { menuImage = Self.placeholder; StatusItem.shared.setImage(menuImage); return }
        let renderer = ImageRenderer(content: MenuBarStrip(metrics: enabled, sample: sample))
        renderer.scale = 2
        if let image = renderer.nsImage {
            image.isTemplate = true
            menuImage = image
            StatusItem.shared.setImage(image)
        }
    }

    static let placeholder: NSImage = {
        let img = Icon.image("activity") ?? NSImage(size: NSSize(width: 18, height: 18))
        img.size = NSSize(width: 18, height: 18)
        return img
    }()
}

/// The strip drawn into the menu bar image. Every metric gets a slot as wide as its widest
/// possible value (measured in the real font), content aligned left, one gap between slots:
/// the item keeps its size as numbers change and the spacing stays even.
struct MenuBarStrip: View {
    let metrics: [MenuMetric]
    let sample: SystemSample

    static let gap: CGFloat = 10
    static let labelFont = Zen.font(7, .extraBold)
    static let valueFont = Zen.font(11, .bold)
    static let rateFont = Zen.font(8.5, .bold)
    static let arrow: CGFloat = 8

    private static func width(_ texts: [String], _ name: String, _ size: CGFloat, tracking: CGFloat = 0) -> CGFloat {
        let font = NSFont(name: name, size: size) ?? .boldSystemFont(ofSize: size)
        return texts.map { t in
            let w = (t as NSString).size(withAttributes: [.font: font]).width
            return w + tracking * CGFloat(max(t.count - 1, 0))
        }.max().map { ceil($0) } ?? 0
    }

    /// Slot for a label over a percentage: the wider of the label and "100%".
    private static func pairWidth(_ labels: [String], _ values: [String]) -> CGFloat {
        max(width(labels, "Montserrat-ExtraBold", 7, tracking: 0.5), width(values, "Montserrat-Bold", 11))
    }

    static let percentSlot = pairWidth(["CPU", "GPU", "RAM"], ["100%"])
    static let batterySlot = pairWidth(["BAT+"], ["100%"])
    static let diskSlot = pairWidth(["SSD"], ["999G", "9,9T"])
    static let rateSlot = arrow + 2 + width(["999 KB", "9,9 MB", "999 MB", "999 B"], "Montserrat-Bold", 8.5)

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(metrics) { m in item(m) }
        }
        .foregroundStyle(Color.black)
        .frame(height: 22)
    }

    @ViewBuilder
    private func item(_ m: MenuMetric) -> some View {
        switch m {
        case .network:
            VStack(alignment: .leading, spacing: 0) {
                rate("arrow-up", sample.network.outPerSec)
                rate("arrow-down", sample.network.inPerSec)
            }
            .frame(width: Self.rateSlot, alignment: .leading)
        case .disk:
            pair("SSD", Format.compactBytes(sample.disk.free), width: Self.diskSlot)
        case .cpu:
            pair("CPU", "\(Int((sample.cpu.total * 100).rounded()))%", width: Self.percentSlot)
        case .gpu:
            pair("GPU", "\(Int(((sample.gpu ?? 0) * 100).rounded()))%", width: Self.percentSlot)
        case .memory:
            pair("RAM", "\(Int((Double(sample.memory.used) / Double(max(sample.memory.total, 1)) * 100).rounded()))%", width: Self.percentSlot)
        case .battery:
            pair(sample.battery?.charging == true ? "BAT+" : "BAT", "\(sample.battery?.percent ?? 0)%", width: Self.batterySlot)
        }
    }

    private func rate(_ icon: String, _ value: Int64) -> some View {
        HStack(spacing: 2) {
            Icon(name: icon, size: Self.arrow, color: .black)
            Text(Format.rate(value, compact: true)).font(Self.rateFont).lineLimit(1)
        }
    }

    private func pair(_ label: String, _ value: String, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -2) {
            Text(label).font(Self.labelFont).tracking(0.5)
            Text(value).font(Self.valueFont)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// `Cleaner --menubar-preview <dir>`: draws the strip with everyday and widest values into PNGs,
/// on white at 4×, for checking the spacing without opening the app.
@MainActor
enum MenuBarPreview {
    static func run(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var typical = SystemSample()
        typical.cpu.user = 0.05; typical.cpu.system = 0.02
        typical.memory.total = 25_800_000_000; typical.memory.app = 13_200_000_000
        typical.network.inPerSec = 0; typical.network.outPerSec = 0
        typical.disk.free = 146_000_000_000
        var wide = typical
        wide.cpu.user = 0.8; wide.cpu.system = 0.2
        wide.memory.app = 25_800_000_000
        wide.network.inPerSec = 999_000; wide.network.outPerSec = 12_400_000
        wide.disk.free = 999_000_000_000
        var battery = SystemSample.Battery(); battery.percent = 100; battery.charging = true
        wide.battery = battery
        let sets: [(String, [MenuMetric], SystemSample)] = [
            ("default-typical", [.cpu, .memory, .network], typical),
            ("default-wide", [.cpu, .memory, .network], wide),
            ("all-wide", MenuMetric.allCases, wide),
        ]
        for (name, metrics, sample) in sets {
            let view = MenuBarStrip(metrics: metrics, sample: sample).padding(.horizontal, 8).background(Color.white)
            let r = ImageRenderer(content: view)
            r.scale = 4
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
                print("\(name): \(Int(img.size.width)) × \(Int(img.size.height)) pt")
            }
        }
        print("slots: percent \(MenuBarStrip.percentSlot), rate \(MenuBarStrip.rateSlot), disk \(MenuBarStrip.diskSlot), battery \(MenuBarStrip.batterySlot)")
    }
}
