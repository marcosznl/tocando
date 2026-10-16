import Foundation

/// Nome e ícone públicos de um app do portal do Discord.
struct DiscordAppInfo: Equatable {
    let id: String
    let name: String
    let iconURL: URL?
}

/// Busca o nome dos apps do Discord pelo Application ID (endpoint público,
/// sem login). É o nome que aparece em "Ouvindo …" no perfil.
@MainActor
final class DiscordApps: ObservableObject {
    static let shared = DiscordApps()

    @Published private(set) var info: [String: DiscordAppInfo] = [:]
    /// IDs que o Discord não conhece.
    @Published private(set) var invalid: Set<String> = []
    private var loading: Set<String> = []

    static func looksValid(_ id: String) -> Bool {
        id.count >= 17 && id.count <= 21 && id.allSatisfy(\.isNumber)
    }

    /// O nome do app, se já buscado (e busca, se ainda não).
    func name(_ id: String) -> String? {
        load(id)
        return info[id]?.name
    }

    func load(_ id: String) {
        guard Self.looksValid(id), info[id] == nil, !invalid.contains(id), !loading.contains(id),
              let url = URL(string: "https://discord.com/api/v10/applications/\(id)/rpc") else { return }
        loading.insert(id)
        Task {
            defer { loading.remove(id) }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return }   // sem internet: tenta depois
            guard status == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = json["name"] as? String else {
                if status == 404 || status == 400 { invalid.insert(id) }
                return
            }
            let icon = (json["icon"] as? String).flatMap {
                URL(string: "https://cdn.discordapp.com/app-icons/\(id)/\($0).png?size=256")
            }
            info[id] = DiscordAppInfo(id: id, name: name, iconURL: icon)
        }
    }

    /// Esquece um ID (ex: o usuário trocou o nome do app no portal).
    func reload(_ id: String) {
        info[id] = nil
        invalid.remove(id)
        load(id)
    }
}
