#!/usr/bin/env bash
# Teste de pcep/aplicar-variante.sh usando cópias dos arquivos reais do fork.
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$AQUI/../.." && pwd)"
SCRIPT="$REPO/pcep/aplicar-variante.sh"

ALVOS=(
  Cargo.toml
  flutter/windows/runner/Runner.rc
  flutter/windows/CMakeLists.txt
  flutter/linux/CMakeLists.txt
  flutter/macos/Runner/Configs/AppInfo.xcconfig
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

espera() { # arquivo, texto literal esperado (linha inteira)
  grep -qxF -- "$2" "$1" || falha "$1 não contém a linha: $2"
}

conta() { # arquivo, texto literal -> quantidade de linhas iguais
  grep -cxF -- "$2" "$1" || true
}

verifica_variante() { # raiz binario exibicao exibicao_rc identificador produto_mac
  local r="$1" bin="$2" exib="$3" exib_rc="$4" id="$5" mac="$6"
  espera "$r/Cargo.toml" "ProductName = \"$exib\""
  espera "$r/Cargo.toml" "FileDescription = \"$exib\""
  espera "$r/Cargo.toml" "OriginalFilename = \"$bin.exe\""
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
}

# Linhas que não podem duplicar após rodar duas vezes.
verifica_sem_duplicar() { # raiz
  local r="$1"
  [ "$(conta "$r/Cargo.toml" 'OriginalFilename = "pcep-desk-equipe.exe"')" = 1 ] || falha "Cargo.toml: OriginalFilename duplicado"
  [ "$(conta "$r/flutter/linux/CMakeLists.txt" 'set(BINARY_NAME "pcep-desk-equipe")')" = 1 ] || falha "linux CMake: BINARY_NAME duplicado"
  [ "$(grep -c 'VALUE "ProductName"' "$r/flutter/windows/runner/Runner.rc")" = 1 ] || falha "Runner.rc: ProductName duplicado"
}

echo "== colaborador (e idempotência)"
R1="$TMP/colab"; nova_raiz "$R1"
PCEP_RAIZ="$R1" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "colaborador retornou erro"
verifica_variante "$R1" pcep-desk-equipe "Pc&P Desk Equipe" "Pc&&P Desk Equipe" br.com.pcepcontabil.desk.equipe PcepDeskEquipe
cp -r "$R1" "$TMP/colab-1"
PCEP_RAIZ="$R1" bash "$SCRIPT" colaborador >/dev/null 2>&1 || falha "segunda execução retornou erro"
diff -r "$TMP/colab-1" "$R1" >/dev/null || falha "segunda execução alterou arquivos (não idempotente)"
verifica_sem_duplicar "$R1"
[ "$(wc -l < "$REPO/Cargo.toml")" = "$(wc -l < "$R1/Cargo.toml")" ] || falha "Cargo.toml mudou de número de linhas"

echo "== cliente"
R2="$TMP/cliente"; nova_raiz "$R2"
PCEP_RAIZ="$R2" bash "$SCRIPT" cliente >/dev/null 2>&1 || falha "cliente retornou erro"
verifica_variante "$R2" pcep-desk "Pc&P Desk" "Pc&&P Desk" br.com.pcepcontabil.desk PcepDesk

echo "== trocar de variante sobre a mesma raiz"
PCEP_RAIZ="$R1" bash "$SCRIPT" cliente >/dev/null 2>&1 || falha "troca de variante retornou erro"
verifica_variante "$R1" pcep-desk "Pc&P Desk" "Pc&&P Desk" br.com.pcepcontabil.desk PcepDesk

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

if [ "$FALHAS" -eq 0 ]; then echo "OK: todos os testes passaram"; else echo "$FALHAS falha(s)"; exit 1; fi
