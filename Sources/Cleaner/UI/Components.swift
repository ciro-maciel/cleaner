import SwiftUI
import AppKit

// MARK: - Page (09-painel.md: px 48, pt 40, pb 80, maw 1280, header mb 32)

struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: 1280, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.top, 40)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Zen.gray0)
    }
}

/// The canonical pair in panel form: crumb 10/800 gray.4, title 36/900, subtitle 15/500 gray.6,
/// actions on the right. One primary button per screen.
struct PageHeader<Actions: View>: View {
    let crumb: String
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        PageHeaderLayout {
            VStack(alignment: .leading, spacing: 8) {
                Text(crumb).zenLabel(10)
                Text(title).zenDisplay(36).lineLimit(1).fixedSize()
            }
            Text(subtitle).zenBody(15).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) { actions }.fixedSize()
        }
        .padding(.bottom, 32)
    }
}

extension PageHeader where Actions == EmptyView {
    init(crumb: String, title: String, subtitle: String) {
        self.init(crumb: crumb, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The header's three parts: crumb with title, subtitle, actions. The actions sit on the right,
/// 18 below the top, while the whole title and at least 360 of text fit beside them; in a
/// narrower window they drop 24 below the subtitle, still on the right. The title is never cut, the subtitle stops at 640.
struct PageHeaderLayout: SwiftUI.Layout {
    private struct Frame { var isSide: Bool; var head: CGSize; var sub: CGSize; var subWidth: CGFloat; var act: CGSize }

    private func frame(_ width: CGFloat, _ views: Subviews) -> Frame {
        let head = views[0].sizeThatFits(.unspecified)
        let act = views[2].sizeThatFits(.unspecified)
        let beside = width - act.width - 24
        let isSide = act.width == 0 || beside >= max(head.width, 360)
        let subWidth = min(isSide && act.width > 0 ? beside : width, 640)
        let sub = views[1].sizeThatFits(ProposedViewSize(width: subWidth, height: nil))
        return Frame(isSide: isSide, head: head, sub: sub, subWidth: subWidth, act: act)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1280
        let f = frame(width, subviews)
        let text = f.head.height + 8 + f.sub.height
        if f.act.width == 0 { return CGSize(width: width, height: text) }
        return CGSize(width: width, height: f.isSide ? max(text, 18 + f.act.height) : text + 24 + f.act.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let f = frame(bounds.width, subviews)
        let x = bounds.minX, y = bounds.minY
        subviews[0].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: x, y: y + f.head.height + 8), proposal: ProposedViewSize(width: f.subWidth, height: nil))
        let at = f.isSide ? CGPoint(x: bounds.maxX - f.act.width, y: y + 18)
                          : CGPoint(x: bounds.maxX - f.act.width, y: y + f.head.height + 8 + f.sub.height + 24)
        subviews[2].place(at: at, proposal: .unspecified)
    }
}

// MARK: - Big metric with its note (Lei 5: every strong number carries its verification)

struct BigMetric: View {
    let label: String
    let bytes: Int64
    let note: String
    var size: CGFloat = 96

    var body: some View {
        let (number, unit) = Format.split(bytes)
        VStack(alignment: .leading, spacing: 10) {
            Text(label).zenLabel(11)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number).zenDisplay(size).lineLimit(1).minimumScaleFactor(0.5)
                Text(unit).font(Zen.font(size * 0.3, .black)).foregroundStyle(Zen.gray9)
            }
            Text(note).zenNote().fixedSize(horizontal: false, vertical: true).frame(maxWidth: 460, alignment: .leading)
        }
    }
}

// MARK: - Table (09-painel.md: grid, header gray.1, rows 14/24, rule gray.2)

struct TableCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Zen.gray0)
            .zenBorder()
    }
}

struct TableHeader: View {
    let columns: [(String, CGFloat?)]   // title, fixed width (nil = flexible)
    var leading: CGFloat = 0
    var body: some View {
        HStack(spacing: 12) {
            if leading > 0 { Color.clear.frame(width: leading, height: 1) }
            ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                Text(col.0).zenLabel(10, color: Zen.gray5)
                    .frame(width: col.1, alignment: i == 0 ? .leading : .trailing)
                    .frame(maxWidth: col.1 == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Zen.gray1)
        .overlay(alignment: .bottom) { Rectangle().fill(Zen.gray2).frame(height: 1) }
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Zen.gray2).frame(height: 1) }
}

/// Row hover: gray.1, 120 ms.
struct Hoverable: ViewModifier {
    @State private var hover = false
    var enabled = true
    func body(content: Content) -> some View {
        content
            .background(hover && enabled ? Zen.gray1 : Color.clear)
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

extension View {
    func rowHover(_ enabled: Bool = true) -> some View { modifier(Hoverable(enabled: enabled)) }
}

/// Badge variant="dot": the dot says the category with the least ink.
struct DotBadge: View {
    let text: String
    var color: Color = Zen.gray9
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).zenLabel(10, color: Zen.gray6)
        }
    }
}

// MARK: - Bars

/// Proportion bar: ink for the part, gray.2 for the rest. No color.
struct ShareBar: View {
    let fraction: Double
    var height: CGFloat = 6
    var ink: Color = Zen.gray9
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Zen.gray2)
                Rectangle().fill(ink).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - States

struct EmptyState<Action: View>: View {
    let illustration: String
    let title: String
    let subtitle: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 16) {
            Illustration(name: illustration, size: 168)
            VStack(spacing: 8) {
                Text(title).zenLabel(11, color: Zen.gray5)
                Text(subtitle).zenBody(14).multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

extension EmptyState where Action == EmptyView {
    init(illustration: String, title: String, subtitle: String) {
        self.init(illustration: illustration, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Paper: a declared surface, border gray.2, white.
struct Banner<Action: View>: View {
    let icon: String
    let title: String
    let text: String
    var danger = false
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Icon(name: icon, size: 20, color: danger ? Zen.red7 : Zen.gray9)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Zen.font(14, .bold)).foregroundStyle(Zen.gray9)
                Text(text).zenData(13, color: Zen.gray6).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .padding(20)
        .background(Zen.gray0)
        .zenBorder(danger ? Zen.red2 : Zen.gray3)
    }
}

/// While a scan runs: the "scan" illustration circles slowly, drawn per frame.
struct ScanningAnimation: View {
    var size: CGFloat = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 1.6
            Illustration(name: "scan", size: size * 0.8)
                .rotationEffect(.degrees(sin(t) * 6))
                .offset(x: cos(t) * size * 0.06, y: sin(t) * size * 0.04)
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

/// Toast: success in gray.9, error in red.6. Distinguishable without reading.
struct Toast: Equatable {
    let text: String
    var error = false
}

struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 10) {
            Icon(name: toast.error ? "alert-circle" : "check", size: 16, color: .white)
            Text(toast.text).font(Zen.font(13, .bold)).foregroundStyle(.white).lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(toast.error ? Zen.red6 : Zen.gray9)
    }
}

/// Small icon button for table rows.
struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Icon(name: icon, size: 16, color: hover ? Zen.gray9 : Zen.gray5)
                .frame(width: 28, height: 28)
                .background(hover ? Zen.gray2 : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// App icons from the Finder, looked up once per path.
@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]
    static func image(_ path: String) -> NSImage {
        if let hit = cache[path] { return hit }
        let img = NSWorkspace.shared.icon(forFile: path)
        cache[path] = img
        return img
    }
}
