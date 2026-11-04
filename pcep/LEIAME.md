# Pc&P Desk (fork do RustDesk)

Este repositório é um fork do [RustDesk](https://github.com/rustdesk/rustdesk) (AGPL-3.0) mantido pela Pc&P Contábil.
Código-fonte: https://github.com/DevPCEP/pcep-desk-app

O fork gera dois aplicativos a partir do mesmo código, escolhidos na compilação:

| | cliente | colaborador |
|---|---|---|
| `PCEP_VARIANTE` | `cliente` | `colaborador` |
| APP_NAME (técnico) | `PcepDesk` | `PcepDeskEquipe` |
| Nome de exibição | Pc&P Desk | Pc&P Desk Equipe |
| Nome do binário | `pcep-desk` | `pcep-desk-equipe` |
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

## Sincronizar com o upstream

```
git fetch upstream
git merge upstream/master
```

Todo gancho no código do upstream é marcado com o comentário `PCEP:` (`// PCEP:` em Rust e Dart).
Para achar todos: `git grep "PCEP:"`.
