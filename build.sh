#!/bin/zsh
# Compila e monta "Tocando.app" (e o .dmg de instalação).
# Precisa do SDK 26.5 (o SDK 27 das Command Line Tools não tem o plugin SwiftUIMacros).
#
# Uso: ./build.sh            só monta (Tocando.app e Tocando.dmg aqui na pasta)
#      ./build.sh --install  monta, instala em /Applications e abre
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=false
[[ "${1:-}" == "--install" ]] && INSTALL=true

APP="Tocando.app"
VERSION="1.0"
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
SIGN=/Users/marcos/Projetos/iDownloads/sign.sh   # certificado fixo dos apps do Marcos
MRA=Vendor/mediaremote-adapter

SDKROOT=$SDK swift build -c release

# MediaRemoteAdapter: o /usr/bin/perl (que o macOS deixa ler o "Tocando agora")
# carrega este framework e manda as mudanças em JSON. Sem cmake: clang direto.
FW=build/MediaRemoteAdapter.framework
rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources"
SDKROOT=$SDK clang -dynamiclib -arch arm64 -arch x86_64 -fobjc-arc -fvisibility=default \
    -mmacosx-version-min=14.0 -w -I$MRA/include -I$MRA/src \
    $MRA/src/adapter/*.m $MRA/src/private/*.m $MRA/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$FW/Versions/A/MediaRemoteAdapter"
ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FW/Resources"
cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key><string>com.marcos.tocando.MediaRemoteAdapter</string>
	<key>CFBundleName</key><string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
</dict>
</plist>
PLIST

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/pt-BR.lproj" "$APP/Contents/Frameworks"
cp .build/release/Tocando "$APP/Contents/MacOS/"
cp Icon/AppIcon.icns "$APP/Contents/Resources/"
cp Icon/icon_1024.png "$APP/Contents/Resources/DiscordIcon.png"   # para enviar ao portal do Discord
cp $MRA/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp -R "$FW" "$APP/Contents/Frameworks/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
	<key>CFBundleLocalizations</key><array><string>pt-BR</string></array>
	<key>CFBundleDisplayName</key><string>Tocando</string>
	<key>CFBundleName</key><string>Tocando</string>
	<key>CFBundleExecutable</key><string>Tocando</string>
	<key>CFBundleIdentifier</key><string>com.marcos.tocando</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>LSUIElement</key><true/>
	<key>NSAppleEventsUsageDescription</key><string>Quando um vídeo toma o lugar da música no macOS, o Tocando pergunta ao Música e ao Spotify o que eles estão tocando, para a música continuar no seu status do Discord.</string>
</dict>
</plist>
PLIST

if [[ -x "$SIGN" ]]; then
    "$SIGN" "$APP"   # certificado fixo: o macOS não esquece as permissões a cada build
else
    codesign --force --deep -s - "$APP"
fi
echo "Pronto: $(pwd)/$APP ($(du -sh "$APP" | cut -f1))"

# DMG de instalação (app + atalho para Aplicativos), refeito a cada build.
DMG="Tocando.dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"
rm -f "$DMG"
hdiutil create -quiet -volname "Tocando $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "DMG: $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"

# Instalar: troca o app em /Applications, leva o item de início (abrir
# sozinho) para lá e abre a versão nova.
if $INSTALL; then
    DEST=/Applications/Tocando.app
    pkill -x Tocando 2>/dev/null && sleep 1 || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    MODE=$(defaults read com.marcos.tocando launchMode 2>/dev/null || echo manual)
    if [[ "$MODE" != "manual" ]]; then
        # Cancela o registro antigo (que pode apontar para esta pasta) e registra o novo.
        "$DEST/Contents/MacOS/Tocando" --launch-mode manual >/dev/null
        "$DEST/Contents/MacOS/Tocando" --launch-mode "$MODE"
    fi
    open "$DEST"
    echo "Instalado: $DEST"
fi
