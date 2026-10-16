import AppKit
import SwiftUI

/// `Tocando --snapshot <pasta>`: fotografa cada tela da janela principal e o
/// painel da barra de menus (PNG) e sai. Não precisa de permissão de Gravação
/// de Tela: o app desenha as próprias janelas.
@MainActor
enum Snapshot {
    static var folder: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(_ app: AppDelegate, into folder: String) async {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(4))   // música, capa do catálogo, Discord
        let screens: [(SidebarItem, String)] = [(.nowPlaying, "1-tocando"), (.history, "2-historico"),
                                                (.players, "3-players"), (.discord, "4-discord")]
        for (item, name) in screens {
            app.nav.selection = item
            try? await Task.sleep(for: .seconds(1.5))
            if let w = NSApp.windows.first(where: { $0.isTitledWindow && $0.isVisible }) {
                save(window: w, to: "\(folder)/\(name).png")
            }
        }
        let panel = MenuBarPanel()
            .environmentObject(app.presence)
            .environmentObject(app.presence.monitor)
            .environmentObject(app.nav)
            .tint(.accent)
            .background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: panel)
        r.scale = 2
        if let img = r.nsImage { write(img, to: "\(folder)/5-barra-de-menus.png") }
        print("snapshot: \(app.presence.blocker ?? "no status") | discord: \(app.presence.discordState)")
        NSApp.terminate(nil)
    }

    private static func save(window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private static func write(_ image: NSImage, to path: String) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
