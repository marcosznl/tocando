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
        try? await Task.sleep(for: .seconds(8))   // música, capa do catálogo, nome do app, Discord
        let screens: [(SidebarItem, String)] = [(.nowPlaying, "1-tocando"), (.history, "2-historico"),
                                                (.players, "3-players"), (.discord, "4-discord")]
        for (item, name) in screens {
            app.nav.selection = item
            try? await Task.sleep(for: .seconds(1.5))
            if let w = NSApp.windows.first(where: { $0.isTitledWindow && $0.isVisible }) {
                save(window: w, to: "\(folder)/\(name).png")
            }
        }
        // O painel numa janela de verdade (fora da tela): o ImageRenderer não
        // desenha os controles do AppKit.
        let panel = MenuBarPanel()
            .environmentObject(app.presence)
            .environmentObject(app.presence.monitor)
            .environmentObject(app.nav)
            .tint(.accent)
        let host = NSHostingView(rootView: panel)
        host.frame.size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: host.fittingSize),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        w.backgroundColor = .windowBackgroundColor
        w.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1.5))
        save(window: w, to: "\(folder)/5-barra-de-menus.png")
        w.orderOut(nil)
        print("snapshot: \(app.presence.blocker ?? "no status") | discord: \(app.presence.discordState)")
        NSApp.terminate(nil)
    }

    private static func save(window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        // Sempre em 2x (Retina), mesmo com a janela numa tela comum.
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

}
