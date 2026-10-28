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

    /// The status item is a template image: label 7 pt over value 11 pt per metric,
    /// Montserrat, black; macOS tints it for light and dark menu bars.
    func renderMenuImage() {
        let enabled = MenuMetric.allCases.filter { UserDefaults.standard.bool(forKey: $0.key) }
            .filter { $0 != .battery || sample.battery != nil }
        guard !enabled.isEmpty else { menuImage = Self.placeholder; StatusItem.shared.setImage(menuImage); return }
        let image = MenuBarStrip.image(metrics: enabled, sample: sample)
        image.isTemplate = true
        menuImage = image
        StatusItem.shared.setImage(image)
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
enum MenuBarStrip {
    static let gap: CGFloat = 10
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

    /// The strip as an image, drawn with Core Graphics when macOS displays it. A SwiftUI
    /// ImageRenderer would cost 117 MB of graphics memory for as long as the app runs.
    static func image(metrics: [MenuMetric], sample: SystemSample) -> NSImage {
        let size = NSSize(width: metrics.map(slot).reduce(0, +) + gap * CGFloat(max(metrics.count - 1, 0)), height: 22)
        return NSImage(size: size, flipped: true) { _ in
            draw(metrics, sample)
            return true
        }
    }

    /// Into the current graphics context, flipped, at the strip's own size.
    static func draw(_ metrics: [MenuMetric], _ sample: SystemSample) {
        var x: CGFloat = 0
        for m in metrics {
            draw(m, sample, at: x)
            x += slot(m) + gap
        }
    }

    private static func slot(_ m: MenuMetric) -> CGFloat {
        switch m {
        case .network: return rateSlot
        case .disk: return diskSlot
        case .battery: return batterySlot
        case .cpu, .gpu, .memory: return percentSlot
        }
    }

    private static func font(_ name: String, _ size: CGFloat) -> NSFont { NSFont(name: name, size: size) ?? .boldSystemFont(ofSize: size) }
    private static func lineHeight(_ f: NSFont) -> CGFloat { f.ascender - f.descender + f.leading }

    private static func draw(_ m: MenuMetric, _ sample: SystemSample, at x: CGFloat) {
        switch m {
        case .network:
            let f = font("Montserrat-Bold", 8.5)
            let row = max(arrow, lineHeight(f))
            let top = (22 - row * 2) / 2
            for (i, (icon, value)) in [("arrow-up", sample.network.outPerSec), ("arrow-down", sample.network.inPerSec)].enumerated() {
                let y = top + row * CGFloat(i)
                // A template: black where it has ink, as SwiftUI tints it. The mask is drawn
                // unflipped, or the up arrow would point down.
                if let ctx = NSGraphicsContext.current?.cgContext, let img = Icon.image(icon) {
                    var px = CGRect(x: 0, y: 0, width: arrow * 4, height: arrow * 4)
                    if let mask = img.cgImage(forProposedRect: &px, context: nil, hints: nil) {
                        let r = CGRect(x: x, y: y + (row - arrow) / 2, width: arrow, height: arrow)
                        ctx.saveGState()
                        ctx.translateBy(x: r.minX, y: r.maxY)
                        ctx.scaleBy(x: 1, y: -1)
                        ctx.clip(to: CGRect(origin: .zero, size: r.size), mask: mask)
                        ctx.setFillColor(NSColor.black.cgColor)
                        ctx.fill(CGRect(origin: .zero, size: r.size))
                        ctx.restoreGState()
                    }
                }
                (Format.rate(value, compact: true) as NSString).draw(at: CGPoint(x: x + arrow + 2, y: y + (row - lineHeight(f)) / 2), withAttributes: [.font: f, .foregroundColor: NSColor.black])
            }
        case .disk: pair("SSD", Format.compactBytes(sample.disk.free), at: x)
        case .cpu: pair("CPU", "\(Int((sample.cpu.total * 100).rounded()))%", at: x)
        case .gpu: pair("GPU", "\(Int(((sample.gpu ?? 0) * 100).rounded()))%", at: x)
        case .memory: pair("RAM", "\(Int((Double(sample.memory.used) / Double(max(sample.memory.total, 1)) * 100).rounded()))%", at: x)
        case .battery: pair(sample.battery?.charging == true ? "BAT+" : "BAT", "\(sample.battery?.percent ?? 0)%", at: x)
        }
    }

    private static func pair(_ label: String, _ value: String, at x: CGFloat) {
        let lf = font("Montserrat-ExtraBold", 7), vf = font("Montserrat-Bold", 11)
        let top = (22 - (lineHeight(lf) + lineHeight(vf) - 2)) / 2
        (label as NSString).draw(at: CGPoint(x: x, y: top), withAttributes: [.font: lf, .kern: 0.5, .foregroundColor: NSColor.black])
        (value as NSString).draw(at: CGPoint(x: x, y: top + lineHeight(lf) - 2), withAttributes: [.font: vf, .foregroundColor: NSColor.black])
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
            let strip = MenuBarStrip.image(metrics: metrics, sample: sample)
            let w = Int((strip.size.width + 16) * 4), h = Int(strip.size.height * 4)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.translateBy(x: 32, y: CGFloat(h)); ctx.scaleBy(x: 4, y: -4)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            MenuBarStrip.draw(metrics, sample)
            NSGraphicsContext.restoreGraphicsState()
            if let img = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, nil)
                CGImageDestinationFinalize(dest)
            }
            print("\(name): \(Int(strip.size.width + 16)) × \(Int(strip.size.height)) pt")
        }
        print("slots: percent \(MenuBarStrip.percentSlot), rate \(MenuBarStrip.rateSlot), disk \(MenuBarStrip.diskSlot), battery \(MenuBarStrip.batterySlot)")
    }
}
