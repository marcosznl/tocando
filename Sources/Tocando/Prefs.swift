import AppKit
import ServiceManagement
import SwiftUI

/// Chaves do UserDefaults (também usadas com @AppStorage nas telas).
enum Prefs {
    static let enabled = "enabled"
    static let clientId = "discordClientId"
    /// O que vem depois de "Ouvindo": "artist", "title" ou "app".
    static let listeningTo = "listeningTo"
    static let showPaused = "showPaused"
    static let showButtons = "showButtons"
    static let showAlbum = "showAlbum"
    static let appearance = "appearance"
    static let playerEnabled = "playerEnabled"
    static let seenPlayers = "seenPlayers"
    /// Application ID de um app do Discord com o nome de cada player.
    static let playerClientIds = "playerClientIds"
    /// Músicas do Spotify ficam com a integração oficial do Discord (só podcasts aqui).
    static let spotifyOfficial = "spotifyOfficial"
    /// Quando o app abre sozinho (LaunchMode).
    static let launchMode = "launchMode"
    /// O ícone some enquanto o app dorme (lido pelo MenuBarExtra).
    static let iconHidden = "iconHidden"

    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static var clientIdValue: String {
        (UserDefaults.standard.string(forKey: clientId) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tema do app: "" segue o sistema, "light" ou "dark".
    @MainActor
    static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: appearance) ?? "" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

extension Color {
    /// Roxo do ícone.
    static let accent = Color(red: 0.40, green: 0.30, blue: 0.93)
    /// Fundo do cartão de atividade, como no perfil do Discord.
    static let discordCard = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let discordGreen = Color(red: 0.14, green: 0.65, blue: 0.35)
}

/// Quando o Tocando abre sozinho.
enum LaunchMode: String {
    /// Só quando você abre.
    case manual
    /// Ao entrar no Mac (Itens de Início).
    case login
    /// Junto com o Discord: abre ao entrar no Mac, mas dorme (sem ícone, sem
    /// ler a música) enquanto o Discord estiver fechado. O macOS não abre um
    /// app quando outro abre, então é assim que dá.
    case discord

    @MainActor
    static var current: LaunchMode {
        if let raw = UserDefaults.standard.string(forKey: Prefs.launchMode), let m = LaunchMode(rawValue: raw) {
            return m
        }
        return LoginItem.isOn ? .login : .manual
    }

    /// Muda o modo e liga/desliga o item de início. Devolve o erro, se houver.
    @MainActor
    static func set(_ mode: LaunchMode) -> String? {
        let error = LoginItem.set(mode != .manual)
        UserDefaults.standard.set((error == nil ? mode : current).rawValue, forKey: Prefs.launchMode)
        return error
    }
}

/// Abrir ao entrar no Mac (Itens de Início).
enum LoginItem {
    static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    /// Devolve o erro, se não deu certo.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Não deu para mudar: \(error.localizedDescription)"
        }
    }
}

enum Links {
    static let developerPortal = URL(string: "https://discord.com/developers/applications")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

/// "3:07" ou "1:02:03".
func formatTime(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
    return String(format: "%d:%02d", s / 60, s % 60)
}
