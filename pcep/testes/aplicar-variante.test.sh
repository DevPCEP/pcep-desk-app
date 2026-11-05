#!/usr/bin/env bash
# Teste de pcep/aplicar-variante.sh usando cópias dos arquivos reais do fork.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$AQUI/../.." && pwd)"
SCRIPT="$REPO/pcep/aplicar-variante.sh"
CR=$'\r'

ALVOS=(
  Cargo.toml
  libs/portable/Cargo.toml
  flutter/windows/runner/Runner.rc
  flutter/windows/CMakeLists.txt
  flutter/linux/CMakeLists.txt
  flutter/linux/my_application.cc
  flutter/macos/Runner/Configs/AppInfo.xcconfig
  build.py
  appimage/AppImageBuilder-x86_64.yml
  res/rustdesk.service
  res/rustdesk.desktop
  res/rustdesk-link.desktop
  res/DEBIAN/postinst
  res/DEBIAN/preinst
  res/DEBIAN/prerm
  res/DEBIAN/postrm
)
TAB=$'\t'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FALHAS=0

falha() { echo "FALHOU: $*" >&2; FALHAS=$((FALHAS + 1)); }

# Cria uma raiz temporária com cópias dos arquivos reais.
nova_raiz() {
  local raiz="$1" f
  for f in "${ALVOS[@]}"; do
    mkdir -p "$raiz/$(dirname "$f")"
    cp "$REPO/$f" "$raiz/$f"
  done
}

# Converte todos os alvos de uma raiz para CRLF (como um checkout com autocrlf no Windows).
para_crlf() {
  local raiz="$1" f
  for f in "${ALVOS[@]}"; do
    sed -i 's/$/\r/' "$raiz/$f"
  done
}

# FIM é o final de linha esperado ("" para LF, "$CR" para CRLF).
FIM=""
espera() { # arquivo, texto literal esperado (linha inteira)
  grep -qxF -- "$2$FIM" "$1" || falha "$1 não contém a linha: $2"
}

conta() { # arquivo, texto literal -> quantidade de linhas iguais
  grep -cxF -- "$2$FIM" "$1" || true
}

verifica_variante() { # raiz binario exibicao exibicao_rc identificador produto_mac
  local r="$1" bin="$2" exib="$3" exib_rc="$4" id="$5" mac="$6"
  espera "$r/Cargo.toml" "ProductName = \"$exib\""
  espera "$r/Cargo.toml" "FileDescription = \"$exib\""
  espera "$r/Cargo.toml" "OriginalFilename = \"$bin.exe\""
  # Empacotador portátil (libs/portable): metadados winres da variante.
  espera "$r/libs/portable/Cargo.toml" "ProductName = \"$exib\""
  espera "$r/libs/portable/Cargo.toml" "FileDescription = \"$exib\""
  espera "$r/libs/portable/Cargo.toml" "OriginalFilename = \"$bin.exe\""
  espera "$r/Cargo.toml" "name = \"$exib\""
  espera "$r/Cargo.toml" "identifier = \"$id\""
  local rc="$r/flutter/windows/runner/Runner.rc"
  espera "$rc" "            VALUE \"CompanyName\", \"PC&&P Contabilidade\" \"\\0\""
  espera "$rc" "            VALUE \"FileDescription\", \"$exib_rc\" \"\\0\""
  espera "$rc" "            VALUE \"InternalName\", \"$bin\" \"\\0\""
  espera "$rc" "            VALUE \"OriginalFilename\", \"$bin.exe\" \"\\0\""
  espera "$rc" "            VALUE \"ProductName\", \"$exib_rc\" \"\\0\""
  espera "$r/flutter/windows/CMakeLists.txt" "set(BINARY_NAME \"$bin\")"
  espera "$r/flutter/windows/CMakeLists.txt" "project(rustdesk LANGUAGES CXX)"
  espera "$r/flutter/linux/CMakeLists.txt" "set(BINARY_NAME \"$bin\")"
  espera "$r/flutter/linux/CMakeLists.txt" "set(APPLICATION_ID \"$id\")"
  # Título GTK do Linux: nome de exibição nas duas chamadas; o nome do ícone não muda.
  local gtk="$r/flutter/linux/my_application.cc"
  espera "$gtk" "    gtk_header_bar_set_title(header_bar, \"$exib\");"
  espera "$gtk" "    gtk_window_set_title(window, \"$exib\");"
  if grep -qE 'set_title\(.*"rustdesk"' "$gtk"; then falha "my_application.cc: título ainda é \"rustdesk\""; fi
  grep -qF "gtk_icon_theme_load_icon(theme, \"$bin\"," "$gtk" || falha "my_application.cc: ícone não procura \"$bin\" no tema"
  if grep -qF '"rustdesk"' "$gtk"; then falha "my_application.cc: ainda contém \"rustdesk\" entre aspas"; fi
  espera "$r/flutter/macos/Runner/Configs/AppInfo.xcconfig" "PRODUCT_NAME = $mac"
  espera "$r/flutter/macos/Runner/Configs/AppInfo.xcconfig" "PRODUCT_BUNDLE_IDENTIFIER = $id"
  # build.py (macOS): o binário `service` é copiado para dentro do .app da variante.
  espera "$r/build.py" "    system2('cp -rf ../target/release/service ./build/macos/Build/Products/Release/$mac.app/Contents/MacOS/')"
  # Receita do AppImage: executável da variante dentro do bundle instalado por build.py.
  espera "$r/appimage/AppImageBuilder-x86_64.yml" "    exec: usr/share/$bin/$bin"
  verifica_deb "$r" "$bin" "$exib"
}

