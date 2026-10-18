import AppKit
import SwiftUI

struct ManagerTextField: View {
    let title: String
    let placeholder: String
    var hint: String? = nil
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ManagerFieldLabel(title: title, hint: hint)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .modifier(ManagerFieldSurface(isFocused: isFocused))
                .focused($isFocused)
        }
    }
}

struct ManagerSecureField: View {
    let title: String
    let placeholder: String
    var hint: String? = nil
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ManagerFieldLabel(title: title, hint: hint)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .modifier(ManagerFieldSurface(isFocused: isFocused))
                .focused($isFocused)
        }
    }
}

private struct ManagerFieldLabel: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(ManagerStyle.ink)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundColor(ManagerStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ManagerFieldSurface: ViewModifier {
    let isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12.5, design: .monospaced))
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous).fill(ManagerStyle.field))
            .overlay {
                RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous)
                    .strokeBorder(isFocused ? ManagerStyle.accent : ManagerStyle.fieldBorder, lineWidth: isFocused ? 1.5 : 1)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.10), value: isFocused)
    }
}

struct ManagerIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 32
    var iconSize: CGFloat = 15
    var cornerRadius: CGFloat = 7

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.30), lineWidth: 0.8)
            )
    }
}

struct ManagerStatusBadge: View {
    let title: String
    let icon: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Circle()
                .fill(color)
                .frame(width: compact ? 5.5 : 6.5, height: compact ? 5.5 : 6.5)
                .shadow(color: color.opacity(0.70), radius: compact ? 2 : 3, x: 0, y: 0)
            Text(title)
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(color)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous)
                .strokeBorder(color.opacity(0.32), lineWidth: 0.8)
        )
    }
}

struct ManagerStatusDot: View {
    let color: Color
    var size: CGFloat = 6.5

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.75), radius: 2.5, x: 0, y: 0)
    }
}

struct ManagerMetricPill: View {
    let title: String
    let value: Int
    let icon: String
    var color: Color = ManagerStyle.accent

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 0.8))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundColor(ManagerStyle.ink)
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(ManagerStyle.muted)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(ManagerStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(ManagerStyle.cardBorder, lineWidth: 0.8)
        )
    }
}

struct ManagerFormCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    init(_ title: String, subtitle: String, icon: String, tint: Color = ManagerStyle.accent, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                ManagerIconBadge(icon: icon, color: tint, size: 30, iconSize: 14, cornerRadius: 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundColor(ManagerStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .managerTableSurface()
    }
}

struct ManagerEditorHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            ManagerIconBadge(icon: icon, color: ManagerStyle.accent, size: 34, iconSize: 16, cornerRadius: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11.5)).foregroundColor(ManagerStyle.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(ManagerStyle.card)
        .overlay(alignment: .bottom) { Rectangle().fill(ManagerStyle.cardBorder).frame(height: 1) }
    }
}

struct ManagerPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let trailing: Trailing

    init(title: String, subtitle: String, icon: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 13) {
            ManagerIconBadge(icon: icon, color: ManagerStyle.accent, size: 36, iconSize: 18, cornerRadius: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 20, weight: .bold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 11.5)).foregroundColor(ManagerStyle.muted)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(ManagerStyle.canvas)
    }
}

extension ManagerPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, icon: String) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

struct ManagerButtonStyle: ButtonStyle {
    enum Tone {
        case primary, start, accent, secondary, quiet, danger
    }

    let tone: Tone
    let iconOnly: Bool

    init(_ tone: Tone = .secondary, iconOnly: Bool = false) {
        self.tone = tone
        self.iconOnly = iconOnly
    }

    func makeBody(configuration: Configuration) -> some View {
        ManagerButtonBody(configuration: configuration, tone: tone, iconOnly: iconOnly)
    }
}

private struct ManagerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tone: ManagerButtonStyle.Tone
    let iconOnly: Bool
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini: return 5.5
        case .small: return 6.5
        default: return ManagerStyle.radius
        }
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: return 23
        case .small: return 27
        default: return 31
        }
    }

    private var accentColor: Color {
        colorScheme == .dark ? ManagerStyle.accentLight : ManagerStyle.accent
    }

    private var active: Bool { isEnabled && (isHovered || configuration.isPressed) }

    private var foreground: Color {
        switch tone {
        case .primary, .start:
            return .white
        case .accent:
            return accentColor
        case .danger:
            return ManagerStyle.danger
        case .secondary:
            return ManagerStyle.ink
        case .quiet:
            return ManagerStyle.muted
        }
    }

    private var background: Color {
        switch tone {
        case .primary, .start:
            return accentColor
        case .accent:
            return accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12)
        case .secondary:
            return ManagerStyle.card
        case .quiet:
            return isHovered && isEnabled ? ManagerStyle.ink.opacity(0.08) : .clear
        case .danger:
            return ManagerStyle.danger.opacity(colorScheme == .dark ? 0.22 : 0.12)
        }
    }

    private var border: Color {
        switch tone {
        case .primary, .start:
            return Color.white.opacity(active ? 0.35 : 0.18)
        case .quiet:
            return .clear
        case .accent:
            return accentColor.opacity(active ? 0.60 : 0.35)
        case .secondary:
            return active ? ManagerStyle.ink.opacity(0.35) : ManagerStyle.fieldBorder
        case .danger:
            return ManagerStyle.danger.opacity(active ? 0.65 : 0.38)
        }
    }

    private var glowColor: Color {
        switch tone {
        case .primary, .start:
            return accentColor.opacity(isHovered ? 0.45 : 0.25)
        case .danger:
            return isHovered ? ManagerStyle.danger.opacity(0.25) : .clear
        default:
            return .clear
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: controlSize == .mini ? 10.5 : 11.5, weight: .semibold, design: (tone == .start || tone == .danger || tone == .secondary) ? .monospaced : .rounded))
            .foregroundColor(foreground)
            .padding(.horizontal, iconOnly ? 0 : (controlSize == .mini ? 7 : 11))
            .frame(minWidth: height, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(configuration.isPressed ? Color.black.opacity(0.12) : (isHovered && isEnabled ? Color.white.opacity(0.08) : .clear))
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: isEnabled ? glowColor : .clear,
                radius: isHovered ? 4 : 2,
                x: 0,
                y: 0.5
            )
            .opacity(isEnabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.08), value: isHovered)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

