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
            Text(title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(ManagerStyle.ink)
            if let hint, !hint.isEmpty {
                Text(hint).font(.caption).foregroundColor(.secondary)
            }
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ManagerStyle.field))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? ManagerStyle.accent.opacity(0.72) : ManagerStyle.fieldBorder, lineWidth: isFocused ? 1.5 : 1)
                }
                .focused($isFocused)
        }
    }
}

struct ManagerSecureField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(ManagerStyle.ink)
            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ManagerStyle.field))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFocused ? ManagerStyle.accent.opacity(0.72) : ManagerStyle.fieldBorder, lineWidth: isFocused ? 1.5 : 1)
                }
                .focused($isFocused)
        }
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
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.body, design: .rounded).weight(.bold)).foregroundColor(ManagerStyle.ink)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(ManagerStyle.card)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ManagerStyle.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ManagerEditorHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [ManagerStyle.accent, ManagerStyle.accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.title3, design: .rounded).weight(.bold)).foregroundColor(ManagerStyle.ink)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
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

enum ManagerStyle {
    static let accent = Color(red: 0.28, green: 0.42, blue: 0.79)
    static let canvas = Color(NSColor.controlBackgroundColor)
    static let panel = Color(NSColor.windowBackgroundColor)
    static let selection = accent.opacity(0.12)
    static let card = Color(NSColor.textBackgroundColor)
    static let field = Color(NSColor.textBackgroundColor)
    static let fieldBorder = Color.primary.opacity(0.16)
    static let cardBorder = Color.primary.opacity(0.075)
    static let ink = Color(NSColor.labelColor)
    static let success = Color(red: 0.16, green: 0.58, blue: 0.43)
    static let warning = Color(red: 0.78, green: 0.49, blue: 0.16)
    static let danger = Color(red: 0.78, green: 0.27, blue: 0.31)
    static let muted = Color.secondary
}