# Pacote .deb: arquivos res/<binario>.*, scripts DEBIAN e build.py.
verifica_deb() { # raiz binario exibicao
  local r="$1" bin="$2" exib="$3" f
  for f in "res/$bin.service" "res/$bin.desktop" "res/$bin-link.desktop"; do
    [ -f "$r/$f" ] || falha "$f não foi gerado"
    if grep -qi rustdesk "$r/$f"; then falha "$f ainda menciona rustdesk"; fi
  done
  for f in postinst preinst prerm postrm; do
    if grep -qi rustdesk "$r/res/DEBIAN/$f"; then falha "res/DEBIAN/$f ainda menciona rustdesk"; fi
  done
  # Os modelos do upstream ficam intactos (rodar de novo e trocar de variante dependem deles).
  grep -q '^Name=RustDesk' "$r/res/rustdesk.desktop" || falha "modelo res/rustdesk.desktop foi alterado"
  espera "$r/res/$bin.service" "Description=$exib"
  espera "$r/res/$bin.service" "ExecStart=/usr/bin/$bin --service"
  espera "$r/res/$bin.desktop" "Name=$exib"
  espera "$r/res/$bin.desktop" "Exec=$bin %u"
  espera "$r/res/$bin.desktop" "Icon=$bin"
  espera "$r/res/$bin.desktop" "StartupWMClass=$bin"
  espera "$r/res/$bin-link.desktop" "MimeType=x-scheme-handler/$bin;"
  espera "$r/res/$bin-link.desktop" "TryExec=$bin"
  espera "$r/res/DEBIAN/postinst" "${TAB}ln -f -s /usr/share/$bin/$bin /usr/bin/$bin"
  espera "$r/res/DEBIAN/postinst" "${TAB}${TAB}systemctl enable $bin"
  espera "$r/res/DEBIAN/postinst" "${TAB}${TAB}cp /usr/share/$bin/files/systemd/$bin.service /usr/lib/systemd/system/$bin.service"
  espera "$r/res/DEBIAN/prerm" "${TAB}${TAB}${TAB}systemctl stop $bin || true"
  espera "$r/res/DEBIAN/postrm" "${TAB}${TAB}rm -rf /root/.config/$bin || true"
  local b="$r/build.py"
  espera "$b" "    content = \"\"\"Package: $bin"
  espera "$b" "Maintainer: PCEP <dev@pcepcontabil.com.br>"
  espera "$b" "Homepage: https://github.com/DevPCEP/pcep-desk-app"
  espera "$b" "Description: $exib"
  espera "$b" "    system2('mkdir -p tmpdeb/usr/share/$bin')"
  espera "$b" "        'cp ../res/$bin.service tmpdeb/usr/share/$bin/files/systemd/')"
  espera "$b" "        'cp ../res/$bin-link.desktop tmpdeb/usr/share/applications/$bin-link.desktop')"
  espera "$b" "    system2('dpkg-deb -b tmpdeb $bin.deb;')"
  espera "$b" "    os.rename('$bin.deb', '../$bin-%s.deb' % version)"
  local corpo
  corpo="$(corpo_funcao "$b" build_flutter_deb)"
  [ -n "$corpo" ] || falha "não achei o corpo de build_flutter_deb"
  if echo "$corpo" | grep -qi rustdesk; then falha "build_flutter_deb ainda menciona rustdesk"; fi
  corpo="$(corpo_funcao "$b" generate_control_file)"
  [ -n "$corpo" ] || falha "não achei o corpo de generate_control_file"
  if echo "$corpo" | grep -qi rustdesk; then falha "generate_control_file ainda menciona rustdesk"; fi
  # Fora dessas duas funções (build_deb_from_folder, modo --drm) nada muda.
  espera "$b" "DRMTAP_DLOPEN_MARKER = b'/usr/lib/rustdesk/libdrmtap.so.0'"
  espera "$b" "DRM_PACKAGE_NAME = 'rustdesk-unattended-wayland'"
  espera "$b" "    system2('dpkg-deb -b tmpdeb rustdesk.deb;')"
  # AppImage: id, name e o diretório do bundle no AppDir.
  local y="$r/appimage/AppImageBuilder-x86_64.yml"
  espera "$y" "    id: $bin"
  espera "$y" "    name: $bin"
  espera "$y" "    icon: $bin"
  grep -qF "AppDir/usr/share/icons/hicolor/scalable/apps/$bin.svg" "$y" || falha "receita: ícone .svg sem o nome $bin"
  grep -qF "apps/$bin.png; done" "$y" || falha "receita: ícones .png sem o nome $bin"
  if grep -E '^[^#]*/apps/rustdesk\.' "$y" | grep -q .; then falha "receita: ainda copia ícone como rustdesk.*"; fi
  grep -qF -- ":\$APPDIR/usr/share/$bin/lib:" "$y" || falha "receita: APPDIR_LIBRARY_PATH sem usr/share/$bin/lib"
  espera "$y" " - bsdtar -zxvf rustdesk.deb"
}

