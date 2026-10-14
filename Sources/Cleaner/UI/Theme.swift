import SwiftUI
import AppKit
import CoreText

/// RiLiGar Zen in SwiftUI: ten grays, Montserrat in four weights, radius zero, no shadow,
/// 1px rules in gray.2. Values from the Zen design system.
enum Zen {
    // 03-cor.md: the ramp. 0–3 surface and structure, 4–9 ink.
    static let gray0 = Color(hex: 0xFFFFFF)
    static let gray1 = Color(hex: 0xF9FAFB)
    static let gray2 = Color(hex: 0xF3F4F6)
    static let gray3 = Color(hex: 0xE5E7EB)
    static let gray4 = Color(hex: 0x9CA3AF)
    static let gray5 = Color(hex: 0x6B7280)
    static let gray6 = Color(hex: 0x4B5563)
    static let gray7 = Color(hex: 0x374151)
    static let gray8 = Color(hex: 0x1F2937)
    static let gray9 = Color(hex: 0x11181C)
    /// Loss and errors only (red.6 / red.7 of Mantine).
    static let red6 = Color(hex: 0xFA5252)
    static let red7 = Color(hex: 0xF03E3E)
    static let red2 = Color(hex: 0xFFC9C9)

    enum Weight { case regular, medium, bold, extraBold, black
        var postScript: String {
            switch self {
            case .regular: return "Montserrat-Regular"
            case .medium: return "Montserrat-Medium"
            case .bold: return "Montserrat-Bold"
            case .extraBold: return "Montserrat-ExtraBold"
            case .black: return "Montserrat-Black"
            }
        }
    }

    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font { .custom(weight.postScript, fixedSize: size) }

    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static let rule: CGFloat = 1
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - The four text roles (02-tipografia.md)

extension View {
    /// Label: the announcement. 10–13px, 800, uppercase, tracking 1.5, gray.4/5.
    func zenLabel(_ size: CGFloat = 10, color: Color = Zen.gray4) -> some View {
        font(Zen.font(size, .extraBold)).tracking(1.5).textCase(.uppercase).foregroundStyle(color)
    }
    /// Data: what is compared in a column. 13px, 500, gray.7.
    func zenData(_ size: CGFloat = 13, color: Color = Zen.gray7) -> some View {
        font(Zen.font(size, .medium)).foregroundStyle(color)
    }
    /// Body: what is read in sequence. 15px, 500, gray.6.
    func zenBody(_ size: CGFloat = 15, color: Color = Zen.gray6) -> some View {
        font(Zen.font(size, .medium)).foregroundStyle(color).lineSpacing(size * 0.4)
    }
    /// Note: the verification under a strong number. 13px, gray.6.
    func zenNote() -> some View {
        font(Zen.font(13, .medium)).foregroundStyle(Zen.gray6).lineSpacing(5)
    }
    /// Display: the declaration. 900, tracking -0.04em, gray.9.
    func zenDisplay(_ size: CGFloat) -> some View {
        font(Zen.font(size, .black)).tracking(-0.04 * size).foregroundStyle(Zen.gray9)
    }

    func zenBorder(_ color: Color = Zen.gray2) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: Zen.rule))
    }
}

// MARK: - Icons and illustrations

