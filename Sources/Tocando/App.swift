import AppKit
import SwiftUI

@main
struct TocandoApp: App {
    // Os dados ficam no AppDelegate, que vive o app todo: com as janelas
    // fechadas (barra de menus), o status no Discord continua.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(Prefs.menuBar) private var menuBar = true
    private var presence: Presence { appDelegate.presence }

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

        Settings {
            SettingsView()
                .environmentObject(presence)
                .tint(.accent)
        }

        MenuBarExtra(isInserted: $menuBar) {
            MenuBarPanel()
                .environmentObject(presence)
                .environmentObject(presence.monitor)
                .environmentObject(appDelegate.nav)
                .tint(.accent)
        } label: {
            MenuBarLabel(presence: presence)
        }
        .menuBarExtraStyle(.window)
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
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.applyAppearance()
        presence.start()
        watchWindows()
        if let folder = Snapshot.folder {
            Task { await Snapshot.run(self, into: folder) }
            return
        }
        // Aberto ao entrar no Mac, com a barra de menus: fica só lá em cima.
        if launchedAtLogin, Prefs.bool(Prefs.menuBar, default: true) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.windows.filter(\.isTitledWindow).forEach { $0.close() }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        presence.stop()   // fecha o socket: o Discord tira a música do status
    }

    // Fechar a janela não fecha o app quando ele está na barra de menus.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Prefs.bool(Prefs.menuBar, default: true)
    }

    // Clique no ícone do Dock sem janela aberta: abre a principal.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { nav.openMain?() }
        return true
    }

    /// Sem janelas, o app sai do Dock e fica só na barra de menus; com uma
    /// janela aberta, volta para o Dock (e para o ⌘Tab).
    private func watchWindows() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard (note.object as? NSWindow)?.isTitledWindow == true,
                      NSApp.activationPolicy() != .regular else { return }
                NSApp.setActivationPolicy(.regular)
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated {
                    guard Prefs.bool(Prefs.menuBar, default: true) else { return }
                    let open = NSApp.windows.filter { $0 !== closing && $0.isTitledWindow && $0.isVisible }
                    if open.isEmpty { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }
}

extension NSWindow {
    /// Janela "de verdade" (a principal, os Ajustes), não o painel da barra de menus.
    var isTitledWindow: Bool { styleMask.contains(.titled) && !(self is NSPanel) }
}
