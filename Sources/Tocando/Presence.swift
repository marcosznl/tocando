import Combine
import Foundation

/// O que aparece no status do Discord (também desenhado na tela, como prévia).
struct ActivityPreview: Equatable {
    /// "Ouvindo Spotify": no perfil, sempre o nome do app do Discord.
    var header: String
    /// "Ouvindo Billie Eilish": a linha curta da lista de membros.
    var memberLine: String
    var details: String
    var state: String?
    var largeText: String?
    var imageURL: String?
    var start: Date?
    var end: Date?
    var buttonURL: String?
    var paused: Bool
}

/// Junta o "Tocando agora" do macOS, os ajustes e o Discord.
@MainActor
final class Presence: ObservableObject {
    let monitor = NowPlayingMonitor()
    let history = History()
    private let discord = DiscordIPC()

    @Published private(set) var track: Track?
    @Published private(set) var match: StoreMatch?
    @Published private(set) var discordState: DiscordIPC.State = .idle
    @Published private(set) var lastError: String?
    /// O status que a música atual teria (nil = nada a mostrar).
    @Published private(set) var preview: ActivityPreview?
    /// Por que não está no status agora (nil = está).
    @Published private(set) var blocker: String? = "Nada tocando"

    var isSharing: Bool { blocker == nil }

    /// O app do Discord em uso agora (o do player, ou o principal).
    @Published private(set) var activeClientId = ""

    private var currentKey: String?
    private var lookup: Task<Void, Never>?
    private var bag: Set<AnyCancellable> = []

    init() {
        discord.onState = { [weak self] s in
            self?.discordState = s
            if case .connected = s { self?.lastError = nil }
            self?.refresh()
        }
        discord.onError = { [weak self] msg in self?.lastError = msg }
        monitor.$track
            .sink { [weak self] t in self?.trackChanged(t) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
        // O nome do app chega depois: a prévia mostra "Ouvindo <nome>".
        DiscordApps.shared.$info
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
    }

    func start() {
        monitor.start()
        refresh()
    }

    func stop() {
        monitor.stop()
        discord.shutdown()
    }

    private func trackChanged(_ t: Track?) {
        track = t
        if let t { Players.markSeen(t.playerId) }
        if t?.key != currentKey {
            currentKey = t?.key
            match = nil
            lookup?.cancel()
            if let t {
                let key = t.key
                lookup = Task { [weak self] in
                    let m = await ArtworkLookup.shared.find(title: t.title, artist: t.artist, album: t.album)
                    guard let self, !Task.isCancelled, self.currentKey == key, let m else { return }
                    self.match = m
                    self.history.setMatch(m, key: key)
                    self.refresh()
                }
            }
        }
        if let t, t.playing { history.record(t) }
        refresh()
    }

    /// Recalcula o status e manda para o Discord (o cliente só envia se mudou).
    func refresh() {
        let enabled = Prefs.bool(Prefs.enabled, default: true)
        // App do Discord do player que está tocando ("Ouvindo Spotify"), senão
        // o principal. Sem música, fica no último: não reconecta à toa.
        let mainId = Prefs.clientIdValue
        let playerIds = Set(Players.seen.compactMap { Players.clientId(for: $0) })
        let clientId = track.flatMap { Players.clientId(for: $0.playerId) }
            ?? (track == nil && playerIds.contains(activeClientId) ? activeClientId : mainId)
        if activeClientId != clientId { activeClientId = clientId }
        discord.setClientId(enabled ? clientId : "")

        let showPaused = Prefs.bool(Prefs.showPaused, default: false)
        var eligible: Track?
        var why: String?
        if let t = track {
            if !Players.isEnabled(t.playerId) {
                why = "\(Players.name(t.playerId)) não é compartilhado"
            } else if !t.playing && !showPaused {
                why = "Pausado"
            } else {
                eligible = t
            }
        } else {
            why = "Nada tocando"
        }
        let p = eligible.map(makePreview)
        if preview != p { preview = p }

        if !enabled {
            why = "Compartilhamento desligado"
        } else if why == nil {
            switch discordState {
            case .idle: why = clientId.isEmpty ? "Falta conectar ao Discord" : "Conectando ao Discord…"
            case .notRunning: why = "O Discord não está aberto"
            case .connecting: why = "Conectando ao Discord…"
            case .rejected(let msg): why = "O Discord recusou: \(msg)"
            case .connected: why = nil
            }
        }
        if blocker != why { blocker = why }
        discord.setActivity(enabled ? p.map(Self.payload) : nil)
    }

    private func makePreview(_ t: Track) -> ActivityPreview {
        let mode = UserDefaults.standard.string(forKey: Prefs.listeningTo) ?? "artist"
        let appName = DiscordApps.shared.name(activeClientId) ?? "seu app no Discord"
        let memberLine: String
        switch mode {
        case "title": memberLine = "Ouvindo \(t.title)"
        case "app": memberLine = "Ouvindo \(appName)"
        default: memberLine = "Ouvindo \(t.artist ?? t.title)"
        }
        let start = t.startDate
        var end: Date?
        if let start, let d = t.duration { end = start.addingTimeInterval(d / ((t.playbackRate ?? 1) > 0 ? t.playbackRate! : 1)) }
        let album = Prefs.bool(Prefs.showAlbum, default: true) ? t.album : nil
        return ActivityPreview(
            header: "Ouvindo \(appName)",
            memberLine: memberLine,
            details: t.title,
            state: t.artist,
            largeText: t.playing ? album : (album.map { "Pausado · \($0)" } ?? "Pausado"),
            imageURL: match?.artworkURL,
            start: start,
            end: end,
            buttonURL: Prefs.bool(Prefs.showButtons, default: true) ? match?.trackURL : nil,
            paused: !t.playing)
    }

    /// A atividade no formato do Discord (tipo 2 = "Ouvindo").
    private static func payload(_ p: ActivityPreview) -> [String: Any] {
        let mode = UserDefaults.standard.string(forKey: Prefs.listeningTo) ?? "artist"
        var a: [String: Any] = [
            "type": 2,
            // O que vem depois de "Ouvindo": 0 = nome do app, 1 = state, 2 = details.
            "status_display_type": mode == "title" ? 2 : mode == "app" ? 0 : (p.state == nil ? 2 : 1),
            "details": fit(p.details),
        ]
        if let s = p.state { a["state"] = fit(s) }
        var assets: [String: Any] = [:]
        if let url = p.imageURL { assets["large_image"] = url }
        if let text = p.largeText { assets["large_text"] = fit(text) }
        if !assets.isEmpty { a["assets"] = assets }
        if !p.paused, let start = p.start {
            var ts: [String: Any] = ["start": Int(start.timeIntervalSince1970 * 1000)]
            if let end = p.end { ts["end"] = Int(end.timeIntervalSince1970 * 1000) }
            a["timestamps"] = ts
        }
        if let url = p.buttonURL { a["buttons"] = [["label": Players.storeButton, "url": url]] }
        return a
    }

    /// O Discord aceita textos de 2 a 128 caracteres.
    private static func fit(_ s: String) -> String {
        if s.count < 2 { return s + "\u{200B}" }
        if s.count > 128 { return String(s.prefix(127)) + "…" }
        return s
    }
}