extension View {
    func managerIconSurface() -> some View {
        modifier(ManagerIconSurface())
    }

    func managerTableSurface() -> some View {
        self
            .background(ManagerStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ManagerStyle.cardRadius, style: .continuous)
                    .strokeBorder(ManagerStyle.cardBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1.5)
    }
}

private struct ManagerIconSurface: ViewModifier {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var size: CGFloat {
        switch controlSize {
        case .mini: return 23
        case .small: return 27
        default: return 31
        }
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini: return 5.5
        case .small: return 6.5
        default: return 7
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: controlSize == .mini ? 10.5 : 11.5, weight: .semibold))
            .foregroundColor(ManagerStyle.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(ManagerStyle.card))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ManagerStyle.ink.opacity(isHovered && isEnabled ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHovered && isEnabled ? ManagerStyle.accent.opacity(0.45) : ManagerStyle.fieldBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.08), value: isHovered)
    }
}

struct ServiceAccessLinks: View {
    let service: Service
    var compact = false

    var body: some View {
        let urls = service.accessURLs
        if let first = urls.first {
            if compact {
                HStack(spacing: 4) {
                    accessLink(first)
                    if urls.count > 1 {
                        Menu {
                            ForEach(Array(urls.dropFirst()), id: \.self) { url in
                                Button(url.absoluteString) { NSWorkspace.shared.open(url) }
                            }
                        } label: {
                            Text("+\(urls.count - 1)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(ManagerStyle.accent)
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(ManagerStyle.selection)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ManagerStyle.accent.opacity(0.25), lineWidth: 0.8))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("选择其他租户访问域名")
                        .accessibilityLabel("其他 \(urls.count - 1) 个访问入口")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(urls, id: \.self) { url in accessLink(url) }
                }
            }
        } else {
            Text("未登记访问入口")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(ManagerStyle.muted)
                .lineLimit(1)
        }
    }

    private func accessLink(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 3) {
                Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(ManagerStyle.accent)
        .help("在默认浏览器中打开 \(url.absoluteString)")
    }
}

enum ManagerStyle {
    // 方案 B：高科技黑曜极客风色彩系统 (Electric & Linear Tech Palette)
    static let accent = Color(red: 0.0, green: 0.40, blue: 1.0)       // 电光科技蓝 #0066FF
    static let accentLight = Color(red: 0.15, green: 0.52, blue: 1.0)
    static let selection = accent.opacity(0.14)

    // 状态与功能电光色
    static let success = Color(red: 0.04, green: 0.74, blue: 0.48)    // 薄荷电光绿 #0ABD7A
    static let warning = Color(red: 1.0, green: 0.69, blue: 0.12)     // 日光琥珀橙 #FFB020
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)     // 极客绯红 #EF4444
    static let purple = Color(red: 0.49, green: 0.36, blue: 0.99)     // 电光紫罗兰 #7D5CFC
    static let cyan = Color(red: 0.0, green: 0.71, blue: 0.85)        // 赛博湖青 #00B5D8

    // 结构与极细线条
    static let canvas = Color(NSColor.windowBackgroundColor)
    static let panel = Color(NSColor.controlBackgroundColor)
    static let card = Color(NSColor.controlBackgroundColor)
    static let field = Color(NSColor.textBackgroundColor)
    static let fieldBorder = Color(NSColor.separatorColor).opacity(0.38)
    static let cardBorder = Color(NSColor.separatorColor).opacity(0.24)
    static let ink = Color(NSColor.labelColor)
    static let muted = Color(NSColor.secondaryLabelColor)
    static let subtle = Color(NSColor.tertiaryLabelColor)

    // 方案 B 极客硬朗圆角规范
    static let radius: CGFloat = 6.5       // 紧凑硬朗按键/输入框圆角
    static let cardRadius: CGFloat = 9.0   // 紧凑硬朗卡片圆角
    static let badgeRadius: CGFloat = 5.0  // 极细状态胶囊圆角
}
