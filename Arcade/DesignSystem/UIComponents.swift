import SwiftUI

/// A titled card container used across Home / Recordings / Settings.
struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if let title {
                SectionLabel(title)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// Uppercased section caption.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.textSecondary)
    }
}

/// A label + trailing control row, aligned for forms.
struct SettingRow<Control: View>: View {
    let label: String
    var systemImage: String?
    @ViewBuilder var control: Control

    init(_ label: String, systemImage: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18)
            }
            Text(label).foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Space.lg)
            control
        }
    }
}

/// Filled primary (emerald) button.
struct PrimaryButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
    }
}

/// Filled record (red) button.
struct RecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.record.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
    }
}

/// Borderless symbol button with a tooltip.
struct IconButton: View {
    let systemName: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ systemName: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
