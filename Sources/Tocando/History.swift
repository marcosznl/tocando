import AppKit
import Foundation

/// Uma música que tocou (aparece na tela Histórico).
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String
    var title: String
    var artist: String?
    var album: String?
    var player: String
    var date: Date
    var artworkURL: String?
    var trackURL: String?
    /// Miniatura da capa que o player mandou (arquivo em Covers/).
    var coverFile: String?
}

/// Histórico das músicas, salvo em ~/Library/Application Support/Tocando.
@MainActor
final class History: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let limit = 300

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Cópias de teste (outro bundle id) não mexem no histórico de verdade.
        let id = Bundle.main.bundleIdentifier ?? "com.marcos.tocando"
        let url = base.appendingPathComponent(id == "com.marcos.tocando" ? "Tocando" : id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url.appendingPathComponent("Covers"), withIntermediateDirectories: true)
        return url
    }()
    private var file: URL { Self.folder.appendingPathComponent("history.json") }

    init() {
        if let data = try? Data(contentsOf: file),
           let list = try? JSONDecoder.iso.decode([HistoryEntry].self, from: data) {
            entries = list
        }
    }

    static func coverURL(_ entry: HistoryEntry) -> URL? {
        entry.coverFile.map { folder.appendingPathComponent("Covers").appendingPathComponent($0) }
    }

    /// Música tocando: entra no topo (ou atualiza a capa, se já é a do topo).
    func record(_ t: Track) {
        if let first = entries.first, first.key == t.key {
            if first.coverFile == nil, let art = t.artwork {
                entries[0].coverFile = saveCover(art, id: first.id)
                save()
            }
            return
        }
        var e = HistoryEntry(key: t.key, title: t.title, artist: t.artist, album: t.album, player: t.playerId, date: .now)
        if let art = t.artwork { e.coverFile = saveCover(art, id: e.id) }
        entries.insert(e, at: 0)
        while entries.count > limit { removeCover(entries.removeLast()) }
        save()
    }

    /// Capa e link do catálogo, que chegam depois.
    func setMatch(_ m: StoreMatch, key: String) {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return }
        entries[i].artworkURL = m.artworkURL
        entries[i].trackURL = m.trackURL
        save()
    }

    func remove(_ e: HistoryEntry) {
        entries.removeAll { $0.id == e.id }
        removeCover(e)
        save()
    }

    func clear() {
        entries.forEach(removeCover)
        entries = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func removeCover(_ e: HistoryEntry) {
        if let url = Self.coverURL(e) { try? FileManager.default.removeItem(at: url) }
    }

    /// Guarda a capa em 300 px (JPEG).
    private func saveCover(_ data: Data, id: UUID) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        let side: CGFloat = 300
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Preenche o quadrado (corta o que sobra, como a capa no Discord).
        let s = image.size
        let scale = max(side / max(s.width, 1), side / max(s.height, 1))
        let w = s.width * scale, h = s.height * scale
        image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let name = "\(id.uuidString).jpg"
        try? jpeg.write(to: Self.folder.appendingPathComponent("Covers").appendingPathComponent(name))
        return name
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
