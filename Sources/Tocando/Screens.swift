import SwiftUI

// MARK: - Peças

/// Capa: a que o player mandou, senão a do catálogo, senão uma nota.
struct CoverView: View {
    var data: Data?
    var file: URL?
    var url: String?
    var size: CGFloat?
    var radius: CGFloat = 10

    var body: some View {
        content
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    @ViewBuilder
    private var content: some View {
        if let data, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let file, let image = NSImage(contentsOf: file) {
            Image(nsImage: image).resizable().scaledToFill()
        } else if let url, let u = URL(string: url) {
            AsyncImage(url: u) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(colors: [Color.accent.opacity(0.55), Color.accent.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            .overlay(Image(systemName: "music.note").font(.system(size: (size ?? 120) * 0.32, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9)))
    }
}

/// Barra de progresso com os tempos.
struct ProgressRow: View {
    let track: Track
    var now: Date
    var light = false

    var body: some View {
        let pos = track.position(at: now) ?? 0
        let dur = track.duration ?? 0
        VStack(spacing: 4) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(light ? Color.white.opacity(0.2) : Color.primary.opacity(0.12))
                    Capsule().fill(light ? Color.white : Color.accent)
                        .frame(width: dur > 0 ? g.size.width * min(1, pos / dur) : 0)
                }
            }
            .frame(height: 4)
            HStack {
                Text(formatTime(pos))
                Spacer()
                Text(dur > 0 ? formatTime(dur) : "--:--")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(light ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary))
        }
    }
}

/// Anterior, tocar/pausar e próxima no player que está tocando.
struct PlayerControls: View {
    @EnvironmentObject private var monitor: NowPlayingMonitor
    let playing: Bool
    var size: CGFloat = 18

    var body: some View {
        HStack(spacing: size * 1.3) {
            Button { monitor.send(.previous) } label: { Image(systemName: "backward.fill") }
                .help("Anterior")
            Button { monitor.send(.togglePlayPause) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: size * 1.4))
                    .frame(width: size * 1.8)
            }
            .help(playing ? "Pausar" : "Tocar")
            Button { monitor.send(.next) } label: { Image(systemName: "forward.fill") }
                .help("Próxima")
        }
        .font(.system(size: size))
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

/// Nome e ícone do player.
struct PlayerChip: View {
    let id: String

