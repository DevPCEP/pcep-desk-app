# Pc&P Desk (fork do RustDesk)

Este repositório é um fork do [RustDesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0) mantido pela Pc&P Contábil.
Código-fonte: https://github.com/DevPCEP/pcep-desk-app

O fork gera dois aplicativos a partir do mesmo código, escolhidos na compilação:

| | cliente | colaborador |
|---|---|---|
| `PCEP_VARIANTE` | `cliente` | `colaborador` |
| APP_NAME (técnico) | `PcepDesk` | `PcepDeskEquipe` |
| Nome de exibição | Pc&P Desk | Pc&P Desk Equipe |
| Nome do binário (APP_NAME em minúsculas, como `RustDesk` → `rustdesk`) | `pcepdesk` | `pcepdeskequipe` |
| Identificador (macOS/Linux) | `br.com.pcepcontabil.desk` | `br.com.pcepcontabil.desk.equipe` |
| Papel | só recebe conexões | conecta aos clientes (exige login) |

## Variáveis de compilação

Lidas com `option_env!` pelo crate `libs/pcep`. No CI vêm de *Repository variables* (não são segredos).

| Variável | Conteúdo |
|---|---|
| `PCEP_VARIANTE` | `cliente` ou `colaborador` (sem ela, o build é o RustDesk normal) |
| `PCEP_SERVIDOR` | só o host do servidor (nome ou IPv4, ex.: `desk.exemplo.com.br`), sem porta, `http://` ou barras; o RustDesk usa as portas padrão (21116 hbbs, 21117 hbbr). IPv6 não é suportado |
| `PCEP_CHAVE` | conteúdo de `id_ed25519.pub` (base64 de 32 bytes) |
| `PCEP_API` | URL `http://` ou `https://` do painel |

Um build de release nunca pode sair sem esses valores nem apontando para `rustdesk.com`.

## Compilação no GitHub Actions

Workflow: `.github/workflows/pcep-build.yml`. Dispara manualmente (`workflow_dispatch`, input `variante` = `ambas` | `cliente` | `colaborador`) ou por push de tag `pcep-v*`, que também cria a release com os entregáveis.

Antes de qualquer compilação, o job `validar` confere `PCEP_SERVIDOR`, `PCEP_CHAVE` e `PCEP_API` (Settings → Secrets and variables → Actions → Variables) e falha se estiverem vazias, inválidas ou apontando para `rustdesk.com`. Em seguida: ponte flutter_rust_bridge (como o upstream), ícones (`pcep/icones/gerar.sh`), `pcep/aplicar-variante.sh` e os passos de build copiados do `flutter-build.yml` do upstream (mesmas versões de toolchain e ações fixadas).

Entregáveis (nomes fixos, sem versão, para links estáveis `releases/latest/download/<nome>`):

| Plataforma | cliente | colaborador |
|---|---|---|
| Windows x64 (portátil) | `PcepDesk-Windows-x64.exe` | `PcepDeskEquipe-Windows-x64.exe` |
| Linux x86_64 | `PcepDesk-Linux-x86_64.AppImage` | `PcepDeskEquipe-Linux-x86_64.AppImage` |
| macOS Apple Silicon | `PcepDesk-macOS-arm64.dmg` | `PcepDeskEquipe-macOS-arm64.dmg` |

> macOS Intel fora dos builds desde 2026-11-04 (runners `macos-15-intel` escassos). Para voltar, restaurar a entrada x64 da matriz `macos` no `pcep-build.yml`.

### Pendências do empacotamento

- **Sem assinatura de código em nenhuma plataforma.** Os passos de assinatura (Windows), codesign e notarização (macOS) do upstream foram deixados de fora: não há certificados. Windows mostra o aviso do SmartScreen e o macOS exige liberar o app em Ajustes → Privacidade e Segurança (ou `xattr -d com.apple.quarantine`).
- `pcep/aplicar-variante.sh` ajusta, além dos nomes, dois arquivos do upstream que fixam o nome `rustdesk`: `build.py` (caminho `RustDesk.app` ao copiar o binário `service`, macOS) e `appimage/AppImageBuilder-x86_64.yml` (`exec: usr/share/rustdesk/rustdesk`). Cada ajuste falha se a linha do upstream não casar mais, em vez de gerar um pacote quebrado. O script precisa de GNU sed (`brew install gnu-sed` no macOS) e tolera arquivos CRLF.
- **Pacote `.deb` não publicado.** O empacotamento deb do upstream (`build.py`, `res/DEBIAN/postinst`, `res/rustdesk.service`, `res/rustdesk*.desktop`) ainda está preso ao nome `rustdesk`: `Package: rustdesk`, instalação em `/usr/share/rustdesk/`, link `/usr/bin/rustdesk -> /usr/share/rustdesk/rustdesk` (que não existe mais) e `systemctl start rustdesk` no `postinst`. O `.deb` é gerado só como insumo do AppImage; para publicá-lo é preciso adaptar Package/postinst/service/desktop à variante.
- `res/scalable.svg` (ícone do menu no Linux) não é gerado por `pcep/icones/gerar.sh`; continua sendo o do RustDesk.
- O executável portátil do Windows (`libs/portable`) herda o ícone de `res/icon.ico` (já do Pc&P Desk), mas os metadados de versão (`ProductName`, `FileDescription`) vêm de `libs/portable/Cargo.toml` e ainda dizem "RustDesk".

## Sincronizar com o upstream

```
git fetch upstream
git merge upstream/master
```

Todo gancho no código do upstream é marcado com o comentário `PCEP:` (`// PCEP:` em Rust e Dart).
Para achar todos: `git grep "PCEP:"`.
