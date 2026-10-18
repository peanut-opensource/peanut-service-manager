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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ManagerStyle.ink)
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
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
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(tint)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
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
        .padding(20)
        .managerTableSurface()
    }
}

struct ManagerEditorHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(ManagerStyle.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
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
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(ManagerStyle.accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 23, weight: .semibold)).foregroundColor(ManagerStyle.ink)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 20)
            trailing
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
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
        case primary, accent, secondary, quiet, danger
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

    private var cornerRadius: CGFloat { iconOnly ? 8 : ManagerStyle.radius }

    private var height: CGFloat {
        switch controlSize {
        case .mini: return 24
        case .small: return 28
        default: return 34
        }
    }

    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.56, green: 0.68, blue: 1) : ManagerStyle.accent
    }

    private var active: Bool { isEnabled && (isHovered || configuration.isPressed) }

    private var foreground: Color {
        switch tone {
        case .primary: return .white
        case .accent: return accent
        case .danger: return ManagerStyle.danger
        case .secondary: return ManagerStyle.ink
        case .quiet: return ManagerStyle.muted
        }
    }

    private var background: Color {
        switch tone {
        case .primary: return ManagerStyle.accent
        case .accent: return accent.opacity(colorScheme == .dark ? 0.16 : 0.09)
        case .secondary: return ManagerStyle.card
        case .quiet: return .clear
        case .danger: return ManagerStyle.danger.opacity(colorScheme == .dark ? 0.16 : 0.08)
        }
    }

    private var border: Color {
        switch tone {
        case .primary: return Color.white.opacity(0.12)
        case .quiet: return .clear
        case .accent: return accent.opacity(active ? 0.48 : 0.26)
        case .secondary: return ManagerStyle.fieldBorder
        case .danger: return ManagerStyle.danger.opacity(active ? 0.48 : 0.25)
        }
    }

    private var interactionColor: Color {
        switch tone {
        case .primary: return configuration.isPressed ? .black : .white
        case .accent: return accent
        case .danger: return ManagerStyle.danger
        case .secondary, .quiet: return ManagerStyle.ink
        }
    }

    var body: some View {
        configuration.label
            .font(.system(size: controlSize == .mini ? 11 : 12, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, iconOnly ? 0 : (controlSize == .mini ? 9 : 12))
            .frame(minWidth: height, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(interactionColor.opacity(isEnabled ? (configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)) : 0))
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: tone == .primary && isEnabled ? ManagerStyle.accent.opacity(configuration.isPressed ? 0.05 : 0.18) : .clear, radius: 3, x: 0, y: 1)
            .opacity(isEnabled ? 1 : 0.42)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
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
            .clipShape(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ManagerStyle.radius, style: .continuous).strokeBorder(ManagerStyle.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 2)
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
        default: return 34
        }
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: controlSize == .mini ? 11 : 12, weight: .semibold))
            .foregroundColor(ManagerStyle.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ManagerStyle.card))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ManagerStyle.ink.opacity(isHovered && isEnabled ? 0.08 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ManagerStyle.fieldBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct ServiceAccessLink: View {
    let service: Service

    var body: some View {
        if let url = service.accessURL {
            Link(destination: url) {
                HStack(spacing: 5) {
                    Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "arrow.up.right.square").font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(ManagerStyle.accent)
            .help("在默认浏览器中打开 \(url.absoluteString)")
        } else {
            Text(service.accessAddress ?? "未登记主机地址和端口")
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

enum ManagerStyle {
    static let accent = Color(red: 0.25, green: 0.38, blue: 0.79)
    static let canvas = Color(NSColor.windowBackgroundColor)
    static let panel = Color(NSColor.controlBackgroundColor)
    static let selection = accent.opacity(0.10)
    static let card = Color(NSColor.controlBackgroundColor)
    static let field = Color(NSColor.textBackgroundColor)
    static let fieldBorder = Color(NSColor.separatorColor).opacity(0.55)
    static let cardBorder = Color(NSColor.separatorColor).opacity(0.35)
    static let ink = Color(NSColor.labelColor)
    static let success = Color(NSColor.systemGreen)
    static let warning = Color(NSColor.systemOrange)
    static let danger = Color(NSColor.systemRed)
    static let muted = Color.secondary
    static let radius: CGFloat = 12
}