# Corpo da função generate_control_file / build_flutter_deb do build.py (mesmos
# limites usados pelo script: até a próxima "def" ou constante de módulo).
corpo_funcao() { # arquivo função
  awk -v f="$2" '
    $0 ~ "^def " f "\\(" { p = 1; next }
    p && /^(def |[A-Z][A-Z_0-9]* =)/ { exit }
    p' "$1"
}

# build.py sem o corpo das duas funções do .deb (para provar que o resto não mudou).
build_py_fora_do_deb() { # arquivo
  awk '
    /^def generate_control_file\(/ { skip = 1; fim = "^def "; next }
    /^def build_flutter_deb\(/ { skip = 1; fim = "^(def |[A-Z][A-Z_0-9]* =)"; next }
    skip && $0 ~ fim { skip = 0 }
    !skip' "$1"
}

# Linhas que não podem duplicar após rodar duas vezes.
verifica_sem_duplicar() { # raiz
  local r="$1"
  [ "$(conta "$r/Cargo.toml" 'OriginalFilename = "pcepdeskequipe.exe"')" = 1 ] || falha "Cargo.toml: OriginalFilename duplicado"
  [ "$(conta "$r/flutter/linux/CMakeLists.txt" 'set(BINARY_NAME "pcepdeskequipe")')" = 1 ] || falha "linux CMake: BINARY_NAME duplicado"
  [ "$(grep -c 'VALUE "ProductName"' "$r/flutter/windows/runner/Runner.rc")" = 1 ] || falha "Runner.rc: ProductName duplicado"
  [ "$(grep -c 'PcepDeskEquipe.app' "$r/build.py")" = 1 ] || falha "build.py: .app da variante em mais de uma linha"
  [ "$(grep -c '^    exec:' "$r/appimage/AppImageBuilder-x86_64.yml")" = 1 ] || falha "receita: exec duplicado"
}

echo "== colaborador (e idempotência)"
R1="$TMP/colab"; nova_raiz "$R1"
PCEP_RAIZ="$R1" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "colaborador retornou erro"
verifica_variante "$R1" pcepdeskequipe "Pc&P Desk Equipe" "Pc&&P Desk Equipe" br.com.pcepcontabil.desk.equipe PcepDeskEquipe
cp -r "$R1" "$TMP/colab-1"
PCEP_RAIZ="$R1" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "segunda execução retornou erro"
diff -r "$TMP/colab-1" "$R1" >/dev/null || falha "segunda execução alterou arquivos (não idempotente)"
verifica_sem_duplicar "$R1"
for f in "${ALVOS[@]}"; do
  [ "$(wc -l < "$REPO/$f")" = "$(wc -l < "$R1/$f")" ] || falha "$f mudou de número de linhas"
done
# Nada além da linha esperada muda em build.py e na receita.
# build.py: fora das funções do .deb só a linha do service do macOS muda.
[ "$(diff <(build_py_fora_do_deb "$REPO/build.py") <(build_py_fora_do_deb "$R1/build.py") | grep -c '^[<>]')" = 2 ] || falha "build.py: mudou algo além da linha do service e das funções do .deb"
# Receita: exec, id, name, icon, 2 linhas de cópia de ícones e APPDIR_LIBRARY_PATH (7 linhas, 14 marcas no diff).
[ "$(diff "$REPO/appimage/AppImageBuilder-x86_64.yml" "$R1/appimage/AppImageBuilder-x86_64.yml" | grep -c '^[<>]')" = 14 ] || falha "receita: esperadas exatamente 7 linhas alteradas"
# Modelos do upstream e arquivos fora do escopo não mudam.
for f in res/rustdesk.service res/rustdesk.desktop res/rustdesk-link.desktop; do
  cmp -s "$REPO/$f" "$R1/$f" || falha "$f (modelo) foi alterado"
done

echo "== cliente"
R2="$TMP/cliente"; nova_raiz "$R2"
PCEP_RAIZ="$R2" bash "$SCRIPT" cliente >/dev/null 2>&1 || falha "cliente retornou erro"
verifica_variante "$R2" pcepdesk "Pc&P Desk" "Pc&&P Desk" br.com.pcepcontabil.desk PcepDesk

echo "== libs/portable/Cargo.toml: só as 3 linhas winres mudam; chave ausente falha (código 1)"
[ "$(diff "$REPO/libs/portable/Cargo.toml" "$R1/libs/portable/Cargo.toml" | grep -c '^[<>]')" = 6 ] || falha "portable: mais/menos de 3 linhas alteradas"
R10="$TMP/semportable"; nova_raiz "$R10"
sed -i '/^ProductName = /d' "$R10/libs/portable/Cargo.toml"
SAIDA="$(PCEP_RAIZ="$R10" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "portable sem ProductName deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'libs/portable/Cargo.toml' || falha "mensagem não cita libs/portable/Cargo.toml: $SAIDA"

echo "== trocar de variante sobre a mesma raiz"
PCEP_RAIZ="$R1" bash "$SCRIPT" cliente >/dev/null 2>&1 || falha "troca de variante retornou erro"
verifica_variante "$R1" pcepdesk "Pc&P Desk" "Pc&&P Desk" br.com.pcepcontabil.desk PcepDesk

echo "== arquivos CRLF (checkout no Windows): valores aplicados e CR preservado"
R7="$TMP/crlf"; nova_raiz "$R7"; para_crlf "$R7"
PCEP_RAIZ="$R7" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "CRLF: colaborador retornou erro"
FIM="$CR"
verifica_variante "$R7" pcepdeskequipe "Pc&P Desk Equipe" "Pc&&P Desk Equipe" br.com.pcepcontabil.desk.equipe PcepDeskEquipe
for f in "${ALVOS[@]}"; do
  # Toda linha continua terminando em CR (nenhuma virou LF puro).
  [ "$(grep -c "$CR\$" "$R7/$f")" = "$(wc -l < "$R7/$f")" ] || falha "CRLF: $f ficou com linhas sem CR"
done
cp -r "$R7" "$TMP/crlf-1"
PCEP_RAIZ="$R7" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "CRLF: segunda execução retornou erro"
diff -r "$TMP/crlf-1" "$R7" >/dev/null || falha "CRLF: segunda execução alterou arquivos (não idempotente)"
FIM=""

echo "== argumento inválido (código 2)"
R3="$TMP/invalido"; nova_raiz "$R3"
PCEP_RAIZ="$R3" bash "$SCRIPT" tecnico >/dev/null 2>&1; [ $? = 2 ] || falha "tecnico deveria sair com 2"
PCEP_RAIZ="$R3" bash "$SCRIPT" >/dev/null 2>&1; [ $? = 2 ] || falha "sem argumento deveria sair com 2"
for f in "${ALVOS[@]}"; do cmp -s "$REPO/$f" "$R3/$f" || falha "$f foi alterado com argumento inválido"; done

echo "== chave ausente (código 1)"
R4="$TMP/semchave"; nova_raiz "$R4"
sed -i '/VALUE "InternalName"/d' "$R4/flutter/windows/runner/Runner.rc"
SAIDA="$(PCEP_RAIZ="$R4" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "chave ausente deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'Runner.rc' || falha "mensagem não cita o arquivo: $SAIDA"
echo "$SAIDA" | grep -q 'InternalName' || falha "mensagem não cita a chave: $SAIDA"

echo "== chave ausente na seção certa do Cargo.toml (código 1)"
R5="$TMP/semsecao"; nova_raiz "$R5"
sed -i '/^identifier = /d' "$R5/Cargo.toml"
PCEP_RAIZ="$R5" bash "$SCRIPT" cliente >/dev/null 2>&1; [ $? = 1 ] || falha "identifier ausente deveria sair com 1"

echo "== arquivo ausente (código 1)"
R6="$TMP/semarquivo"; nova_raiz "$R6"; rm "$R6/flutter/linux/CMakeLists.txt"
PCEP_RAIZ="$R6" bash "$SCRIPT" cliente >/dev/null 2>&1; [ $? = 1 ] || falha "arquivo ausente deveria sair com 1"

echo "== build.py sem a linha do service (código 1, cita build.py)"
R8="$TMP/sembuildpy"; nova_raiz "$R8"
sed -i '/target\/release\/service/d' "$R8/build.py"
SAIDA="$(PCEP_RAIZ="$R8" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "build.py sem padrão deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'build.py' || falha "mensagem não cita build.py: $SAIDA"

echo "== receita do AppImage sem exec (código 1, cita a receita)"
R9="$TMP/semexec"; nova_raiz "$R9"
sed -i '/^    exec: /d' "$R9/appimage/AppImageBuilder-x86_64.yml"
SAIDA="$(PCEP_RAIZ="$R9" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "receita sem exec deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'AppImageBuilder-x86_64.yml' || falha "mensagem não cita a receita: $SAIDA"

echo "== .deb: arquivo/trecho do upstream ausente (código 1, cita o arquivo)"
R11="$TMP/semdebian"; nova_raiz "$R11"; rm "$R11/res/DEBIAN/postinst"
SAIDA="$(PCEP_RAIZ="$R11" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "sem res/DEBIAN/postinst deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'res/DEBIAN/postinst' || falha "mensagem não cita postinst: $SAIDA"
R12="$TMP/semmodelo"; nova_raiz "$R12"; rm "$R12/res/rustdesk-link.desktop"
SAIDA="$(PCEP_RAIZ="$R12" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "sem modelo .desktop deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'rustdesk-link.desktop' || falha "mensagem não cita o modelo: $SAIDA"
R13="$TMP/semmantenedor"; nova_raiz "$R13"; sed -i '/^Maintainer: /d' "$R13/build.py"
SAIDA="$(PCEP_RAIZ="$R13" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "build.py sem Maintainer deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'build.py' || falha "mensagem não cita build.py: $SAIDA"
R14="$TMP/semid"; nova_raiz "$R14"; sed -i '/^    id: /d' "$R14/appimage/AppImageBuilder-x86_64.yml"
SAIDA="$(PCEP_RAIZ="$R14" bash "$SCRIPT" cliente 2>&1)"; COD=$?
[ "$COD" = 1 ] || falha "receita sem id deveria sair com 1 (saiu $COD)"
echo "$SAIDA" | grep -q 'AppImageBuilder-x86_64.yml' || falha "mensagem não cita a receita: $SAIDA"

if [ "$FALHAS" -eq 0 ]; then echo "OK: todos os testes passaram"; else echo "$FALHAS falha(s)"; exit 1; fi
