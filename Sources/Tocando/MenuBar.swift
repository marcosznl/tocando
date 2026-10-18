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

/// Painel do ícone: a música e os controles, o status no Discord e as telas
/// do app, como um menu.
struct MenuBarPanel: View {
    @EnvironmentObject private var presence: Presence
    @EnvironmentObject private var nav: Navigator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.enabled) private var enabled = true
    @AppStorage(Prefs.launchMode) private var launchMode = LaunchMode.manual.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tocando").font(.headline)
                Spacer()
                PanelSwitch(isOn: $enabled)
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
            if presence.track != nil || !enabled {   // sem música, o "Nada tocando" acima já diz
                HStack(spacing: 8) {
                    StatusDot(sharing: presence.isSharing, enabled: enabled)
                    Text(presence.isSharing ? "No seu status do Discord" : (presence.blocker ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            Divider()
            VStack(spacing: 0) {
                MenuRow("Tocando agora", systemImage: "music.note") { nav.show(.nowPlaying) }
                MenuRow("Histórico", systemImage: "clock.arrow.circlepath") { nav.show(.history) }
                MenuRow("Players", systemImage: "hifispeaker.2") { nav.show(.players) }
                MenuRow("Discord", systemImage: "person.crop.circle.badge.checkmark") { nav.show(.discord) }
            }
            .padding(5)
            Divider()
            VStack(spacing: 0) {
                MenuRow("Abrir ao entrar no Mac", systemImage: "power.circle", checked: launchMode == LaunchMode.login.rawValue) {
                    _ = LaunchMode.set(launchMode == LaunchMode.login.rawValue ? .manual : .login)
                }
                MenuRow("Abrir junto com o Discord", systemImage: "bubble.left.and.bubble.right",
                        checked: launchMode == LaunchMode.discord.rawValue) {
                    _ = LaunchMode.set(launchMode == LaunchMode.discord.rawValue ? .manual : .discord)
                }
                .help("Fica dormindo, sem ícone, enquanto o Discord estiver fechado")
                MenuRow("Ajustes…", systemImage: "gearshape", shortcut: "⌘,") {
                    NSApp.activate()   // senão os Ajustes abrem atrás dos outros apps
                    openSettings()
                }
                MenuRow("Sair do Tocando", systemImage: "xmark.circle", shortcut: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(5)
        }
        .frame(width: 320)
        .onAppear {
            if nav.openMain == nil { nav.openMain = { [openWindow] in openWindow(id: "main") } }
        }
    }
}

/// Linha de menu: ícone, texto, marca ou atalho, com destaque ao passar o mouse.
struct MenuRow: View {
    let title: String
    let systemImage: String
    var checked: Bool?
    var shortcut: String?
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, systemImage: String, checked: Bool? = nil, shortcut: String? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.checked = checked
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(hover ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(title)
                Spacer()
                if checked == true {
                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                }
                if let shortcut {
                    Text(shortcut).foregroundStyle(hover ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(hover ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(hover ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Interruptor do painel, desenhado em SwiftUI (o nativo não aparece nas
/// fotos do --snapshot, que desenham o painel fora da tela).
struct PanelSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accent : Color.secondary.opacity(0.35))
            .frame(width: 32, height: 19)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
            .contentShape(Capsule())
            .onTapGesture { isOn.toggle() }
            .accessibilityElement()
            .accessibilityLabel("Compartilhar no Discord")
            .accessibilityValue(isOn ? "ligado" : "desligado")
            .accessibilityAddTraits(.isButton)
    }
}