/// Tabler icon, outline, stroke 1.5, from Resources/Icons (template PDFs).
struct Icon: View {
    let name: String
    var size: CGFloat = 16
    var color: Color = Zen.gray7

    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "Icons"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[name] = img
        return img
    }

    var body: some View {
        Group {
            if let img = Icon.image(name) {
                Image(nsImage: img).renderingMode(.template).resizable().interpolation(.high)
            } else {
                Rectangle().fill(Color.clear)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(color)
    }
}

/// An illustration from Resources/Illustrations when the build has one; otherwise the Tabler
/// icon of the same idea, drawn large in a square of gray.1. The repository ships no
/// illustrations: the licensed gallery they came from can't be redistributed.
struct Illustration: View {
    let name: String
    var size: CGFloat = 160

    private static let fallback: [String: String] = [
        "scan": "scan", "cleanup": "sparkles", "uninstall": "package", "diskmap": "chart-treemap",
        "startup": "rocket", "quarantine": "shield-check", "done": "square-check", "access": "lock",
    ]

    /// Decoded once: the scan animation redraws this 60 times a second.
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Illustrations"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }

    var body: some View {
        if let img = Illustration.image(name) {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(width: size, height: size)
        } else {
            Icon(name: Illustration.fallback[name] ?? "sparkles", size: size * 0.4, color: Zen.gray5)
                .frame(width: size * 0.7, height: size * 0.7)
                .background(Zen.gray1)
                .zenBorder(Zen.gray3)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Buttons (05-forma.md: a label in a black rectangle)

struct ZenButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, subtle, danger }
    var kind: Kind = .primary
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        // Row buttons (30 pt and less) are compact: letter 10, tighter sides.
        let compact = height <= 30
        return configuration.label
            .font(Zen.font(compact ? 10 : 11, .extraBold))
            .tracking(compact ? 0.8 : 1)
            .textCase(.uppercase)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, kind == .subtle ? 8 : (compact ? 10 : 16))
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(background)
            .overlay(Rectangle().strokeBorder(border, lineWidth: kind == .secondary || kind == .danger ? 1 : 0))
            .opacity(enabled ? 1 : 0.45)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .offset(y: configuration.isPressed ? 0 : 0)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary, .subtle: return Zen.gray9
        case .danger: return Zen.red7
        }
    }
    private var background: Color { kind == .primary ? Zen.gray9 : Zen.gray0.opacity(kind == .subtle ? 0 : 1) }
    private var border: Color {
        switch kind {
        case .secondary: return Zen.gray3
        case .danger: return Zen.red7
        default: return .clear
        }
    }
}

struct ButtonLabel: View {
    let title: String
    var icon: String? = nil
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Icon(name: icon, size: 14, color: color ?? Zen.gray9) }
            Text(title)
        }
    }
}

/// 09-painel.md, "Ação destrutiva": nothing removes in one click. Hold for 3 s; letting go
/// at any moment cancels.
///
/// The timing is SwiftUI's long-press gesture, and the countdown is drawn per frame by a
/// TimelineView: a Foundation Timer would not fire while the mouse button is down, because
/// AppKit runs the event-tracking run loop mode during the press.
struct HoldButton: View {
    let title: String
    var icon: String? = "trash"
    var kind: ZenButtonStyle.Kind = .primary
    var duration: Double = 3
    var height: CGFloat = 36
    /// For drawing previews only: start showing the hint.
    var previewHint = false
    let action: () -> Void

    @State private var pressedAt: Date?
    /// A press let go too early: the label says what to do for a moment.
    @State private var hinting = false
    @State private var hintToken = 0
    @Environment(\.isEnabled) private var enabled

    private var hint: String { "Segure \(Int(duration)) s" }

