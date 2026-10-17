import Foundation

/// Capa e links da música em catálogos públicos.
///
/// O Discord só mostra imagens por endereço na internet; a capa que o player
/// manda fica só no Mac. Então procura a mesma música, nesta ordem: catálogo
/// da Apple (iTunes Search API), Deezer e MusicBrainz + Cover Art Archive.
struct StoreMatch: Codable, Equatable {
    var artworkURL: String?
    /// Apple Music.
    var trackURL: String?
    var deezerURL: String?
}

actor ArtworkLookup {
    static let shared = ArtworkLookup()

    private var cache: [String: StoreMatch] = [:]
    private var misses: Set<String> = []
    /// O MusicBrainz pede no máximo uma consulta por segundo.
    private var lastMusicBrainz = Date.distantPast

    /// `wantsDeezer`: o player é o Deezer (o botão precisa do link de lá,
    /// mesmo quando a capa vem da Apple).
    func find(title: String, artist: String?, album: String?, wantsDeezer: Bool = false) async -> StoreMatch? {
        let key = [title, artist ?? "", album ?? "", wantsDeezer ? "dz" : ""].map(Self.normalize).joined(separator: "|")
        if let hit = cache[key] { return hit }
        if misses.contains(key) { return nil }

        var match = await apple(title: title, artist: artist, album: album)
        if match == nil || wantsDeezer, let dz = await deezer(title: title, artist: artist, album: album) {
            if match == nil { match = dz } else { match?.deezerURL = dz.deezerURL }
        }
        if match == nil, let art = await coverArtArchive(title: title, artist: artist, album: album) {
            match = StoreMatch(artworkURL: art)
        }
        if let match { cache[key] = match } else { misses.insert(key) }
        return match
    }

    // MARK: - Apple

    private func apple(title: String, artist: String?, album: String?) async -> StoreMatch? {
        let artistTerm = artist.map { Self.clean($0) } ?? ""
        if let songs = await appleSearch("\(artistTerm) \(Self.clean(title))", entity: "song"),
           let m = best(songs, title: title, artist: artist, album: album) {
            return m
        }
        // Sem a música (ex: arquivo local, versão ao vivo): tenta só o álbum.
        if let album, let albums = await appleSearch("\(artistTerm) \(Self.clean(album))", entity: "album") {
            return best(albums, title: nil, artist: artist, album: album)
        }
        return nil
    }

    private func appleSearch(_ term: String, entity: String) async -> [[String: Any]]? {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: term.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "US"),
        ]
        return await json(c.url)?["results"] as? [[String: Any]]
    }

    /// O resultado mais parecido; precisa bater o artista (quando há) e o
    /// título ou o álbum.
    private func best(_ results: [[String: Any]], title: String?, artist: String?, album: String?) -> StoreMatch? {
        var best: (score: Int, match: StoreMatch)?
        for r in results {
            guard let score = Self.score(title: title, artist: artist, album: album,
                                         found: (r["trackName"] as? String, r["artistName"] as? String, r["collectionName"] as? String)),
                  let art = r["artworkUrl100"] as? String else { continue }
            let m = StoreMatch(
                artworkURL: art.replacingOccurrences(of: "100x100bb", with: "600x600bb"),
                trackURL: (r["trackViewUrl"] as? String) ?? (r["collectionViewUrl"] as? String))
            if score > (best?.score ?? -1) { best = (score, m) }
        }
        return best?.match
    }

    // MARK: - Deezer

    private func deezer(title: String, artist: String?, album: String?) async -> StoreMatch? {
        var c = URLComponents(string: "https://api.deezer.com/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: "\(artist.map { Self.clean($0) } ?? "") \(Self.clean(title))"),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let results = await json(c.url)?["data"] as? [[String: Any]] else { return nil }
        var best: (score: Int, match: StoreMatch)?
        for r in results {
            let a = r["artist"] as? [String: Any], al = r["album"] as? [String: Any]
            guard let score = Self.score(title: title, artist: artist, album: album,
                                         found: (r["title"] as? String, a?["name"] as? String, al?["title"] as? String))
            else { continue }
            let m = StoreMatch(artworkURL: (al?["cover_xl"] as? String) ?? (al?["cover_big"] as? String),
                               deezerURL: r["link"] as? String)
            if score > (best?.score ?? -1) { best = (score, m) }
        }
        return best?.match
    }

    // MARK: - MusicBrainz + Cover Art Archive

    private func coverArtArchive(title: String, artist: String?, album: String?) async -> String? {
        let wait = 1.1 - Date().timeIntervalSince(lastMusicBrainz)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        lastMusicBrainz = Date()
        var query = "recording:\"\(Self.clean(title))\""
        if let artist { query += " AND artist:\"\(Self.clean(artist))\"" }
        var c = URLComponents(string: "https://musicbrainz.org/ws/2/recording")!
        c.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"),
                        URLQueryItem(name: "limit", value: "5")]
        guard let recs = await json(c.url, musicBrainz: true)?["recordings"] as? [[String: Any]] else { return nil }
        // Releases das gravações certas; o do mesmo álbum primeiro.
        var releases: [String] = []
        for r in recs {
            let credit = (r["artist-credit"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: " ")
            guard Self.similar(r["title"] as? String, title), artist == nil || Self.similar(credit, artist!) else { continue }
            for rel in r["releases"] as? [[String: Any]] ?? [] {
                guard let id = rel["id"] as? String else { continue }
                if let album, Self.similar(rel["title"] as? String, album) { releases.insert(id, at: 0) } else { releases.append(id) }
            }
        }
        for id in releases.prefix(3) {
            // O endereço redireciona para o archive.org: guarda o final, que é a imagem.
            var req = URLRequest(url: URL(string: "https://coverartarchive.org/release/\(id)/front-500")!)
            req.httpMethod = "HEAD"
            if let (_, response) = try? await URLSession.shared.data(for: req),
               (response as? HTTPURLResponse)?.statusCode == 200, let final = response.url {
                return final.absoluteString
            }
        }
        return nil
    }

    // MARK: - Comum

    private func json(_ url: URL?, musicBrainz: Bool = false) async -> [String: Any]? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        if musicBrainz {   // o MusicBrainz exige identificar o app
            req.setValue("Tocando/1.0 (https://github.com/marcosznl/discord-music-presence)", forHTTPHeaderField: "User-Agent")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Pontos de um resultado, ou nil se não for a mesma música: precisa bater
    /// o artista (quando há) e o título ou o álbum.
    private static func score(title: String?, artist: String?, album: String?,
                              found: (title: String?, artist: String?, album: String?)) -> Int? {
        var score = 0
        if let artist {
            guard similar(found.artist, artist) else { return nil }
            score += 2
        }
        let titleOK = title.map { similar(found.title, $0) } ?? false
        let albumOK = album.map { similar(found.album, $0) } ?? false
        if title != nil, !titleOK, !albumOK { return nil }
        if title == nil, !albumOK { return nil }
        if titleOK { score += 2 }
        if albumOK { score += 3 }
        return score
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
