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

# Escapa o texto para o lado de substituição do sed (delimitador "|" ou o
# informado em $2).
escapa_sed() {
  local s="$1" d="${2:-|}"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//"$d"/\\$d}"
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


# ---------------------------------------------------------------------------
# Pacote .deb do Linux (build.py --flutter): todo "rustdesk" do empacotamento
# vira o nome do binário da variante. O Rust já procura <app em minúsculas>
# (serviço systemd, .desktop, ~/.config/<app>), então o nome tem de ser o mesmo.
# ---------------------------------------------------------------------------

# Nomes que já podem estar no lugar do "rustdesk" se o script rodar de novo
# sobre a mesma árvore (idempotência e troca de variante). Se surgir uma
# variante nova, acrescentar aqui (a mais longa não precisa vir primeiro: o
# sed escolhe a maior correspondência).
NOMES_BIN='rustdesk|pcepdeskequipe|pcepdesk'
# Delimitador "~" nas trocas abaixo: as regexes usam "|" (alternância).
BIN_SED="$(escapa_sed "$BINARIO" '~')"
EXIBICAO_SED="$(escapa_sed "$EXIBICAO" '~')"

# gera_do_modelo <modelo> <destino>
#   Copia o arquivo do upstream (que continua intacto como modelo) trocando
#   "RustDesk" pelo nome de exibição e "rustdesk" pelo binário. O modelo não é
#   apagado: assim rodar de novo ou trocar de variante funciona, e os demais
#   empacotamentos do upstream (que não usamos) continuam achando o arquivo.
gera_do_modelo() {
  local modelo="$1" destino="$2"
  confere_arquivo "$modelo"
  cp "$RAIZ/$modelo" "$RAIZ/$destino"
  "$SED" -i -E "s~RustDesk~${EXIBICAO_SED}~g; s~rustdesk~${BIN_SED}~g" "$RAIZ/$destino"
  if grep -qi rustdesk "$RAIZ/$destino"; then
    echo "ERRO: sobrou 'rustdesk' em $destino" >&2
    exit 1
  fi
  if ! grep -qF -- "$BINARIO" "$RAIZ/$destino"; then
    echo "ERRO: $destino não recebeu o nome do binário (o modelo $modelo mudou?)" >&2
    exit 1
  fi
}

gera_do_modelo res/rustdesk.service      "res/$BINARIO.service"
gera_do_modelo res/rustdesk.desktop      "res/$BINARIO.desktop"
gera_do_modelo res/rustdesk-link.desktop "res/$BINARIO-link.desktop"

# res/DEBIAN/*: scripts de instalação, trocados no lugar (build.py os copia
# para dentro do pacote).
for f in postinst preinst prerm postrm; do
  confere_arquivo "res/DEBIAN/$f"
  if ! grep -qE "$NOMES_BIN" "$RAIZ/res/DEBIAN/$f"; then
    echo "ERRO: nenhum nome de binário encontrado em res/DEBIAN/$f (o upstream mudou?)" >&2
    exit 1
  fi
  "$SED" -i -E "s~(${NOMES_BIN})~${BIN_SED}~g" "$RAIZ/res/DEBIAN/$f"
  if grep -qi rustdesk "$RAIZ/res/DEBIAN/$f"; then
    echo "ERRO: sobrou 'rustdesk' em res/DEBIAN/$f" >&2
    exit 1
  fi
done

# substitui_na_funcao <arquivo> <função> <regex-do-fim> <regex-ERE> <substituição>
#   Troca (todas as ocorrências, com "~" como delimitador) só dentro do corpo
#   da função Python, que vai da linha "def <função>(" até a linha que casa
#   <regex-do-fim> (esta fica de fora). Falha se a regex não casar nada.
substitui_na_funcao() {
  local arquivo="$RAIZ/$1" funcao="$2" fim="$3" regex="$4" troca="$5"
  local faixa="/^def ${funcao}\\(/,/${fim}/"
  confere_arquivo "$1"
  if ! "$SED" -n -E "${faixa}{/${fim}/!{\\~${regex}~p}}" "$arquivo" | grep -q .; then
    echo "ERRO: ${regex} não encontrado na função ${funcao} de $1 (o upstream mudou?)" >&2
    exit 1
  fi
  "$SED" -i -E "${faixa}{/${fim}/!{s~${regex}~${troca}~g}}" "$arquivo"
}

# sem_rustdesk_na_funcao <arquivo> <função> <regex-do-fim>
sem_rustdesk_na_funcao() {
  local arquivo="$RAIZ/$1" funcao="$2" fim="$3"
  if "$SED" -n -E "/^def ${funcao}\\(/,/${fim}/{/${fim}/!p}" "$arquivo" | grep -qi rustdesk; then
    echo "ERRO: sobrou 'rustdesk' na função ${funcao} de $1" >&2
    exit 1
  fi
}

# build.py: control do .deb (generate_control_file) e montagem do pacote
# (build_flutter_deb). build_deb_from_folder e o modo --drm não são usados no CI.
FIM_CONTROL='^def '
# build_flutter_deb termina na próxima função ou na primeira constante de módulo
# (DRMTAP_DLOPEN_MARKER, que tem um caminho do upstream e não pode mudar).
FIM_DEB='^(def |[A-Z][A-Z_0-9]* =)'
MANTENEDOR='PCEP <dev@pcepcontabil.com.br>'
PAGINA='https://github.com/DevPCEP/pcep-desk-app'

substitui_na_funcao build.py generate_control_file "$FIM_CONTROL" \
  'Package: [A-Za-z0-9.+-]+' "Package: ${BIN_SED}"
substitui_na_funcao build.py generate_control_file "$FIM_CONTROL" \
  "^Maintainer: [^${CR}]*" "Maintainer: $(escapa_sed "$MANTENEDOR" '~')"
substitui_na_funcao build.py generate_control_file "$FIM_CONTROL" \
  "^Homepage: [^${CR}]*" "Homepage: $(escapa_sed "$PAGINA" '~')"
substitui_na_funcao build.py generate_control_file "$FIM_CONTROL" \
  "^Description: [^${CR}]*" "Description: ${EXIBICAO_SED}"
sem_rustdesk_na_funcao build.py generate_control_file "$FIM_CONTROL"

substitui_na_funcao build.py build_flutter_deb "$FIM_DEB" \
  "(${NOMES_BIN})" "${BIN_SED}"
sem_rustdesk_na_funcao build.py build_flutter_deb "$FIM_DEB"

# Receita do AppImage: o .deb passa a instalar o bundle em usr/share/<binario>/,
# e o executável dentro dele é o BINARY_NAME. Também troca o identificador, o
# nome e o diretório do bundle no AppDir.
# O `bsdtar rustdesk.deb` da receita fica: o workflow renomeia o .deb para isso.
substitui_trecho appimage/AppImageBuilder-x86_64.yml "exec do AppImage" \
  "^(    exec: usr/share/)[A-Za-z0-9_-]+/[A-Za-z0-9_-]+(${CR}?)\$" \
  "\\1$(escapa_sed "$BINARIO")/$(escapa_sed "$BINARIO")\\2"
substitui_trecho appimage/AppImageBuilder-x86_64.yml "app_info.id do AppImage" \
  "^(    id: )[A-Za-z0-9_-]+(${CR}?)\$" \
  "\\1$(escapa_sed "$BINARIO")\\2"
substitui_trecho appimage/AppImageBuilder-x86_64.yml "app_info.name do AppImage" \
  "^(    name: )[A-Za-z0-9_-]+(${CR}?)\$" \
  "\\1$(escapa_sed "$BINARIO")\\2"
substitui_trecho appimage/AppImageBuilder-x86_64.yml "APPDIR_LIBRARY_PATH do AppImage" \
  '(:\$APPDIR/usr/share/)[A-Za-z0-9_-]+(/lib:)' \
  "\\1$(escapa_sed "$BINARIO")\\2"

echo "Variante '$1' aplicada em $RAIZ"
