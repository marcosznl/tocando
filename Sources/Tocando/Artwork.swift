import Foundation

/// Capa e link da música no catálogo da Apple (iTunes Search API, pública).
///
/// O Discord só mostra imagens por endereço na internet; a capa que o player
/// manda fica só no Mac. Então procura a mesma música no catálogo e usa a capa
/// de lá (e o link para o botão "Ouvir no Apple Music").
struct StoreMatch: Codable, Equatable {
    var artworkURL: String?
    var trackURL: String?
}

actor ArtworkLookup {
    static let shared = ArtworkLookup()

    private var cache: [String: StoreMatch] = [:]
    private var misses: Set<String> = []

    func find(title: String, artist: String?, album: String?) async -> StoreMatch? {
        let key = [title, artist ?? "", album ?? ""].map(Self.normalize).joined(separator: "|")
        if let hit = cache[key] { return hit }
        if misses.contains(key) { return nil }

        var match: StoreMatch?
        let artistTerm = artist.map { Self.clean($0) } ?? ""
        if let songs = await search("\(artistTerm) \(Self.clean(title))", entity: "song") {
            match = best(songs, title: title, artist: artist, album: album)
        }
        // Sem a música (ex: arquivo local, versão ao vivo): tenta só o álbum.
        if match == nil, let album, let albums = await search("\(artistTerm) \(Self.clean(album))", entity: "album") {
            match = best(albums, title: nil, artist: artist, album: album)
        }
        if let match { cache[key] = match } else { misses.insert(key) }
        return match
    }

    private func search(_ term: String, entity: String) async -> [[String: Any]]? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: term.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        guard let url = c.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return json["results"] as? [[String: Any]]
    }

    /// O resultado mais parecido; precisa bater o artista (quando há) e o
    /// título ou o álbum.
    private func best(_ results: [[String: Any]], title: String?, artist: String?, album: String?) -> StoreMatch? {
        var best: (score: Int, match: StoreMatch)?
        for r in results {
            var score = 0
            if let artist {
                guard Self.similar(r["artistName"] as? String, artist) else { continue }
                score += 2
            }
            let titleOK = title.map { Self.similar(r["trackName"] as? String, $0) } ?? false
            let albumOK = album.map { Self.similar(r["collectionName"] as? String, $0) } ?? false
            if title != nil, !titleOK, !albumOK { continue }
            if title == nil, !albumOK { continue }
            if titleOK { score += 2 }
            if albumOK { score += 3 }
            guard let art = r["artworkUrl100"] as? String else { continue }
            let m = StoreMatch(
                artworkURL: art.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                trackURL: (r["trackViewUrl"] as? String) ?? (r["collectionViewUrl"] as? String))
            if score > (best?.score ?? -1) { best = (score, m) }
        }
        return best?.match
    }

    /// Tira "(Remastered 2011)", "- Ao Vivo", "feat. …" para a busca achar.
    static func clean(_ s: String) -> String {
        var t = s
        for pattern in [#"\s*[\(\[][^\)\]]*[\)\]]"#, #"\s+-\s+.*$"#, #"\s+(feat\.?|ft\.?|featuring)\s+.*$"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.isEmpty ? s : t
    }

    static func normalize(_ s: String) -> String {
        clean(s).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func similar(_ a: String?, _ b: String) -> Bool {
        guard let a else { return false }
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.contains(y) || y.contains(x)
    }
}
