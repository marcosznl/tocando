import SwiftUI

enum SidebarItem: Hashable {
    case nowPlaying, history, players, discord
}

/// O que a janela principal mostra (compartilhado com a barra de menus).
@MainActor
final class Navigator: ObservableObject {
    @Published var selection: SidebarItem? = .nowPlaying
    /// Abre (ou traz para a frente) a janela principal; vem do SwiftUI.
    var openMain: (() -> Void)?

    func show(_ item: SidebarItem) {
        selection = item
        NSApp.activate()
        openMain?()
    }
}

struct MainView: View {
    @EnvironmentObject private var nav: Navigator
    @EnvironmentObject private var presence: Presence
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            detail
                .frame(minWidth: 520, minHeight: 420)
        }
        .onAppear { nav.openMain = { [openWindow] in openWindow(id: "main") } }
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.selection ?? .nowPlaying {
        case .nowPlaying: NowPlayingScreen()
        case .history: HistoryScreen()
        case .players: PlayersScreen()
        case .discord: DiscordScreen()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var nav: Navigator
    var body: some View {
        List(selection: $nav.selection) {
            Section {
                Label("Tocando agora", systemImage: "music.note").tag(SidebarItem.nowPlaying)
                Label("Histórico", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
                Label("Players", systemImage: "hifispeaker.2").tag(SidebarItem.players)
            }
            Section("Status") {
                Label("Discord", systemImage: "person.crop.circle.badge.checkmark").tag(SidebarItem.discord)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatus()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}

/// Rodapé da barra lateral: a música que está no status e um botão para
/// ligar/desligar o compartilhamento.
struct SidebarStatus: View {
    @EnvironmentObject private var presence: Presence
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(sharing: presence.isSharing, enabled: enabled)
            VStack(alignment: .leading, spacing: 1) {
                Text(presence.isSharing ? "No seu status" : "Fora do status")
                    .font(.caption.weight(.semibold))
                Text(presence.isSharing ? (presence.track?.title ?? "") : (presence.blocker ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(enabled ? "Parar de compartilhar no Discord (⌘D)" : "Compartilhar no Discord (⌘D)")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Bolinha verde (no status), cinza (fora) ou vazada (desligado).
struct StatusDot: View {
    let sharing: Bool
    let enabled: Bool

    var body: some View {
        Circle()
            .fill(sharing ? Color.discordGreen : enabled ? Color.secondary.opacity(0.5) : .clear)
            .overlay(Circle().strokeBorder(Color.secondary.opacity(enabled ? 0 : 0.6), lineWidth: 1.2))
            .frame(width: 8, height: 8)
    }
}
