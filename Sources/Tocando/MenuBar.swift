import AppKit
import SwiftUI

/// Ícone da barra de menus: nota (no status), pausa (fora do status) ou
/// riscado (compartilhamento desligado).
struct MenuBarLabel: View {
    @ObservedObject var presence: Presence
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some View {
        Image(systemName: !enabled ? "speaker.slash" : presence.isSharing ? "music.note" : "pause")
    }
}

/// Painel da barra de menus: a música, os controles, o status no Discord e atalhos.
struct MenuBarPanel: View {
    @EnvironmentObject private var presence: Presence
    @EnvironmentObject private var nav: Navigator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tocando").font(.headline)
                Spacer()
                Toggle("Compartilhar", isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help(enabled ? "Parar de compartilhar no Discord" : "Compartilhar no Discord")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if let t = presence.track {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        CoverView(data: t.artwork, url: presence.match?.artworkURL, size: 64, radius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.body.weight(.semibold)).lineLimit(2)
                            if let a = t.artist { Text(a).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                            HStack(spacing: 4) {
                                PlayerIcon(id: t.playerId, size: 12)
                                Text(Players.name(t.playerId))
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        ProgressRow(track: t, now: ctx.date)
                    }
                    PlayerControls(playing: t.playing, size: 15)
                }
                .padding(12)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "music.note").font(.title2).foregroundStyle(.tertiary)
                    Text("Nada tocando").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }
            Divider()
            HStack(spacing: 8) {
                StatusDot(sharing: presence.isSharing, enabled: enabled)
                Text(presence.isSharing ? "No seu status do Discord" : (presence.blocker ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            HStack {
                Button("Abrir o Tocando") { showMain() }
                Spacer()
                Button {
                    NSApp.activate()   // senão os Ajustes abrem atrás dos outros apps
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                    .help("Ajustes")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Sair do Tocando")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
    }

    private func showMain() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        openWindow(id: "main")
    }
}
