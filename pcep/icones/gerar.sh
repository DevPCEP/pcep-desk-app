#!/usr/bin/env bash
# PCEP: gera os ícones do Pc&P Desk nos lugares que o RustDesk usa.
# Roda no CI (job "icones" do pcep-build.yml) antes da compilação; os arquivos
# gerados NÃO são commitados. Requer: rsvg-convert (librsvg2-bin),
# convert (ImageMagick) e png2icns (icnsutils).
#
# Uso (na raiz do fork): bash pcep/icones/gerar.sh
set -euo pipefail

RAIZ="${PCEP_RAIZ:-.}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONE="$DIR/icone.svg"
BANDEJA="$DIR/bandeja.svg"
LOGO="$DIR/origem/logo.svg"

for ferramenta in rsvg-convert convert png2icns; do
  if ! command -v "$ferramenta" >/dev/null 2>&1; then
    echo "ERRO: ferramenta '$ferramenta' não encontrada (instale librsvg2-bin, imagemagick e icnsutils)." >&2
    exit 1
  fi
done
for arquivo in "$ICONE" "$BANDEJA" "$LOGO"; do
  [ -f "$arquivo" ] || { echo "ERRO: arquivo de origem ausente: $arquivo" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

png() { # png <svg> <tamanho> <destino>
  rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
}

# Tamanhos base do ícone do app
for t in 16 32 48 64 128 256 512 1024; do
  png "$ICONE" "$t" "$TMP/icone-$t.png"
done

mkdir -p "$RAIZ/res" "$RAIZ/flutter/windows/runner/resources" "$RAIZ/flutter/macos/Runner" "$RAIZ/flutter/assets"

cp "$TMP/icone-1024.png" "$RAIZ/res/icon.png"
cp "$TMP/icone-32.png"   "$RAIZ/res/32x32.png"
cp "$TMP/icone-64.png"   "$RAIZ/res/64x64.png"
cp "$TMP/icone-128.png"  "$RAIZ/res/128x128.png"
cp "$TMP/icone-256.png"  "$RAIZ/res/128x128@2x.png"
cp "$TMP/icone-1024.png" "$RAIZ/res/mac-icon.png"

# .ico com vários tamanhos (Windows)
convert "$TMP"/icone-{16,32,48,64,128,256}.png "$RAIZ/res/icon.ico"
cp "$RAIZ/res/icon.ico" "$RAIZ/res/tray-icon.ico"
cp "$RAIZ/res/icon.ico" "$RAIZ/flutter/windows/runner/resources/app_icon.ico"

# .icns (macOS): png2icns aceita 16, 32, 128, 256, 512 e 1024
png2icns "$RAIZ/flutter/macos/Runner/AppIcon.icns" \
  "$TMP"/icone-{16,32,128,256,512,1024}.png >/dev/null

# Bandeja do macOS (template monocromático, 44x44 = 22pt @2x)
png "$BANDEJA" 44 "$RAIZ/res/mac-tray-dark-x2.png"
cp "$RAIZ/res/mac-tray-dark-x2.png" "$RAIZ/res/mac-tray-light-x2.png"

# Ícone e logo usados na interface Flutter
cp "$ICONE" "$RAIZ/flutter/assets/icon.svg"
sed 's/currentColor/#111528/g' "$LOGO" > "$TMP/logo-escuro.svg"
rsvg-convert -w 512 "$TMP/logo-escuro.svg" -o "$RAIZ/flutter/assets/logo.png"

echo "Ícones do Pc&P Desk gerados em $RAIZ"
