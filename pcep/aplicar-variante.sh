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
set -euo pipefail

uso() {
  echo "Uso: $0 <cliente|colaborador>" >&2
  exit 2
}

[ "$#" -eq 1 ] || uso

case "$1" in
  cliente)
    PRODUTO_MAC="PcepDesk"
    EXIBICAO="Pc&P Desk"
    BINARIO="pcep-desk"
    IDENTIFICADOR="br.com.pcepcontabil.desk"
    ;;
  colaborador)
    PRODUTO_MAC="PcepDeskEquipe"
    EXIBICAO="Pc&P Desk Equipe"
    BINARIO="pcep-desk-equipe"
    IDENTIFICADOR="br.com.pcepcontabil.desk.equipe"
    ;;
  *) uso ;;
esac

RAIZ="${PCEP_RAIZ:-.}"
EMPRESA="PC&P Contabilidade"
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

# substitui <arquivo> <seção|""> <regex-da-chave> <linha-nova>
#   Troca a linha inteira que começa (após espaços) com a chave. A indentação
#   é preservada. Se <seção> for informada (ex.: "[package.metadata.winres]"),
#   só mexe dentro dela, até o próximo cabeçalho "[".
substitui() {
  local arquivo="$RAIZ/$1" secao="$2" chave="$3" nova="$4"
  local escopo=""
  if [ ! -f "$arquivo" ]; then
    echo "ERRO: arquivo não encontrado: $1" >&2
    exit 1
  fi
  if [ -n "$secao" ]; then
    local sec_re="${secao//[/\\[}"
    sec_re="${sec_re//]/\\]}"
    escopo="/^${sec_re}\$/,/^\\[/"
  fi
  local padrao="^([[:space:]]*)(${chave}).*\$"
  if ! sed -n -E "${escopo}{/${padrao}/p}" "$arquivo" | grep -q .; then
    echo "ERRO: chave '${chave}'${secao:+ na seção ${secao}} não encontrada em $1" >&2
    exit 1
  fi
  sed -i -E "${escopo}{s|${padrao}|\\1$(escapa_sed "$nova")|}" "$arquivo"
}

# Cargo.toml: metadados do executável do Windows e do bundle do macOS.
substitui Cargo.toml "[package.metadata.winres]" 'OriginalFilename[[:space:]]*=' "OriginalFilename = \"$BINARIO.exe\""
substitui Cargo.toml "[package.metadata.winres]" 'ProductName[[:space:]]*='      "ProductName = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.winres]" 'FileDescription[[:space:]]*='  "FileDescription = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.bundle]" 'name[[:space:]]*='             "name = \"$EXIBICAO\""
substitui Cargo.toml "[package.metadata.bundle]" 'identifier[[:space:]]*='       "identifier = \"$IDENTIFICADOR\""

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

echo "Variante '$1' aplicada em $RAIZ"
