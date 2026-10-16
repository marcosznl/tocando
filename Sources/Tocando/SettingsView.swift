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
    @AppStorage(Prefs.menuBar) private var menuBar = true
    @State private var loginItem = LoginItem.isOn
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
                Toggle("Ficar na barra de menus", isOn: $menuBar)
                Text("Fechando a janela, o Tocando continua lá em cima e o status no Discord segue atualizando. Para sair de vez, use Sair no menu.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Abrir ao entrar no Mac", isOn: Binding(
                    get: { loginItem },
                    set: { on in
                        loginError = LoginItem.set(on)
                        loginItem = LoginItem.isOn
                    }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}
