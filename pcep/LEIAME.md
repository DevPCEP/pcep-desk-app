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
| Linux x86_64 (AppImage) | `PcepDesk-Linux-x86_64.AppImage` | `PcepDeskEquipe-Linux-x86_64.AppImage` |
| Linux x86_64 (.deb) | `PcepDesk-Linux-x86_64.deb` | `PcepDeskEquipe-Linux-x86_64.deb` |
| macOS Apple Silicon | `PcepDesk-macOS-arm64.dmg` | `PcepDeskEquipe-macOS-arm64.dmg` |

> macOS Intel fora dos builds desde 2026-11-04 (runners `macos-15-intel` escassos). Para voltar, restaurar a entrada x64 da matriz `macos` no `pcep-build.yml`.

### Pendências do empacotamento

- **Sem assinatura de código em nenhuma plataforma por enquanto.** O Windows já está preparado (ver "Assinatura do Windows" abaixo) e passa a assinar quando os segredos existirem; codesign e notarização (macOS) do upstream foram deixados de fora. Sem certificado, o Windows mostra o aviso do SmartScreen e o macOS exige liberar o app em Ajustes → Privacidade e Segurança (ou `xattr -d com.apple.quarantine`).
- `pcep/aplicar-variante.sh` ajusta, além dos nomes, os arquivos do upstream que fixam o nome `rustdesk`: `build.py` (caminho `RustDesk.app` ao copiar o binário `service`, macOS, e as funções `generate_control_file` e `build_flutter_deb` do `.deb`) e `appimage/AppImageBuilder-x86_64.yml` (`exec`, `app_info.id/name` e `APPDIR_LIBRARY_PATH`, todos apontando para `usr/share/<binario>/`). Cada ajuste falha se a linha do upstream não casar mais, em vez de gerar um pacote quebrado. O script precisa de GNU sed (`brew install gnu-sed` no macOS) e tolera arquivos CRLF.
- **Pacote `.deb` com nomes próprios.** O script gera `res/<binario>.service`, `res/<binario>.desktop` e `res/<binario>-link.desktop` a partir dos modelos `res/rustdesk.*` (que ficam intactos) e troca `rustdesk` por `<binario>` em `res/DEBIAN/*`. Resultado: `Package: <binario>`, `Maintainer: PCEP <dev@pcepcontabil.com.br>`, instalação em `/usr/share/<binario>/`, link `/usr/bin/<binario>`, serviço systemd `<binario>.service` (habilitado e iniciado no `postinst`, nas duas variantes) e `/usr/share/applications/<binario>.desktop`. Não há `Conflicts/Replaces` com o `rustdesk` oficial: os dois podem estar instalados juntos. Só a biblioteca interna `lib/librustdesk.so` mantém o nome (o Dart a carrega por esse nome). O job `linux` instala e remove o `.deb` no runner como teste antes de publicá-lo. Não foram adaptados `build_deb_from_folder` e o modo `--drm` do `build.py`, que o CI não usa.
- `res/scalable.svg` (ícone do menu no Linux, usado pelo `.deb` e pelo AppImage) é gerado por `pcep/icones/gerar.sh`, que copia o ícone da variante para esse caminho.
- O executável portátil do Windows (`libs/portable`) herda o ícone de `res/icon.ico` e os metadados de versão (`ProductName`, `FileDescription`) de `libs/portable/Cargo.toml`, ambos já ajustados à variante.

## Assinatura do Windows

O job `windows` assina com `signtool` (via `pcep/assinar-windows.ps1`) os `.exe`/`.dll` de `./rustdesk` antes do empacotamento (ignora `drivers\`, `usbmmidd_v2\` e arquivos já com assinatura válida) e, depois, o executável portátil final. É opcional: sem os segredos abaixo o passo só avisa "sem certificado" e o build segue com executáveis não assinados.

Para ligar: em Settings → Secrets and variables → Actions → Secrets, criar

- `PCEP_ASSINATURA_PFX`: o certificado de code signing em PFX, em base64 (`base64 -w0 certificado.pfx`);
- `PCEP_ASSINATURA_SENHA`: a senha do PFX.

Os dois precisam existir juntos; só um deles definido faz o build falhar. A assinatura usa SHA-256 e carimbo de tempo da DigiCert (`http://timestamp.digicert.com`), e o script confere que cada arquivo assinado ficou com certificado.

Certificados atuais emitidos na nuvem (Certum na nuvem, Azure Artifact Signing) não exportam PFX. Nesse caso só o trecho do `signtool` dentro de `pcep/assinar-windows.ps1` muda (ponto único); o restante (passos do workflow, escolha dos arquivos, conferência) continua igual.

Testar a mecânica sem certificado real (certificado autoassinado criado na hora, só em execução manual; nunca vale em tag):

```
gh workflow run pcep-build.yml -R DevPCEP/pcep-desk-app -f variante=cliente -f assinatura_teste=true
```

Nesse modo o workflow também confere que os executáveis ficaram com certificado e que uma senha errada faz o script falhar. O status da assinatura fica `NotTrusted`/`UnknownError` por ser autoassinada; isso é esperado, e o artefato desse teste não deve ser distribuído.

## Sincronizar com o upstream

```
git fetch upstream
git merge upstream/master
```

Todo gancho no código do upstream é marcado com o comentário `PCEP:` (`// PCEP:` em Rust e Dart).
Para achar todos: `git grep "PCEP:"`.
