#!/usr/bin/env bash
# Ajusta os arquivos de empacotamento (nome do produto, binário, identificador)
# para a variante do Pc&P Desk. Executar na raiz do fork antes de compilar.
#
# Uso: pcep/aplicar-variante.sh <cliente|colaborador>
# Variável opcional: PCEP_RAIZ (raiz do fork; padrão: diretório atual).
#
# Idempotente: substitui o valor da linha inteira da chave, não um texto do
# upstream. Se uma chave não existir, falha (código 1) para o CI não gerar
# um app com nome errado sem perceber. Argumento inválido: código 2.
#
# Tolera arquivos com CRLF (checkout no Windows): o CR do fim da linha é
# preservado. Precisa de GNU sed (no macOS: `brew install gnu-sed`, o script
# usa `gsed` se existir).
set -euo pipefail

uso() {
  echo "Uso: $0 <cliente|colaborador>" >&2
  exit 2
}

[ "$#" -eq 1 ] || uso

# O nome do binário é o APP_NAME em minúsculas, como o upstream faz com
# "RustDesk" -> "rustdesk": o Rust no Linux procura processos, serviço systemd
# e .desktop por get_app_name().to_lowercase().
case "$1" in
  cliente)
    PRODUTO_MAC="PcepDesk"
    EXIBICAO="Pc&P Desk"
    BINARIO="pcepdesk"
    IDENTIFICADOR="br.com.pcepcontabil.desk"
    ;;
  colaborador)
    PRODUTO_MAC="PcepDeskEquipe"
    EXIBICAO="Pc&P Desk Equipe"
    BINARIO="pcepdeskequipe"
    IDENTIFICADOR="br.com.pcepcontabil.desk.equipe"
    ;;
  *) uso ;;
esac

RAIZ="${PCEP_RAIZ:-.}"
EMPRESA="PC&P Contabilidade"
CR=$'\r'

# GNU sed: `gsed` (Homebrew no macOS) ou `sed` (Linux, Git Bash no Windows).
if command -v gsed >/dev/null 2>&1; then SED=gsed; else SED=sed; fi
if ! "$SED" --version 2>/dev/null | grep -q 'GNU sed'; then
  echo "ERRO: este script precisa do GNU sed (no macOS: brew install gnu-sed)." >&2
  exit 1
fi

# No Runner.rc o "&" literal precisa ser escrito "&&".
dobra_e() { printf '%s' "${1//&/&&}"; }

# Escapa o texto para o lado de substituição do sed (delimitador "|").
escapa_sed() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

confere_arquivo() {
  if [ ! -f "$RAIZ/$1" ]; then
    echo "ERRO: arquivo não encontrado: $1" >&2
    exit 1
  fi
}

# substitui <arquivo> <seção|""> <regex-da-chave> <linha-nova>
#   Troca a linha inteira que começa (após espaços) com a chave. A indentação
#   e o CR final (se houver) são preservados. Se <seção> for informada
#   (ex.: "[package.metadata.winres]"), só mexe dentro dela, até o próximo
#   cabeçalho "[".
substitui() {
  local arquivo="$RAIZ/$1" secao="$2" chave="$3" nova="$4"
  local escopo=""
  confere_arquivo "$1"
  if [ -n "$secao" ]; then
    local sec_re="${secao//[/\\[}"
    sec_re="${sec_re//]/\\]}"
    escopo="/^${sec_re}${CR}?\$/,/^\\[/"
  fi
  local padrao="^([[:space:]]*)(${chave})[^${CR}]*(${CR}?)\$"
  if ! "$SED" -n -E "${escopo}{/${padrao}/p}" "$arquivo" | grep -q .; then
    echo "ERRO: chave '${chave}'${secao:+ na seção ${secao}} não encontrada em $1" >&2
    exit 1
  fi
  "$SED" -i -E "${escopo}{s|${padrao}|\\1$(escapa_sed "$nova")\\3|}" "$arquivo"
}

# substitui_trecho <arquivo> <descrição> <regex-ERE> <substituição-sed>
#   Para linhas em que só um trecho muda (o resto é código do upstream). A
#   regex deve casar ao menos uma linha, senão falha: se o upstream mudar a
#   linha, o CI para em vez de gerar um pacote quebrado.
substitui_trecho() {
  local arquivo="$RAIZ/$1" descricao="$2" regex="$3" troca="$4"
  confere_arquivo "$1"
  # Delimitador "|" também no endereço: a regex pode conter "/" (caminhos).
  if ! "$SED" -n -E "\\|${regex}|p" "$arquivo" | grep -q .; then
    echo "ERRO: ${descricao} não encontrado em $1 (o upstream mudou a linha?)" >&2
    exit 1
  fi
  "$SED" -i -E "s|${regex}|${troca}|" "$arquivo"
}