    var body: some View {
        let fg: Color = kind == .primary ? .white : (kind == .danger ? Zen.red7 : Zen.gray9)
        TimelineView(.animation(minimumInterval: 1 / 30, paused: pressedAt == nil)) { context in
            let progress = pressedAt.map { min(1, context.date.timeIntervalSince($0) / duration) } ?? 0
            let left = max(1, Int(ceil(duration * (1 - progress))))
            let shown = pressedAt != nil ? "Segure… \(left)" : (hinting || previewHint ? hint : title)
            HStack(spacing: 8) {
                if let icon { Icon(name: icon, size: 14, color: fg) }
                // Every text the button can show sits in the same slot, so its width never jumps.
                ZStack(alignment: .center) {
                    ForEach([title, hint, "Segure… \(Int(duration))"], id: \.self) { Text($0).hidden() }
                    Text(shown)
                }
            }
            .font(Zen.font(height <= 30 ? 10 : 11, .extraBold)).tracking(height <= 30 ? 0.8 : 1).textCase(.uppercase).lineLimit(1)
            .fixedSize()
            .padding(.horizontal, height <= 30 ? 10 : 16)
            .frame(height: height)
            .foregroundStyle(fg)
            .background(kind == .primary ? Zen.gray9 : Zen.gray0)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Rectangle().fill(kind == .primary ? Color.white.opacity(0.85) : fg)
                        .frame(width: geo.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .overlay(Rectangle().strokeBorder(kind == .danger ? Zen.red7 : (kind == .secondary ? Zen.gray3 : .clear), lineWidth: 1))
        .opacity(enabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
            pressedAt = nil
            hinting = false
            if enabled { action() }
        } onPressingChanged: { pressing in
            if pressing && enabled {
                pressedAt = Date()
                hinting = false
            } else if let started = pressedAt {
                pressedAt = nil
                // Let go before the end: say how it works, then go back to the label.
                if Date().timeIntervalSince(started) < duration { showHint() }
            }
        }
        .help("Segure por \(Int(duration)) segundos para confirmar. Solte para cancelar.")
        .accessibilityHint("Segure por \(Int(duration)) segundos para confirmar")
    }

    private func showHint() {
        hintToken += 1
        let token = hintToken
        hinting = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            if hintToken == token { hinting = false }
        }
    }
}

/// A square checkbox (Tabler square / square-check / square-minus).
struct CheckBox: View {
    enum State { case on, off, mixed }
    let state: State
    var body: some View {
        Icon(name: state == .on ? "square-check" : (state == .mixed ? "square-minus" : "square"),
             size: 18, color: state == .off ? Zen.gray4 : Zen.gray9)
    }
}

/// The logotype: the bolt, the word and "by Ciro Cesar Maciel", the same lockup as the headers of
/// the Ciro's sites (design system, 14-logotipo.md; `Logotype` in @ciromaciel/components-kit).
/// Since 14/10/2026 it is drawn, not a bitmap: a vector bolt and live text. The signature has a
/// FIXED size — 0.42 of the word, never below 11 pt — and starts where the word starts; it is not
/// stretched to the word's width (Apple's rule, the "Download on the App Store" badge). A click
/// opens his site in the browser: a link the person clicks, not network code. `source` tells his
/// scoreboard which corner of the app the visit came from.
struct Logotype: View {
    var height: CGFloat
    let source: String

    private var wordSize: CGFloat { height / 2 }
    private var signatureSize: CGFloat { max(11, (0.21 * height * 10).rounded() / 10) }

    var body: some View {
        Button {
            if let url = URL(string: "https://ciromaciel.click/?ref=\(source)") { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: wordSize * 0.35) {
                LogotypeBolt()
                    .frame(width: height * 0.8 * 320 / 420, height: height * 0.8)
                VStack(alignment: .leading, spacing: signatureSize * 0.35) {
                    Text("Cleaner")
                        .font(Zen.font(wordSize, .extraBold)).tracking(-0.02 * wordSize)
                        .foregroundStyle(Zen.gray9)
                    Text("by Ciro Cesar Maciel")
                        .font(Zen.font(signatureSize, .bold)).tracking(0.01 * signatureSize)
                        .foregroundStyle(Zen.gray6)
                }
            }
            .fixedSize()
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Cleaner by Ciro Cesar Maciel. Mais ferramentas em ciromaciel.click")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cleaner by Ciro Cesar Maciel")
        .accessibilityAddTraits(.isLink)
    }
}

/// The bolt, cut from the Infrastructure's logotype (marca-raio.svg, viewBox 80 40 320 420),
/// never redrawn: the same points, filled and stroked 16 units with round joins.
struct LogotypeBolt: View {
    private static let points: [CGPoint] = [
        (144, 50), (298, 50), (307, 58), (308, 68), (265, 160), (380, 164), (388, 169), (390, 185),
        (224, 447), (212, 449), (204, 444), (213, 294), (100, 290), (91, 284), (134, 58),
    ].map { CGPoint(x: $0.0 - 80, y: $0.1 - 40) }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 320, proxy.size.height / 420)
            let path = Path { p in
                p.addLines(Self.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
                p.closeSubpath()
            }
            path.fill(Zen.gray9)
            path.stroke(Zen.gray9, style: StrokeStyle(lineWidth: 16 * scale, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
