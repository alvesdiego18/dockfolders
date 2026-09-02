#!/bin/bash
# Build do DockFolders.
#
#   DEBUG=1 ./build.sh   build de desenvolvimento: sharingType capturável (para
#                        verificar a UI por screenshot), sem gerar o .dmg.
#   ./build.sh           build de release: sharingType = .none incondicional, e
#                        gera o .dmg pronto para instalar em outro Mac.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DockFolders"
APP="$APP_NAME.app"
DEBUG_FLAG=""
[ "${DEBUG:-0}" = "1" ] && DEBUG_FLAG="-D DEBUG"

rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DockFolders</string>
    <key>CFBundleDisplayName</key><string>DockFolders</string>
    <key>CFBundleIdentifier</key><string>local.dockfolders.app</string>
    <key>CFBundleExecutable</key><string>DockFolders</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# shellcheck disable=SC2086
swiftc -O $DEBUG_FLAG Sources/*.swift -o "$APP/Contents/MacOS/DockFolders"
codesign --force --sign - "$APP" 2>/dev/null || true
echo "OK: $(pwd)/$APP  (debug=${DEBUG:-0})"

if [ "${DEBUG:-0}" = "1" ]; then
    exit 0   # build de desenvolvimento: pula o empacotamento em .dmg
fi

# --- empacotamento para instalar em outro Mac -------------------------------
#
# Aviso (consequência da Q2 do CONTEXT.md: build local, sem conta de desenvolvedor,
# sem notarização). Copiado para outro Mac via AirDrop, rede ou nuvem, o arquivo
# recebe o atributo de quarentena e o macOS vai recusar abrir o app como
# "desenvolvedor não identificado" — não é um app quebrado, é a política padrão
# para software sem Developer ID pago e notarizado pela Apple. O README dentro
# do .dmg explica como liberar.

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

echo "== preparando imagem ($VERSION) =="
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/Leia-me.txt" <<EOF
DockFolders $VERSION
=====================

INSTALAR
Arraste DockFolders.app para o atalho Applications ao lado.

PRIMEIRA ABERTURA
Este app é assinado localmente (sem conta de desenvolvedor Apple), então o
Gatekeeper vai recusar abrir com um clique duplo normal, avisando que o
desenvolvedor não pôde ser verificado. Isso é esperado — não é um app corrompido.

Para liberar, escolha uma das duas formas:

  1. Clique com o botão direito em DockFolders.app → Abrir → Abrir, na janela
     de aviso. (Em versões mais novas do macOS, se essa opção não aparecer,
     use a via 2.)

  2. Ajustes do Sistema → Privacidade e Segurança → role até o aviso sobre o
     DockFolders → "Abrir Mesmo Assim".

Depois da primeira liberação, o app abre normalmente pelo Dock.

DEPOIS DE INSTALAR
- Clique com o botão direito no ícone do Dock → Opções → Manter no Dock.
- Conceda Acessibilidade ao DockFolders quando quiser o posicionamento
  preciso do balão (Ajustes do Sistema → Privacidade e Segurança →
  Acessibilidade). Sem isso o app funciona normalmente, só com a seta do
  balão desativada.
- Seus dados (pastas, grupos, apps) ficam em
  ~/Library/Application Support/DockFolders/folders.json — não vêm deste
  instalador; cada Mac começa com a lista vazia.
EOF

rm -f "$DMG_NAME"
echo "== gerando $DMG_NAME =="
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME" >/dev/null

echo
echo "OK: $(pwd)/$DMG_NAME"
echo
echo "Sem conta de desenvolvedor Apple, o Gatekeeper vai barrar a primeira abertura"
echo "em outro Mac. Instruções de liberação estão dentro do .dmg (Leia-me.txt)."
