import Darwin
import Foundation

/// Fala com o app do Discord aberto neste Mac pelo socket local
/// (`$TMPDIR/discord-ipc-N`), o mesmo usado pelo "Rich Presence" dos jogos.
///
/// Cada mensagem: código (UInt32 little-endian), tamanho (UInt32 LE) e JSON.
/// Tudo roda numa fila só; quem usa só diz qual atividade quer no status
/// (`setActivity`) e o cliente conecta, reconecta e respeita o limite do
/// Discord (5 atualizações a cada 20 s) sozinho.
final class DiscordIPC: @unchecked Sendable {
    enum State: Equatable {
        /// Sem Client ID, ou desligado.
        case idle
        /// O Discord não está aberto (tenta de novo a cada 5 s).
        case notRunning
        case connecting
        case connected(user: String)
        /// O Discord recusou (ex: Client ID inválido).
        case rejected(String)
    }

    /// Chamado na fila principal.
    var onState: (@MainActor (State) -> Void)?
    /// Erro de uma atualização do status (na fila principal).
    var onError: (@MainActor (String) -> Void)?

    private enum Op: UInt32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    private let queue = DispatchQueue(label: "com.marcos.tocando.discord")
    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var timer: DispatchSourceTimer?
    private var inbox = Data()
    private var clientId = ""
    private var ready = false
    private var state: State = .idle
    /// Atividade desejada (nil = nenhuma) e a última enviada.
    private var desired: [String: Any]?
    private var lastSent: Data?
    private var sendTimes: [Date] = []
    private var flushScheduled = false
    /// Depois de uma recusa, espera o Client ID mudar (ou 30 s).
    private var retryAfter = Date.distantPast

    init() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 5)
        t.setEventHandler { [weak self] in self?.connectIfNeeded() }
        t.resume()
        timer = t
    }

    /// Client ID do app criado no portal do Discord ("" desliga).
    func setClientId(_ id: String) {
        queue.async { [self] in
            guard id != clientId else { return }
            clientId = id
            retryAfter = .distantPast
            disconnect(to: id.isEmpty ? .idle : .connecting)
            connectIfNeeded()
        }
    }

    /// A atividade a mostrar no status, ou nil para limpar.
    func setActivity(_ activity: [String: Any]?) {
        queue.async { [self] in
            desired = activity
            flush()
        }
    }

    /// Ao sair do app: fechar o socket já tira a atividade do status.
    func shutdown() {
        queue.sync { disconnect(to: .idle) }
    }

    // MARK: - Conexão

    private func connectIfNeeded() {
        guard fd < 0, !clientId.isEmpty, Date() >= retryAfter else { return }
        guard let s = Self.openSocket() else {
            setState(.notRunning)
            return
        }
        fd = s
        ready = false
        lastSent = nil
        inbox.removeAll()
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
        src.setEventHandler { [weak self] in self?.readAvailable() }
        src.resume()
        readSource = src
        setState(.connecting)
        write(.handshake, ["v": 1, "client_id": clientId])
    }

    private static func openSocket() -> Int32? {
        let env = ProcessInfo.processInfo.environment
        var dirs: [String] = []
        if let test = env["TOCANDO_IPC_DIR"] {
            dirs = [test]   // testes: só esta pasta (um Discord falso), nunca o de verdade
        } else {
            if let t = env["TMPDIR"] { dirs.append(t) }
            dirs.append(NSTemporaryDirectory())
            dirs.append("/tmp/")
        }
        var seen = Set<String>()
        for dir in dirs {
            let base = dir.hasSuffix("/") ? dir : dir + "/"
            guard seen.insert(base).inserted else { continue }
            for i in 0..<10 {
                if let s = connect(path: base + "discord-ipc-\(i)") { return s }
            }
        }
        return nil
    }

    private static func connect(path: String) -> Int32? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard r == 0 else {
            close(s)
            return nil
        }
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        return s
    }

    private func disconnect(to newState: State) {
        if let src = readSource {
            readSource = nil
            src.cancel()
        }
        if fd >= 0 {
            close(fd)
            fd = -1
        }
        ready = false
        lastSent = nil
        setState(newState)
    }

    private func setState(_ s: State) {
        guard s != state else { return }
        state = s
        let cb = onState
        DispatchQueue.main.async { MainActor.assumeIsolated { cb?(s) } }
    }

    // MARK: - Mensagens

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while fd >= 0 {
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                inbox.append(buf, count: n)
                continue
            }
            if n < 0, errno == EAGAIN || errno == EINTR { break }
            // 0 = o Discord fechou (ou foi encerrado).
            disconnect(to: .notRunning)
            return
        }
        while inbox.count >= 8 {
            let op = inbox.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
            let len = Int(inbox.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) })
            guard inbox.count >= 8 + len else { break }
            let body = inbox.subdata(in: inbox.startIndex + 8..<inbox.startIndex + 8 + len)
            inbox.removeSubrange(inbox.startIndex..<inbox.startIndex + 8 + len)
            handle(op: op, body: body)
            if fd < 0 { return }
        }
    }

    private func handle(op: UInt32, body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        switch Op(rawValue: op) {
        case .frame:
            let data = json["data"] as? [String: Any]
            if json["evt"] as? String == "READY" {
                ready = true
                let user = data?["user"] as? [String: Any]
                let name = (user?["global_name"] as? String) ?? (user?["username"] as? String) ?? "Discord"
                setState(.connected(user: name))
                flush()
            } else if json["evt"] as? String == "ERROR" {
                let msg = data?["message"] as? String ?? "erro desconhecido"
                let cb = onError
                DispatchQueue.main.async { MainActor.assumeIsolated { cb?(msg) } }
            }
        case .close:
            let msg = json["message"] as? String ?? "O Discord fechou a conexão."
            retryAfter = Date().addingTimeInterval(30)
            disconnect(to: .rejected(msg))
        case .ping:
            write(.pong, json)
        default:
            break
        }
    }

    @discardableResult
    private func write(_ op: Op, _ object: Any) -> Bool {
        guard fd >= 0, let body = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var frame = Data(capacity: 8 + body.count)
        withUnsafeBytes(of: op.rawValue.littleEndian) { frame.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(body.count).littleEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        var offset = 0
        var tries = 0
        while offset < frame.count {
            let n = frame.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + offset, frame.count - offset) }
            if n > 0 {
                offset += n
            } else if n < 0, errno == EAGAIN || errno == EINTR, tries < 100 {
                tries += 1
                usleep(2000)
            } else {
                disconnect(to: .notRunning)
                return false
            }
        }
        return true
    }

    // MARK: - Atividade

    /// Envia a atividade desejada, se mudou e se o limite deixa.
    private func flush() {
        guard fd >= 0, ready else { return }
        let args: [String: Any] = desired.map { ["pid": Int(getpid()), "activity": $0] } ?? ["pid": Int(getpid())]
        let signature = (try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys)) ?? Data()
        guard signature != lastSent else { return }
        let now = Date()
        sendTimes.removeAll { now.timeIntervalSince($0) > 20 }
        if sendTimes.count >= 5 {
            guard !flushScheduled else { return }
            flushScheduled = true
            let wait = 20 - now.timeIntervalSince(sendTimes[0]) + 0.1
            queue.asyncAfter(deadline: .now() + wait) { [self] in
                flushScheduled = false
                flush()
            }
            return
        }
        let frame: [String: Any] = ["cmd": "SET_ACTIVITY", "args": args, "nonce": UUID().uuidString]
        if write(.frame, frame) {
            lastSent = signature
            sendTimes.append(now)
        }
    }
}
