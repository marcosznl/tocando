import AppKit
import Combine

/// Sabe se o app do Discord está aberto (para o modo "junto com o Discord").
@MainActor
final class DiscordWatcher: ObservableObject {
    /// Discord, PTB e Canary (TOCANDO_DISCORD_BUNDLE troca, para testes).
    nonisolated static let bundleIds: Set<String> = ProcessInfo.processInfo.environment["TOCANDO_DISCORD_BUNDLE"].map { [$0] }
        ?? ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]

    @Published private(set) var isRunning = DiscordWatcher.check(NSWorkspace.shared.runningApplications)
    private var observation: AnyCancellable?

    init() {
        // A lista de apps abertos (KVO) muda com qualquer app, de Dock ou de
        // fundo; os avisos de "app abriu" do NSWorkspace pulam alguns.
        observation = NSWorkspace.shared.publisher(for: \.runningApplications)
            .map(Self.check)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] running in
                guard let self, running != self.isRunning else { return }
                self.isRunning = running
            }
    }

    nonisolated private static func check(_ apps: [NSRunningApplication]) -> Bool {
        apps.contains { $0.bundleIdentifier.map(bundleIds.contains) ?? false }
    }
}