    var body: some View {
        HStack(spacing: 6) {
            PlayerIcon(id: id, size: 16)
            Text(Players.name(id)).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

/// Prévia do cartão de atividade, como aparece no perfil do Discord.
struct DiscordCard: View {
    let preview: ActivityPreview
    let track: Track
    /// Ícone do app no portal (aparece quando não há capa).
    var appIcon: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preview.header)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
            HStack(alignment: .top, spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.details).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let s = preview.state { Text(s).font(.system(size: 12)).opacity(0.8).lineLimit(1) }
                    if let l = preview.largeText { Text(l).font(.system(size: 12)).opacity(0.6).lineLimit(1) }
                    if preview.start != nil, preview.end != nil {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            ProgressRow(track: track, now: ctx.date, light: true)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            if preview.buttonURL != nil {
                Text(Players.storeButton)
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(Color.discordCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// Sem capa no catálogo o Discord mostra o ícone do app (do portal).
    @ViewBuilder
    private var cover: some View {
        if let url = preview.imageURL {
            CoverView(url: url, size: 80, radius: 8)   // a do catálogo: é a que o Discord mostra
        } else if let appIcon {
            CoverView(url: appIcon.absoluteString, size: 80, radius: 8)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .help("Sem capa no catálogo da Apple: o Discord mostra o ícone do app.")
        }
    }
}

// MARK: - Tocando agora

struct NowPlayingScreen: View {
    @EnvironmentObject private var presence: Presence
    @EnvironmentObject private var monitor: NowPlayingMonitor
    @EnvironmentObject private var nav: Navigator
    @ObservedObject private var apps = DiscordApps.shared
    @AppStorage(Prefs.clientId) private var clientId = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if clientId.trimmingCharacters(in: .whitespaces).isEmpty { setupBanner }
                if let failure = monitor.failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let t = presence.track {
                    nowPlaying(t)
                    discordSection(t)
                } else {
                    ContentUnavailableView(
                        "Nada tocando",
                        systemImage: "music.note",
                        description: Text("Dê play no Música, Spotify, TIDAL, Deezer ou outro player: a música aparece aqui e no seu status do Discord."))
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tocando agora")
        .navigationSubtitle(presence.isSharing ? "No seu status do Discord" : (presence.blocker ?? ""))
    }

    private func nowPlaying(_ t: Track) -> some View {
        HStack(alignment: .center, spacing: 30) {
            CoverView(data: t.artwork, url: presence.match?.artworkURL, size: 250, radius: 14)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            VStack(alignment: .leading, spacing: 8) {
                PlayerChip(id: t.playerId)
                Text(t.title)
                    .font(.system(size: 28, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let a = t.artist {
                    Text(a).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }
                if let al = t.album {
                    Text(al).foregroundStyle(.tertiary).lineLimit(1)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ProgressRow(track: t, now: ctx.date)
                }
                .padding(.top, 10)
                .frame(maxWidth: 380)
                PlayerControls(playing: t.playing, size: 18)
                    .frame(maxWidth: 380)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func discordSection(_ t: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("No Discord").font(.headline)
                StatusDot(sharing: presence.isSharing, enabled: Prefs.bool(Prefs.enabled, default: true))
                Text(presence.isSharing ? "aparecendo no seu perfil" : (presence.blocker ?? ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let p = presence.preview {
                DiscordCard(preview: p, track: t, appIcon: apps.info[presence.activeClientId]?.iconURL)
                    .opacity(presence.isSharing ? 1 : 0.55)
                Text("Na lista de membros e nas conversas: “\(p.memberLine)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let e = presence.lastError {
                Label("O Discord recusou a última atualização: \(e)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Conecte ao Discord").font(.headline)
                Text("Falta o Application ID do seu app no portal do Discord (leva 1 minuto).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Configurar") { nav.selection = .discord }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Histórico

struct HistoryScreen: View {
    @EnvironmentObject private var history: History
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 22, alignment: .top)]

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView("Nenhuma música ainda", systemImage: "clock.arrow.circlepath",
                                       description: Text("As músicas que tocarem aparecem aqui, com a capa e o player."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                        ForEach(days, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(Self.dayTitle(group.day)).font(.title3.weight(.semibold))
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                                    ForEach(group.entries) { HistoryCard(entry: $0) }
                                }
                            }
                        }
                    }
                    .padding(28)
                }
            }
        }
        .navigationTitle("Histórico")
        .navigationSubtitle(history.entries.isEmpty ? "" : "\(history.entries.count) músicas")
        .toolbar {
            ToolbarItem {
                Button { confirmClear = true } label: { Label("Limpar histórico", systemImage: "trash") }
                    .disabled(history.entries.isEmpty)
                    .help("Limpar histórico")
            }
        }
        .confirmationDialog("Limpar o histórico?", isPresented: $confirmClear) {
            Button("Limpar histórico", role: .destructive) { history.clear() }
        } message: {
            Text("As músicas e as capas guardadas saem deste Mac.")
        }
    }

    private var days: [(day: Date, entries: [HistoryEntry])] {
        var out: [(day: Date, entries: [HistoryEntry])] = []
        let cal = Calendar.current
        for e in history.entries {
            let d = cal.startOfDay(for: e.date)
            if out.last?.day == d { out[out.count - 1].entries.append(e) } else { out.append((d, [e])) }
        }
        return out
    }

    static func dayTitle(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Hoje" }
        if cal.isDateInYesterday(d) { return "Ontem" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

struct HistoryCard: View {
    @EnvironmentObject private var history: History
    let entry: HistoryEntry
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(file: History.coverURL(entry), url: entry.artworkURL, radius: 10)
                .scaleEffect(hover ? 1.02 : 1)
                .shadow(color: .black.opacity(hover ? 0.2 : 0.08), radius: hover ? 10 : 4, y: 3)
                .animation(.easeOut(duration: 0.15), value: hover)
            Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
            if let a = entry.artist {
                Text(a).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 4) {
                PlayerIcon(id: entry.player, size: 12)
                Text("\(Players.name(entry.player)) · \(entry.date.formatted(date: .omitted, time: .shortened))")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { open() }
        .contextMenu {
            if entry.trackURL != nil { Button("Abrir no Apple Music") { open() } }
            Button("Copiar “\(entry.artist.map { "\($0) — " } ?? "")\(entry.title)”") {
                Links.copy("\(entry.artist.map { "\($0) — " } ?? "")\(entry.title)")
            }
            Divider()
            Button("Remover do histórico", role: .destructive) { history.remove(entry) }
        }
    }

    private func open() {
        if let s = entry.trackURL, let u = URL(string: s) { Links.open(u) }
    }
}

// MARK: - Players

struct PlayersScreen: View {
    @EnvironmentObject private var presence: Presence
    /// Players.* lê o UserDefaults direto: muda isto para redesenhar.
    @State private var version = 0

    var body: some View {
        let _ = version
        let ids = playerIds
        Form {
            Section {
                if ids.isEmpty {
                    Text("Os players aparecem aqui quando tocam alguma coisa.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ids, id: \.self) { id in
                    PlayerRow(id: id, playing: presence.track?.playerId == id, version: $version)
                        .contextMenu {
                            Button("Esquecer este player") { Players.forget(id); version += 1 }
                        }
                }
            } footer: {
                Text("Navegadores e players de vídeo começam desligados, para um vídeo qualquer não ir parar no seu status. Ligue os que quiser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No perfil, o Discord mostra “Ouvindo” e o nome do app criado no portal. Para aparecer “Ouvindo Spotify”, “Ouvindo Apple Music” etc.:")
                    Text("1. No portal do Discord, crie um app com o nome do player (New Application → “Spotify”).")
                    Text("2. Opcional: em App Icon, envie o ícone do player (aparece quando a música não tem capa).")
                    Text("3. Copie o Application ID e cole no campo do player acima.")
                    Text("Players sem app próprio usam o app principal (tela Discord).")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Abrir o portal do Discord") { Links.open(Links.developerPortal) }
            } header: {
                Text("Nome do player no status")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Players")
        .navigationSubtitle("O que vai para o status")
    }

    private var playerIds: [String] {
        var ids = Players.seen
        if let cur = presence.track?.playerId, !ids.contains(cur) { ids.insert(cur, at: 0) }
        return ids
    }
}

/// Um player: compartilhar ou não, e o app do Discord com o nome dele.
private struct PlayerRow: View {
    let id: String
    let playing: Bool
    @Binding var version: Int
    @ObservedObject private var apps = DiscordApps.shared
    @State private var clientId = ""

    var body: some View {
        let _ = version
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                PlayerIcon(id: id, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Players.name(id))
                    Text(id).font(.caption).foregroundStyle(.tertiary)
                }
                if playing {
                    Text("Tocando")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accent)
                }
                Spacer()
                Toggle("Compartilhar", isOn: Binding(
                    get: { Players.isEnabled(id) },
                    set: { Players.setEnabled(id, $0); version += 1 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            HStack(spacing: 8) {
                TextField("App do Discord", text: $clientId, prompt: Text("Application ID do app no Discord"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 230)
                    .onChange(of: clientId) { _, v in
                        Players.setClientId(v, for: id)
                        apps.load(v.trimmingCharacters(in: .whitespaces))
                    }
                appStatus
                Spacer()
            }
            .padding(.leading, 44)
        }
        .padding(.vertical, 2)
        .onAppear { clientId = Players.rawClientId(for: id) }
    }

    @ViewBuilder
    private var appStatus: some View {
        let v = clientId.trimmingCharacters(in: .whitespaces)
        if v.isEmpty {
            Text("usa o app principal").font(.caption).foregroundStyle(.tertiary)
        } else if !DiscordApps.looksValid(v) {
            Label("só números, 17 a 20 dígitos", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        } else if apps.invalid.contains(v) {
            Label("o Discord não achou esse app", systemImage: "xmark.circle")
                .font(.caption).foregroundStyle(.orange)
        } else if let info = apps.info[v] {
            Label("Ouvindo \(info.name)", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(Color.discordGreen)
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Discord

struct DiscordScreen: View {
    var body: some View {
        DiscordForm()
            .navigationTitle("Discord")
            .navigationSubtitle("Conexão e aparência do status")
    }
}

/// Ajustes do Discord (na tela Discord e nos Ajustes do app).
struct DiscordForm: View {
    @EnvironmentObject private var presence: Presence
    @AppStorage(Prefs.clientId) private var clientId = ""
    @AppStorage(Prefs.listeningTo) private var listeningTo = "artist"
    @AppStorage(Prefs.showAlbum) private var showAlbum = true
    @AppStorage(Prefs.showButtons) private var showButtons = true
    @AppStorage(Prefs.showPaused) private var showPaused = false
    @AppStorage(Prefs.enabled) private var enabled = true

    @ObservedObject private var apps = DiscordApps.shared

    private var trimmedId: String { clientId.trimmingCharacters(in: .whitespaces) }
    private var idLooksValid: Bool { DiscordApps.looksValid(trimmedId) }

    var body: some View {
        Form {
            Section("Conexão") {
                LabeledContent("Situação") {
                    HStack(spacing: 6) {
                        StatusDot(sharing: isConnected, enabled: enabled)
                        Text(stateText)
                    }
                }
                Toggle("Compartilhar no Discord", isOn: $enabled)
            }
            Section {
                TextField("Application ID", text: $clientId, prompt: Text("ex: 1234567890123456789"))
                    .task(id: trimmedId) { apps.load(trimmedId) }
                if !clientId.isEmpty && !idLooksValid {
                    Text("O Application ID tem só números (17 a 20 dígitos).")
                        .font(.caption).foregroundStyle(.orange)
                } else if let name = apps.info[trimmedId]?.name {
                    LabeledContent("Nome no perfil") {
                        Text("Ouvindo \(name)")
                    }
                    Text("Para trocar, mude o nome do app no portal. Para mostrar o nome de cada player (Spotify, Apple Music…), veja a tela Players.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if apps.invalid.contains(trimmedId) {
                    Text("O Discord não achou um app com esse ID.").font(.caption).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Abra o portal de desenvolvedores do Discord e clique em New Application.")
                    Text("2. Dê o nome que deve aparecer no seu perfil (ex: Música) e crie.")
                    Text("3. Em General Information, copie o Application ID e cole acima.")
                    Text("Opcional: em App Icon, envie o ícone do Tocando; ele aparece quando a música não tem capa.")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Button("Abrir o portal do Discord") { Links.open(Links.developerPortal) }
                    Button("Mostrar o ícone no Finder") {
                        if let url = Bundle.main.url(forResource: "DiscordIcon", withExtension: "png") { Links.reveal(url) }
                    }
                }
            } header: {
                Text("App no Discord")
            }
            Section("Status") {
                Picker("Na lista de membros, depois de “Ouvindo”", selection: $listeningTo) {
                    Text("Artista").tag("artist")
                    Text("Música").tag("title")
                    Text("Nome do app (player)").tag("app")
                }
                Toggle("Mostrar o álbum", isOn: $showAlbum)
                Toggle("Botão “\(Players.storeButton)”", isOn: $showButtons)
                Toggle("Continuar no status com a música pausada", isOn: $showPaused)
                Text("A capa e o botão vêm do catálogo da Apple; músicas que não estão lá (arquivos próprios, gravações) ficam com o ícone do app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var isConnected: Bool {
        if case .connected = presence.discordState { return true }
        return false
    }

    private var stateText: String {
        guard enabled else { return "Desligado" }
        switch presence.discordState {
        case .idle: return clientId.isEmpty ? "Falta o Application ID" : "Conectando…"
        case .notRunning: return "O Discord não está aberto"
        case .connecting: return "Conectando…"
        case .connected(let user): return "Conectado como \(user)"
        case .rejected(let msg): return "Recusado: \(msg)"
        }
    }
}
