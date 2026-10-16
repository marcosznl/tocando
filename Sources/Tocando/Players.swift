import AppKit
import SwiftUI

/// Nome, ícone e preferências de cada player (pelo bundle id).
@MainActor
enum Players {
    /// Nomes mais bonitos que o do .app (ou para apps que não estão instalados).
    private static let knownNames: [String: String] = [
        "com.apple.Music": "Música",
        "com.apple.podcasts": "Podcasts",
        "com.apple.TV": "TV",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.spotify.client": "Spotify",
        "com.tidal.desktop": "TIDAL",
        "com.deezer.deezer-desktop": "Deezer",
        "com.amazon.music": "Amazon Music",
        "com.qobuz.QobuzDesktop": "Qobuz",
        "com.colliderli.iina": "IINA",
        "org.videolan.vlc": "VLC",
        "io.mpv": "mpv",
        "com.marcos.tubeplayer": "iPlayer",
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Google Chrome",
        "org.mozilla.firefox": "Firefox",
        "company.thebrowser.Browser": "Arc",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "Brave",
    ]

    /// Navegadores e players de vídeo: desligados até o usuário ligar
    /// (senão qualquer vídeo aberto vai para o status).
    private static let offByDefault: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.apple.TV", "com.apple.QuickTimePlayerX", "com.colliderli.iina", "org.videolan.vlc", "io.mpv",
    ]

    private static var nameCache: [String: String] = [:]
    private static var iconCache: [String: NSImage] = [:]

    static func name(_ id: String) -> String {
        if let n = knownNames[id] ?? nameCache[id] { return n }
        var n = id.split(separator: ".").last.map(String.init) ?? id
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            n = FileManager.default.displayName(atPath: url.path)
            if n.hasSuffix(".app") { n.removeLast(4) }
        }
        nameCache[id] = n
        return n
    }

    static func icon(_ id: String) -> NSImage {
        if let i = iconCache[id] { return i }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[id] = icon
        return icon
    }

    /// Navegadores e players de vídeo: a música (de outro player) tem
    /// prioridade sobre eles no status.
    static func isVideo(_ id: String) -> Bool {
        offByDefault.contains(id) || id == "com.marcos.tubeplayer" || id == testVideoId
    }

    /// Testes: um player falso que faz papel de navegador.
    private static let testVideoId = ProcessInfo.processInfo.environment["TOCANDO_VIDEO_BUNDLE"]

    static func isEnabled(_ id: String) -> Bool {
        let map = UserDefaults.standard.dictionary(forKey: Prefs.playerEnabled) as? [String: Bool] ?? [:]
        return map[id] ?? !offByDefault.contains(id)
    }

    static func setEnabled(_ id: String, _ on: Bool) {
        var map = UserDefaults.standard.dictionary(forKey: Prefs.playerEnabled) as? [String: Bool] ?? [:]
        map[id] = on
        UserDefaults.standard.set(map, forKey: Prefs.playerEnabled)
    }

    /// App do Discord só deste player (para aparecer "Ouvindo Spotify"), se houver.
    static func clientId(for id: String) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: Prefs.playerClientIds) as? [String: String] ?? [:]
        guard let v = map[id]?.trimmingCharacters(in: .whitespacesAndNewlines), DiscordApps.looksValid(v) else { return nil }
        return v
    }

    static func rawClientId(for id: String) -> String {
        (UserDefaults.standard.dictionary(forKey: Prefs.playerClientIds) as? [String: String])?[id] ?? ""
    }

    static func setClientId(_ value: String, for id: String) {
        var map = UserDefaults.standard.dictionary(forKey: Prefs.playerClientIds) as? [String: String] ?? [:]
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        map[id] = v.isEmpty ? nil : v
        UserDefaults.standard.set(map, forKey: Prefs.playerClientIds)
    }

    /// Players que já tocaram alguma coisa (para a tela Players).
    static var seen: [String] { UserDefaults.standard.stringArray(forKey: Prefs.seenPlayers) ?? [] }

    static func markSeen(_ id: String) {
        var list = seen
        guard !list.contains(id) else { return }
        list.append(id)
        UserDefaults.standard.set(list, forKey: Prefs.seenPlayers)
    }

    static func forget(_ id: String) {
        UserDefaults.standard.set(seen.filter { $0 != id }, forKey: Prefs.seenPlayers)
    }

    /// Texto do botão no status (o link é sempre do Apple Music).
    static let storeButton = "Ouvir no Apple Music"
}

/// Ícone do app do player, do tamanho pedido.
struct PlayerIcon: View {
    let id: String
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: Players.icon(id))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
