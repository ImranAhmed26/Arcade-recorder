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
    @EnvironmentObject private var auth: AuthService
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
            avatar
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(auth.currentUser?.displayName ?? "Signed in")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text(secondaryLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            IconButton("rectangle.portrait.and.arrow.right", help: "Sign out") {
                appState.signOut()
            }
        }
        .padding(Theme.Space.md)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = auth.currentUser?.avatarURL {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                initialsAvatar
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Theme.primaryTint)
            .overlay(
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.primary)
            )
    }

    /// Email if present, else a generic label distinguishing Google vs guest.
    private var secondaryLine: String {
        if let email = auth.currentUser?.email { return email }
        return (auth.currentUser?.isGuest ?? true) ? "Local account" : "Google account"
    }

    private var initials: String {
        let base = auth.currentUser?.displayName ?? "A"
        return String(base.prefix(1)).uppercased()
    }
}
