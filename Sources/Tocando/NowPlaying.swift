import AppKit
import Foundation

/// O que o macOS diz que está tocando (o mesmo da Central de Controle).
struct Track: Equatable {
    var bundleId: String
    /// App "dono" quando quem toca é um processo auxiliar (ex: aba do Safari).
    var parentBundleId: String?
    var title: String
    var artist: String?
    var album: String?
    /// Segundos.
    var duration: Double?
    /// Posição (segundos) no instante `timestamp`.
    var elapsed: Double?
    var timestamp: Date?
    var playing: Bool
    var playbackRate: Double?
    var artwork: Data?

    /// O player que aparece para o usuário.
    var playerId: String { parentBundleId ?? bundleId }

    /// Identifica a música (sem posição nem estado).
    var key: String { [playerId, title, artist ?? "", album ?? ""].joined(separator: "\u{1}") }

    /// Posição estimada agora.
    func position(at now: Date = .now) -> Double? {
        guard let elapsed else { return nil }
        var p = elapsed
        if playing, let timestamp { p += now.timeIntervalSince(timestamp) * rate }
        if let duration, duration > 0 { p = min(p, duration) }
        return max(0, p)
    }

    /// Quando a música "começou", para o Discord mostrar a barra de progresso.
    /// Calculado de `timestamp`, não de agora: não muda a cada atualização.
    var startDate: Date? {
        guard playing, let elapsed, let timestamp else { return nil }
        return timestamp.addingTimeInterval(-elapsed / rate)
    }

    private var rate: Double { (playbackRate ?? 1) > 0 ? (playbackRate ?? 1) : 1 }
}

/// Lê o "Tocando agora" do macOS em tempo real.
///
/// Desde o macOS 15.4 só apps da Apple podem usar o MediaRemote. O
/// MediaRemoteAdapter (ungive/mediaremote-adapter, BSD-3) contorna isso: o
/// /usr/bin/perl, que tem essa permissão, carrega um framework que imprime as
/// mudanças em JSON, uma por linha.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    /// O adaptador não está rodando (e por quê).
    @Published private(set) var failure: String?

    enum Command: Int { case togglePlayPause = 2, next = 4, previous = 5 }

    private var process: Process?
    private var state: [String: Any] = [:]
    private var buffer = Data()
    private var restartDelay: TimeInterval = 1
    private var stopped = false

    private struct Adapter { let script: String; let framework: String }

    private static var adapter: Adapter? {
        guard let res = Bundle.main.resourceURL, let fw = Bundle.main.privateFrameworksURL else { return nil }
        let script = res.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = fw.appendingPathComponent("MediaRemoteAdapter.framework").path
        let fm = FileManager.default
        guard fm.fileExists(atPath: script), fm.fileExists(atPath: framework) else { return nil }
        return Adapter(script: script, framework: framework)
    }

    func start() {
        stopped = false
        guard process == nil else { return }
        guard let adapter = Self.adapter else {
            failure = "O leitor de música não está no app. Gere o app com ./build.sh."
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [adapter.script, adapter.framework, "stream", "--micros", "--debounce=150"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        // Linhas chegam em pedaços; a fila principal mantém a ordem.
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        p.terminationHandler = { [weak self] proc in
            proc.standardOutput.flatMap { $0 as? Pipe }?.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.terminated(proc) } }
        }
        do {
            try p.run()
            process = p
        } catch {
            failure = "Não consegui iniciar o leitor de música: \(error.localizedDescription)"
            scheduleRestart()
        }
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
        state = [:]
        buffer.removeAll()
        if track != nil { track = nil }
    }

    /// Tocar/pausar, próxima e anterior no player que está tocando.
    func send(_ command: Command) {
        guard let adapter = Self.adapter else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [adapter.script, adapter.framework, "send", String(command.rawValue)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func terminated(_ proc: Process) {
        guard proc === process else { return }
        process = nil
        buffer.removeAll()
        guard !stopped else { return }
        failure = "O leitor de música parou (código \(proc.terminationStatus)). Tentando de novo…"
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                self.start()
            }
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return }
        if obj["diff"] as? Bool ?? false {
            // Música nova sem capa ainda: não fica com a capa da anterior.
            let identity = ["bundleIdentifier", "title", "artist", "album"]
            if identity.contains(where: { payload[$0] != nil }), payload["artworkData"] == nil {
                state["artworkData"] = nil
            }
            for (k, v) in payload { state[k] = v is NSNull ? nil : v }
        } else {
            state = payload
        }
        failure = nil
        restartDelay = 1
        let new = Self.parse(state)
        if new != track { track = new }
    }

    static func parse(_ s: [String: Any]) -> Track? {
        // Às vezes vem só o número do processo.
        let pidBundle = (s["processIdentifier"] as? NSNumber)
            .flatMap { NSRunningApplication(processIdentifier: $0.int32Value)?.bundleIdentifier }
        guard let bundle = (s["bundleIdentifier"] as? String) ?? pidBundle,
              let title = (s["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return nil }
        func text(_ k: String) -> String? {
            guard let v = (s[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        func micros(_ k: String) -> Double? { (s[k] as? NSNumber).map { $0.doubleValue / 1_000_000 } }
        return Track(
            bundleId: bundle,
            parentBundleId: text("parentApplicationBundleIdentifier"),
            title: title,
            artist: text("artist"),
            album: text("album"),
            duration: micros("durationMicros").flatMap { $0 > 0 ? $0 : nil },
            elapsed: micros("elapsedTimeMicros"),
            timestamp: micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) },
            playing: s["playing"] as? Bool ?? false,
            playbackRate: (s["playbackRate"] as? NSNumber)?.doubleValue,
            artwork: (s["artworkData"] as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        )
    }
}
