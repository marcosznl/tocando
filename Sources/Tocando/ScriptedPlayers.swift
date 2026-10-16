import AppKit

/// Pergunta direto ao Música e ao Spotify o que estão tocando (AppleScript).
///
/// O macOS só informa um "Tocando agora": quem começou a tocar por último. Um
/// vídeo no Safari toma o lugar da música, mesmo com ela ainda tocando; aí o
/// Presence pergunta ao player da música, que continua tendo prioridade.
enum ScriptedPlayers {
    enum Answer {
        /// Tocando ou pausado (`Track.playing`).
        case track(Track)
        /// Parado, sem música.
        case stopped
        /// Sem resposta (player não suporta, sem permissão, erro).
        case unavailable
    }

    private static let scripts: [String: String] = [
        "com.apple.Music": """
            tell application id "com.apple.Music"
                if player state is stopped then return {}
                set t to current track
                return {player state is playing, name of t, artist of t, album of t, duration of t, player position}
            end tell
            """,
        "com.spotify.client": """
            tell application id "com.spotify.client"
                if player state is stopped then return {}
                set t to current track
                return {player state is playing, name of t, artist of t, album of t, (duration of t) / 1000, player position}
            end tell
            """,
    ]

    static func supports(_ bundleId: String) -> Bool { scripts[bundleId] != nil }

    /// NSAppleScript não é para várias threads: uma fila só.
    private static let queue = DispatchQueue(label: "com.marcos.tocando.applescript")

    static func query(_ bundleId: String) async -> Answer {
        guard let source = scripts[bundleId] else { return .unavailable }
        // `tell application` abriria o player se estivesse fechado.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty == false else {
            return .stopped
        }
        return await withCheckedContinuation { cont in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                cont.resume(returning: parse(result, error: error, bundleId: bundleId))
            }
        }
    }

    private static func parse(_ d: NSAppleEventDescriptor?, error: NSDictionary?, bundleId: String) -> Answer {
        guard error == nil, let d else { return .unavailable }
        guard d.numberOfItems >= 6 else { return .stopped }
        func text(_ i: Int) -> String? {
            guard let s = d.atIndex(i)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        guard let title = text(2) else { return .stopped }
        let duration = d.atIndex(5)?.doubleValue ?? 0
        return .track(Track(
            bundleId: bundleId,
            parentBundleId: nil,
            title: title,
            artist: text(3),
            album: text(4),
            duration: duration > 0 ? duration : nil,
            elapsed: d.atIndex(6)?.doubleValue,
            timestamp: .now,
            playing: d.atIndex(1)?.booleanValue ?? false,
            playbackRate: 1,
            artwork: nil))
    }
}
