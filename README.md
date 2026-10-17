# Tocando — app macOS

Mostra no seu status do Discord a música que está tocando no Mac ("Ouvindo …"), em qualquer
player: Música, Spotify, TIDAL, Deezer, Podcasts, iPlayer e o que mais aparecer na Central de
Controle. Mesma família do iPlayer e do iDownloads (SwiftUI, sem dependências, sem Xcode).

Projeto escrito do zero. Ele mora no fork de
[ungive/discord-music-presence](https://github.com/ungive/discord-music-presence), que não tem
o código-fonte do app, mas não copia nada do Music Presence (código, nome ou imagens).

- **Tocando agora**: capa, música, artista, álbum, player, progresso e controles (anterior,
  tocar/pausar, próxima; também ⌘espaço, ⌘← e ⌘→). Embaixo, a prévia de como o cartão aparece
  no seu perfil do Discord.
- **Status no Discord**: atividade "Ouvindo" com a capa, a barra de progresso e um botão para
  ouvir a música no serviço do player que está tocando: "Ouvir no Spotify" (link exato da faixa,
  lido do próprio Spotify), "Ouvir no Deezer", "Ouvir no TIDAL", "Ouvir no Amazon Music" (busca
  no serviço) ou "Ouvir no Apple Music". Depois de "Ouvindo" pode vir o artista, a música ou o
  nome do app. Música pausada sai do status (ou fica, se você preferir).
- **Capas**: o Discord só mostra imagens que estão na internet, e a capa que o player manda fica
  só no Mac. O app procura a mesma música no catálogo da Apple (iTunes Search API), depois no
  Deezer e por fim no MusicBrainz + Cover Art Archive (todos públicos). Música que não está em
  nenhum fica com o ícone do app.
- **Spotify conectado ao Discord**: a integração oficial já mostra as músicas; na tela Players,
  "Deixar as músicas para a integração oficial" faz o Tocando mostrar só os podcasts do Spotify.
- **Players**: liga e desliga o compartilhamento de cada player. Navegadores e players de vídeo
  começam desligados.
- **A música tem prioridade**: o macOS só informa quem começou a tocar por último, então um vídeo
  no navegador "rouba" o Tocando agora, mesmo com a música tocando. O Tocando segura a música:
  pergunta ao Música e ao Spotify (AppleScript; o macOS pede permissão na primeira vez) se ela
  ainda toca, e nos outros players a mantém até acabar, pelo tempo dela. O vídeo só aparece
  quando não há música tocando (e se o player dele estiver ligado).
- **Histórico**: grade com as músicas que tocaram, por dia, com capa e player. Clique duplo abre
  no Apple Music.
- **Segundo plano**: o Tocando não aparece no Dock nem no ⌘Tab, só como um ícone na barra de
  menus (nota = no status, pausa = fora do status, riscado = desligado). Clicando no ícone: a
  música com os controles, o botão de compartilhar (⌘D), as telas (Tocando agora, Histórico,
  Players, Discord), as opções de abrir sozinho, Ajustes e Sair. A janela só abre quando você
  pede (ou na primeira vez, para configurar o Discord).
- **Abrir sozinho**: não, ao entrar no Mac, ou **junto com o Discord**. O macOS não abre um app
  quando outro abre; então, nesse modo, o Tocando abre ao entrar no Mac mas fica dormindo (sem
  ícone, sem ler a música, ~35 MB) enquanto o Discord estiver fechado, e acorda quando ele abre.

## Primeira vez: o app no Discord

O Discord só mostra atividades de "apps" cadastrados. O nome desse app é o que aparece no seu
perfil.

1. Abra <https://discord.com/developers/applications> e clique em **New Application**.
2. Dê o nome (ex: "Música") e crie.
3. Em **General Information**, copie o **Application ID** e cole no Tocando (tela Discord).
4. Opcional: em **App Icon**, envie o `DiscordIcon.png` (botão "Mostrar o ícone no Finder").

No perfil o Discord sempre mostra "Ouvindo <nome do app>". Para aparecer "Ouvindo Spotify",
"Ouvindo Apple Music" etc., crie um app para cada player com o nome dele e cole o ID ao lado do
player na tela **Players**. O Tocando troca de app conforme o player que está tocando, e os
players sem app próprio usam o principal. O nome de cada app é conferido no endpoint público
`discord.com/api/v10/applications/<id>/rpc`.

O Discord precisa estar aberto neste Mac (o app de desktop, não o site).

## Como funciona

- **Leitura da música** (`NowPlaying.swift`): desde o macOS 15.4 só apps da Apple podem ler o
  "Tocando agora". O [MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)
  (BSD-3, em `Vendor/`) contorna isso: o `/usr/bin/perl`, que tem a permissão, carrega um
  framework que imprime as mudanças em JSON. O app roda `perl … stream` e lê linha a linha.
  Testado no macOS 27.
- **Discord** (`Discord.swift`): socket local `$TMPDIR/discord-ipc-N`, o mesmo do Rich Presence
  dos jogos (mensagens com código + tamanho + JSON). Reconecta sozinho e respeita o limite do
  Discord (5 atualizações a cada 20 s).
- **Dados**: histórico e capas em `~/Library/Application Support/Tocando`; ajustes no
  UserDefaults (`com.marcos.tocando`).

## Compilar

```sh
./build.sh            # Tocando.app + Tocando.dmg aqui na pasta
./build.sh --install  # e instala em /Applications (leva junto o "abrir sozinho") e abre
```

Precisa das Command Line Tools com o SDK 26.5 (o SDK 27 não tem o plugin das macros do
SwiftUI). O `build.sh` compila o adaptador com `clang` (sem cmake) e assina com o certificado
local de `../iDownloads/sign.sh`, quando ele existe.

Para conferir as telas sem abrir a janela: `Tocando.app/Contents/MacOS/Tocando --snapshot <pasta>`
salva um PNG de cada tela e fecha.
