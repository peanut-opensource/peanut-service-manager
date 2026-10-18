import AppKit
import SwiftUI

struct ManagerTextField: View {
    let title: String
    let placeholder: String
    var hint: String? = nil
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
        VStack(alignment: .leading, spacing: 7) {
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
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ManagerStyle.ink)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
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
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous).fill(ManagerStyle.field))
            .overlay {
                RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous)
                    .strokeBorder(isFocused ? ManagerStyle.accent : ManagerStyle.fieldBorder, lineWidth: isFocused ? 1.5 : 1)
            }
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct ManagerIconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 34
    var iconSize: CGFloat = 16
    var cornerRadius: CGFloat = 9

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
                    .strokeBorder(color.opacity(0.20), lineWidth: 0.8)
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
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .medium, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4.5)
        .background(
            RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ManagerStyle.badgeRadius, style: .continuous)
                .strokeBorder(color.opacity(0.24), lineWidth: 0.8)
        )
    }
}

struct ManagerStatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.38), radius: 2, x: 0, y: 0)
    }
}

struct ManagerMetricPill: View {
    let title: String
    let value: Int
    let icon: String
    var color: Color = ManagerStyle.accent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(ManagerStyle.ink)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ManagerStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ManagerIconBadge(icon: icon, color: tint, size: 32, iconSize: 15, cornerRadius: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .managerTableSurface()
    }
}

struct ManagerEditorHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            ManagerIconBadge(icon: icon, color: ManagerStyle.accent, size: 36, iconSize: 18, cornerRadius: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
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
        HStack(spacing: 14) {
            ManagerIconBadge(icon: icon, color: ManagerStyle.accent, size: 40, iconSize: 20, cornerRadius: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 21, weight: .bold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 20)
            trailing
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
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
        case .mini: return 6
        case .small: return 7
        default: return ManagerStyle.radius
        }
    }

    private var height: CGFloat {
        switch controlSize {
        case .mini: return 24
        case .small: return 28
        default: return 32
        }
    }

    private var accentColor: Color {
        colorScheme == .dark ? ManagerStyle.accentLight : ManagerStyle.accent
    }

    private var active: Bool { isEnabled && (isHovered || configuration.isPressed) }

    private var foreground: Color {
        switch tone {
        case .primary: return .white
        case .start: return .white
        case .accent: return accentColor
        case .danger: return ManagerStyle.danger
        case .secondary: return ManagerStyle.ink
        case .quiet: return ManagerStyle.muted
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            return accentColor
        case .start:
            return accentColor
        case .accent:
            return accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12)
        case .secondary:
            return ManagerStyle.card
        case .quiet:
            return isHovered && isEnabled ? ManagerStyle.ink.opacity(0.06) : .clear
        case .danger:
            return ManagerStyle.danger.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }
    }

    private var border: Color {
        switch tone {
        case .primary, .start:
            return Color.white.opacity(0.18)
        case .quiet:
            return .clear
        case .accent:
            return accentColor.opacity(active ? 0.50 : 0.28)
        case .secondary:
            return active ? ManagerStyle.accent.opacity(0.40) : ManagerStyle.fieldBorder
        case .danger:
            return ManagerStyle.danger.opacity(active ? 0.55 : 0.30)
        }
    }

    private var interactionOverlay: Color {
        switch tone {
        case .primary, .start:
            return configuration.isPressed ? Color.black.opacity(0.15) : (isHovered ? Color.white.opacity(0.12) : .clear)
        case .accent:
            return configuration.isPressed ? accentColor.opacity(0.12) : (isHovered ? accentColor.opacity(0.06) : .clear)
        case .danger:
            return configuration.isPressed ? ManagerStyle.danger.opacity(0.12) : (isHovered ? ManagerStyle.danger.opacity(0.06) : .clear)
        case .secondary, .quiet:
            return configuration.isPressed ? ManagerStyle.ink.opacity(0.08) : (isHovered ? ManagerStyle.ink.opacity(0.04) : .clear)
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: controlSize == .mini ? 11 : 12, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, iconOnly ? 0 : (controlSize == .mini ? 8 : 12))
            .frame(minWidth: height, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(isEnabled ? interactionOverlay : .clear)
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: (tone == .primary || tone == .start) && isEnabled ? accentColor.opacity(configuration.isPressed ? 0.08 : 0.22) : Color.black.opacity(tone == .secondary && isEnabled ? 0.03 : 0),
                radius: (tone == .primary || tone == .start) ? 3 : 1,
                x: 0,
                y: 1
            )
            .opacity(isEnabled ? 1 : 0.40)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.10), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
            .shadow(color: Color.black.opacity(0.035), radius: 8, x: 0, y: 2)
    }
}

