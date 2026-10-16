import AppKit
import Combine
import SwiftUI

/// Roda em segundo plano, só com o ícone na barra de menus (LSUIElement: sem
/// Dock nem ⌘Tab). A janela abre pelo painel do ícone, quando precisa.
@main
struct TocandoApp: App {
    // Os dados ficam no AppDelegate, que vive o app todo.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var presence: Presence { appDelegate.presence }
    /// Escondido enquanto o app dorme (modo "junto com o Discord").
    @AppStorage(Prefs.iconHidden) private var iconHidden = false

    // A janela vem primeiro: o SwiftUI a cria ao abrir (e o AppDelegate fecha),
    // e assim o painel consegue reabri-la depois.
    var body: some Scene {
        Window("Tocando", id: "main") {
            MainView()
                .environmentObject(presence)
                .environmentObject(presence.monitor)
                .environmentObject(presence.history)
                .environmentObject(appDelegate.nav)
                .tint(.accent)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                SharingCommand()
            }
            CommandMenu("Controles") {
                Button("Tocar/Pausar") { presence.monitor.send(.togglePlayPause) }
                    .keyboardShortcut(.space, modifiers: [.command])
                Button("Próxima") { presence.monitor.send(.next) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Anterior") { presence.monitor.send(.previous) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }

        MenuBarExtra(isInserted: Binding(get: { !iconHidden }, set: { iconHidden = !$0 })) {
            MenuBarPanel()
                .environmentObject(presence)
                .environmentObject(presence.monitor)
                .environmentObject(appDelegate.nav)
                .tint(.accent)
        } label: {
            MenuBarLabel(presence: presence)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(presence)
                .tint(.accent)
        }
    }
}

/// Arquivo → Compartilhar no Discord (⌘D).
struct SharingCommand: View {
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some View {
        Toggle("Compartilhar no Discord", isOn: $enabled)
            .keyboardShortcut("d", modifiers: [.command])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let presence = Presence()
    let nav = Navigator()
    let discordApp = DiscordWatcher()
    /// Aberto pelo macOS ao entrar (Itens de Início), e não por você.
    private var launchedAtLogin = false
    private var bag: Set<AnyCancellable> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        // `Tocando --launch-mode manual|login|discord`: muda o modo (como no
        // painel) e sai, sem abrir nada.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--launch-mode") {
            guard i + 1 < args.count, let mode = LaunchMode(rawValue: args[i + 1]) else {
                print("uso: Tocando --launch-mode manual|login|discord")
                exit(2)
            }
            let error = LaunchMode.set(mode)
            print(error ?? "Abrir sozinho: \(mode.rawValue)")
            exit(error == nil ? 0 : 1)
        }
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        // Guarda o modo uma vez (antes vinha só do item de início).
        if UserDefaults.standard.string(forKey: Prefs.launchMode) == nil {
            UserDefaults.standard.set(LaunchMode.current.rawValue, forKey: Prefs.launchMode)
        }
        // Antes do ícone aparecer: dormindo, ele nem chega a piscar.
        UserDefaults.standard.set(!shouldBeAwake, forKey: Prefs.iconHidden)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.applyAppearance()
        if let folder = Snapshot.folder {
            presence.start()
            Task { await Snapshot.run(self, into: folder) }
            return
        }
        applyLaunchMode()
        // O Discord abriu ou fechou, ou o modo mudou: acorda ou dorme.
        discordApp.$isRunning.dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLaunchMode() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyLaunchMode() }
            .store(in: &bag)

        // Começa escondido, só no ícone lá em cima (a MainView fecha a janela
        // ao aparecer). A janela fica aberta na primeira vez (sem o
        // Application ID) e quando você abre o app com ele dormindo (sem ícone,
        // senão pareceria que não abriu).
        if Prefs.clientIdValue.isEmpty {
            nav.selection = .discord
            NSApp.activate()
        } else if !shouldBeAwake && !launchedAtLogin {
            NSApp.activate()
        } else {
            nav.hideOnLaunch = true
            // Garantia, se a janela aparecer antes da MainView fechar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NSApp.windows.filter { $0.isTitledWindow && $0.isVisible }.forEach { $0.close() }
            }
        }
    }

    /// No modo "junto com o Discord", só fica acordado com o Discord aberto.
    private var shouldBeAwake: Bool { LaunchMode.current != .discord || discordApp.isRunning }

    private func applyLaunchMode() {
        let awake = shouldBeAwake
        if awake == presence.asleep || !started {
            started = true
            if awake { presence.start() } else { presence.sleep() }
        }
        if Prefs.bool(Prefs.iconHidden, default: false) == awake {
            UserDefaults.standard.set(!awake, forKey: Prefs.iconHidden)
        }
    }
    private var started = false

    func applicationWillTerminate(_ notification: Notification) {
        presence.stop()   // fecha o socket: o Discord tira a música do status
    }

    // Fechar a janela não fecha o app: ele continua no ícone da barra de menus.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Abrir o app de novo (Finder, Spotlight) com ele já rodando: mostra a janela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { nav.show(nav.selection ?? .nowPlaying) }
        return true
    }
}

extension NSWindow {
    /// Janela "de verdade" (a principal, os Ajustes), não o painel da barra de menus.
    var isTitledWindow: Bool { styleMask.contains(.titled) && !(self is NSPanel) }
}