# Cargo.toml: metadados do executável do Windows e do bundle do macOS.
substitui Cargo.toml "[package.metadata.winres]" 'OriginalFilename[[:space:]]*=' "OriginalFilename = \"$BINARIO.exe\""
substitui Cargo.toml "[package.metadata.winres]" 'ProductName[[:space:]]*='      "ProductName = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.winres]" 'FileDescription[[:space:]]*='  "FileDescription = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.bundle]" 'name[[:space:]]*='             "name = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.bundle]" 'identifier[[:space:]]*='       "identifier = \"$IDENTIFICADOR\""

# Empacotador portátil (libs/portable): metadados do .exe que o usuário vê.
substitui libs/portable/Cargo.toml "[package.metadata.winres]" 'OriginalFilename[[:space:]]*=' "OriginalFilename = \"$BINARIO.exe\""
substitui libs/portable/Cargo.toml "[package.metadata.winres]" 'ProductName[[:space:]]*='      "ProductName = \"$EXIBICAO\""
substitui libs/portable/Cargo.toml "[package.metadata.winres]" 'FileDescription[[:space:]]*='  "FileDescription = \"$EXIBICAO\""

# Runner.rc (Windows): recursos de versão do executável.
RC=flutter/windows/runner/Runner.rc
EXIBICAO_RC="$(dobra_e "$EXIBICAO")"
substitui "$RC" "" 'VALUE "CompanyName",'      "VALUE \"CompanyName\", \"$(dobra_e "$EMPRESA")\" \"\\0\""
substitui "$RC" "" 'VALUE "FileDescription",'  "VALUE \"FileDescription\", \"$EXIBICAO_RC\" \"\\0\""
substitui "$RC" "" 'VALUE "InternalName",'     "VALUE \"InternalName\", \"$BINARIO\" \"\\0\""
substitui "$RC" "" 'VALUE "OriginalFilename",' "VALUE \"OriginalFilename\", \"$BINARIO.exe\" \"\\0\""
substitui "$RC" "" 'VALUE "ProductName",'      "VALUE \"ProductName\", \"$EXIBICAO_RC\" \"\\0\""

# CMake do Windows: só BINARY_NAME (o project(rustdesk ...) fica como está).
substitui flutter/windows/CMakeLists.txt "" 'set\(BINARY_NAME[[:space:]]' "set(BINARY_NAME \"$BINARIO\")"

# CMake do Linux.
substitui flutter/linux/CMakeLists.txt "" 'set\(BINARY_NAME[[:space:]]'    "set(BINARY_NAME \"$BINARIO\")"
substitui flutter/linux/CMakeLists.txt "" 'set\(APPLICATION_ID[[:space:]]' "set(APPLICATION_ID \"$IDENTIFICADOR\")"

# macOS.
XC=flutter/macos/Runner/Configs/AppInfo.xcconfig
substitui "$XC" "" 'PRODUCT_NAME[[:space:]]*='              "PRODUCT_NAME = $PRODUTO_MAC"
substitui "$XC" "" 'PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=' "PRODUCT_BUNDLE_IDENTIFIER = $IDENTIFICADOR"

# build.py (macOS): copia o binário `service` para dentro de RustDesk.app, nome
# fixo; o .app agora se chama PRODUCT_NAME.app.
substitui_trecho build.py "cópia do binário service para o .app" \
  '(cp -rf \.\./target/release/service \./build/macos/Build/Products/Release/)[A-Za-z0-9_]+(\.app/Contents/MacOS/)' \
  "\\1$(escapa_sed "$PRODUTO_MAC")\\2"

# Receita do AppImage (Linux): build.py instala o bundle em usr/share/rustdesk/,
# mas o executável dentro dele é o BINARY_NAME.
substitui_trecho appimage/AppImageBuilder-x86_64.yml "exec do AppImage" \
  "^(    exec: usr/share/rustdesk/)[A-Za-z0-9_-]+(${CR}?)\$" \
  "\\1$(escapa_sed "$BINARIO")\\2"

echo "Variante '$1' aplicada em $RAIZ"
