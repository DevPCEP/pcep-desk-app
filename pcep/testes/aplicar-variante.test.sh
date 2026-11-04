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
  flutter/macos/Runner/Configs/AppInfo.xcconfig
  build.py
  appimage/AppImageBuilder-x86_64.yml
)

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
  espera "$r/flutter/macos/Runner/Configs/AppInfo.xcconfig" "PRODUCT_NAME = $mac"
  espera "$r/flutter/macos/Runner/Configs/AppInfo.xcconfig" "PRODUCT_BUNDLE_IDENTIFIER = $id"
  # build.py (macOS): o binário `service` é copiado para dentro do .app da variante.
  espera "$r/build.py" "    system2('cp -rf ../target/release/service ./build/macos/Build/Products/Release/$mac.app/Contents/MacOS/')"
  # Receita do AppImage: executável da variante dentro do bundle instalado por build.py.
  espera "$r/appimage/AppImageBuilder-x86_64.yml" "    exec: usr/share/rustdesk/$bin"
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
[ "$(diff "$REPO/build.py" "$R1/build.py" | grep -c '^[<>]')" = 2 ] || falha "build.py: mais de uma linha alterada"
[ "$(diff "$REPO/appimage/AppImageBuilder-x86_64.yml" "$R1/appimage/AppImageBuilder-x86_64.yml" | grep -c '^[<>]')" = 2 ] || falha "receita: mais de uma linha alterada"

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

if [ "$FALHAS" -eq 0 ]; then echo "OK: todos os testes passaram"; else echo "$FALHAS falha(s)"; exit 1; fi
