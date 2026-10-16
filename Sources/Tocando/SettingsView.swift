import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Geral", systemImage: "gearshape") }
            DiscordForm().frame(height: 620).tabItem { Label("Discord", systemImage: "person.crop.circle.badge.checkmark") }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettings: View {
    @AppStorage(Prefs.appearance) private var appearance = ""
    @AppStorage(Prefs.launchMode) private var launchMode = LaunchMode.manual.rawValue
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Aparência") {
                Picker("Tema", selection: $appearance) {
                    Text("Sistema").tag("")
                    Text("Claro").tag("light")
                    Text("Escuro").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { Prefs.applyAppearance() }
            }
            Section("Segundo plano") {
                Text("O Tocando roda em segundo plano, só com o ícone na barra de menus (sem Dock). Clique no ícone para ver a música, abrir as telas ou sair.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Abrir sozinho", selection: Binding(
                    get: { launchMode },
                    set: { raw in loginError = LaunchMode.set(LaunchMode(rawValue: raw) ?? .manual) })) {
                    Text("Não").tag(LaunchMode.manual.rawValue)
                    Text("Ao entrar no Mac").tag(LaunchMode.login.rawValue)
                    Text("Junto com o Discord").tag(LaunchMode.discord.rawValue)
                }
                if launchMode == LaunchMode.discord.rawValue {
                    Text("O Tocando abre ao entrar no Mac, mas fica dormindo, sem ícone e sem ler a música, enquanto o Discord estiver fechado. Para abrir a janela nesse meio-tempo, abra o Tocando pelo Finder ou pelo Spotlight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}
