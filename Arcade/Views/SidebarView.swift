import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case home, recordings, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .recordings: return "Recordings"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .recordings: return "square.stack"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selection: SidebarSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "record.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.primary)
                Text("Arcade")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, Theme.Space.lg)

            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)
            Divider()
            accountFooter
        }
    }

    private var accountFooter: some View {
        HStack(spacing: Theme.Space.sm) {
            Circle()
                .fill(Theme.primaryTint)
                .overlay(
                    Text(initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                )
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(appState.accountEmail ?? "Signed in")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text("Local account")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            IconButton("rectangle.portrait.and.arrow.right", help: "Sign out") {
                appState.signOut()
            }
        }
        .padding(Theme.Space.md)
    }

    private var initials: String {
        let email = appState.accountEmail ?? "A"
        return String(email.prefix(1)).uppercased()
    }
}