private struct ManagerIconSurface: ViewModifier {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var size: CGFloat {
        switch controlSize {
        case .mini: return 24
        case .small: return 28
        default: return 32
        }
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini: return 6
        case .small: return 7
        default: return 8
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: controlSize == .mini ? 11 : 12, weight: .semibold))
            .foregroundColor(ManagerStyle.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(ManagerStyle.card))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ManagerStyle.ink.opacity(isHovered && isEnabled ? 0.06 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHovered && isEnabled ? ManagerStyle.accent.opacity(0.35) : ManagerStyle.fieldBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.40)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }
}

struct ServiceAccessLinks: View {
    let service: Service
    var compact = false

    var body: some View {
        let urls = service.accessURLs
        if let first = urls.first {
            if compact {
                HStack(spacing: 5) {
                    accessLink(first)
                    if urls.count > 1 {
                        Menu {
                            ForEach(Array(urls.dropFirst()), id: \.self) { url in
                                Button(url.absoluteString) { NSWorkspace.shared.open(url) }
                            }
                        } label: {
                            Text("+\(urls.count - 1)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(ManagerStyle.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(ManagerStyle.selection)
                                .clipShape(Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("选择其他租户访问域名")
                        .accessibilityLabel("其他 \(urls.count - 1) 个访问入口")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(urls, id: \.self) { url in accessLink(url) }
                }
            }
        } else {
            Text("未登记访问入口")
                .font(.system(.caption))
                .foregroundColor(ManagerStyle.muted)
                .lineLimit(1)
        }
    }

    private func accessLink(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(ManagerStyle.accent)
        .help("在默认浏览器中打开 \(url.absoluteString)")
    }
}

enum ManagerStyle {
    // 现代科技群青蓝与主色体系
    static let accent = Color(red: 0.08, green: 0.47, blue: 0.98)
    static let accentLight = Color(red: 0.22, green: 0.56, blue: 1.0)
    static let selection = accent.opacity(0.12)

    // 语义色彩体系（自成一体的彩色）
    static let success = Color(red: 0.16, green: 0.70, blue: 0.44) // 运行中 - 翡翠绿
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.13) // 转换/停止中 - 琥珀橙
    static let danger = Color(red: 0.93, green: 0.28, blue: 0.28)  // 失败/危险 - 珊瑚红
    static let purple = Color(red: 0.58, green: 0.35, blue: 0.94)  // MCP/连接 - 紫罗兰
    static let cyan = Color(red: 0.12, green: 0.65, blue: 0.82)    // 资源/目录 - 湖蓝青

    // 结构层级
    static let canvas = Color(NSColor.windowBackgroundColor)
    static let panel = Color(NSColor.controlBackgroundColor)
    static let card = Color(NSColor.controlBackgroundColor)
    static let field = Color(NSColor.textBackgroundColor)
    static let fieldBorder = Color(NSColor.separatorColor).opacity(0.40)
    static let cardBorder = Color(NSColor.separatorColor).opacity(0.28)
    static let ink = Color(NSColor.labelColor)
    static let muted = Color(NSColor.secondaryLabelColor)
    static let subtle = Color(NSColor.tertiaryLabelColor)

    // 统一圆角
    static let radius: CGFloat = 8
    static let cardRadius: CGFloat = 13
    static let badgeRadius: CGFloat = 7
}
