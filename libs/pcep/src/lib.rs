//! Regras das variantes do Pc&P Desk (fork do RustDesk).
//!
//! Este crate concentra, sem depender do restante do RustDesk, tudo o que
//! diferencia as duas variantes do app (`cliente` e `colaborador`): nomes,
//! validação dos valores embutidos, o JSON de configuração personalizada
//! (mesmo formato do `custom.txt` do RustDesk) e a checagem de conexões de saída.
//!
//! Os valores embutidos (`PCEP_VARIANTE`, `PCEP_SERVIDOR`, `PCEP_CHAVE`,
//! `PCEP_API`) vêm de `option_env!` na compilação deste crate, ou seja, ficam
//! gravados no binário. Sem `PCEP_VARIANTE` o build é o RustDesk normal.

use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::{json, Map, Value};
use std::fmt;
use std::sync::OnceLock;

/// Variante do aplicativo, escolhida na compilação.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Variant {
    /// App instalado no computador do cliente: só recebe conexões.
    Cliente,
    /// App da equipe: conecta aos clientes, exige login.
    Colaborador,
}

impl Variant {
    /// Interpreta o valor de `PCEP_VARIANTE` (`cliente` ou `colaborador`).
    pub fn parse(s: &str) -> Option<Variant> {
        match s.trim() {
            "cliente" => Some(Variant::Cliente),
            "colaborador" => Some(Variant::Colaborador),
            _ => None,
        }
    }

    /// Nome técnico (ASCII) usado como `APP_NAME` do RustDesk; define a pasta de configuração.
    pub fn app_name(self) -> &'static str {
        match self {
            Variant::Cliente => "PcepDesk",
            Variant::Colaborador => "PcepDeskEquipe",
        }
    }

    /// Nome mostrado ao usuário.
    pub fn display_name(self) -> &'static str {
        match self {
            Variant::Cliente => "Pc&P Desk",
            Variant::Colaborador => "Pc&P Desk Equipe",
        }
    }
}

/// Valores crus, como vieram do ambiente de compilação.
pub struct RawValues<'a> {
    pub variant: Option<&'a str>,
    pub server: Option<&'a str>,
    pub key: Option<&'a str>,
    pub api: Option<&'a str>,
}

/// Valores validados e normalizados.
#[derive(Clone, Debug)]
pub struct BuildValues {
    pub variant: Variant,
    pub server: String,
    pub key: String,
    pub api: String,
}

/// Motivo da rejeição dos valores de compilação.
#[derive(Clone, Debug, PartialEq)]
pub enum ConfigError {
    MissingVariant,
    UnknownVariant(String),
    MissingServer,
    InvalidServer,
    MissingKey,
    InvalidKey,
    MissingApi,
    InvalidApi,
    PublicServer,
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::MissingVariant => write!(f, "PCEP_VARIANTE não foi definida"),
            ConfigError::UnknownVariant(v) => write!(
                f,
                "PCEP_VARIANTE desconhecida: \"{v}\" (use cliente ou colaborador)"
            ),
            ConfigError::MissingServer => write!(f, "PCEP_SERVIDOR não foi definida"),
            ConfigError::InvalidServer => write!(
                f,
                "PCEP_SERVIDOR deve ser só o endereço do servidor (ex.: desk.exemplo.com.br ou 192.168.0.10), sem porta, http:// ou barras"
            ),
            ConfigError::MissingKey => write!(f, "PCEP_CHAVE não foi definida"),
            ConfigError::InvalidKey => write!(
                f,
                "PCEP_CHAVE inválida: deve ser o conteúdo de id_ed25519.pub (base64 de 32 bytes)"
            ),
            ConfigError::MissingApi => write!(f, "PCEP_API não foi definida"),
            ConfigError::InvalidApi => write!(
                f,
                "PCEP_API inválida: deve começar com http:// ou https://"
            ),
            ConfigError::PublicServer => write!(
                f,
                "PCEP_SERVIDOR e PCEP_API não podem apontar para rustdesk.com (servidor público)"
            ),
        }
    }
}

impl std::error::Error for ConfigError {}

fn non_empty(s: Option<&str>) -> Option<&str> {
    s.map(str::trim).filter(|s| !s.is_empty())
}

// Checagem por substring, conservadora de propósito: qualquer coisa que mencione
// rustdesk.com (inclusive subdomínios, maiúsculas ou barra final) é recusada.
fn is_public(s: &str) -> bool {
    s.to_ascii_lowercase().contains("rustdesk.com")
}

/// Valida e normaliza os valores de compilação.
pub fn validate(raw: RawValues) -> Result<BuildValues, ConfigError> {
    let variant = non_empty(raw.variant).ok_or(ConfigError::MissingVariant)?;
    let variant =
        Variant::parse(variant).ok_or_else(|| ConfigError::UnknownVariant(variant.to_owned()))?;

    let server = non_empty(raw.server).ok_or(ConfigError::MissingServer)?;
    if is_public(server) {
        return Err(ConfigError::PublicServer);
    }
    // Só o host (nome ou IPv4): portas padrão do RustDesk (21116 hbbs, 21117 hbbr).
    // IPv6 fora de escopo (contém `:`).
    if server.contains(|c: char| c == ':' || c == '/' || c.is_whitespace()) {
        return Err(ConfigError::InvalidServer);
    }

    let key = non_empty(raw.key).ok_or(ConfigError::MissingKey)?;
    match STANDARD.decode(key) {
        Ok(bytes) if bytes.len() == 32 => {}
        _ => return Err(ConfigError::InvalidKey),
    }

    let api = non_empty(raw.api).ok_or(ConfigError::MissingApi)?;
    let api = api.trim_end_matches('/');
    let host = api
        .strip_prefix("https://")
        .or_else(|| api.strip_prefix("http://"))
        .ok_or(ConfigError::InvalidApi)?;
    if host.is_empty() {
        return Err(ConfigError::InvalidApi);
    }
    if is_public(api) {
        return Err(ConfigError::PublicServer);
    }

    Ok(BuildValues {
        variant,
        server: server.to_owned(),
        key: key.to_owned(),
        api: api.to_owned(),
    })
}

/// Valores embutidos na compilação. `None` quando `PCEP_VARIANTE` não foi definida
/// (build de desenvolvimento = RustDesk normal).
///
/// A decodificação/validação roda uma única vez; as chamadas seguintes devolvem uma cópia
/// do resultado em cache (é chamada a cada tradução de texto da interface).
pub fn embedded() -> Option<Result<BuildValues, ConfigError>> {
    static CACHE: OnceLock<Option<Result<BuildValues, ConfigError>>> = OnceLock::new();
    CACHE.get_or_init(compute_embedded).clone()
}

fn compute_embedded() -> Option<Result<BuildValues, ConfigError>> {
    let variant = option_env!("PCEP_VARIANTE")?;
    Some(validate(RawValues {
        variant: Some(variant),
        server: option_env!("PCEP_SERVIDOR"),
        key: option_env!("PCEP_CHAVE"),
        api: option_env!("PCEP_API"),
    }))
}

/// Configuração no formato do `custom.txt` do RustDesk (antes de assinar/codificar).
/// Chaves de topo vão para HARD_SETTINGS; `override-settings` → OVERWRITE.
pub fn custom_client_json(b: &BuildValues) -> Value {
    let mut over = Map::new();
    let mut set = |k: &str, v: &str| {
        over.insert(k.to_owned(), Value::String(v.to_owned()));
    };
    set("custom-rendezvous-server", &b.server);
    set("relay-server", &b.server);
    set("api-server", &b.api);
    set("key", &b.key);
    set("approve-mode", "click");
    set("enable-check-update", "N");
    set("allow-auto-update", "N");
    set("disable-change-id", "Y");
    set("hide-server-settings", "Y");
    set("hide-proxy-settings", "Y");
    set("hide-websocket-settings", "Y");
    if b.variant == Variant::Cliente {
        set("allow-only-conn-window-open", "Y");
        set("disable-change-permanent-password", "Y");
        set("allow-logon-screen-password", "N");
    }

    let mut top = json!({
        "app-name": b.variant.app_name(),
        "override-settings": Value::Object(over),
    });
    if b.variant == Variant::Cliente {
        let t = top.as_object_mut().expect("objeto");
        t.insert("conn-type".to_owned(), json!("incoming"));
        t.insert("disable-settings".to_owned(), json!("Y"));
        t.insert("disable-account".to_owned(), json!("Y"));
        t.insert("disable-ab".to_owned(), json!("Y"));
    }
    top
}

/// Bloqueia conexões de saída quando a variante não pode fazê-las.
pub fn check_outgoing(variant: Variant, access_token: &str) -> Result<(), &'static str> {
    match variant {
        Variant::Cliente => Err("Este aplicativo só recebe conexões."),
        Variant::Colaborador if access_token.trim().is_empty() => {
            Err("Faça login no Pc&P Desk Equipe para conectar.")
        }
        Variant::Colaborador => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // base64 de 32 bytes zero
    const KEY: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const SERVER: &str = "desk.exemplo.com.br";
    const API: &str = "https://desk.exemplo.com.br";

    fn raw<'a>(
        variant: Option<&'a str>,
        server: Option<&'a str>,
        key: Option<&'a str>,
        api: Option<&'a str>,
    ) -> RawValues<'a> {
        RawValues { variant, server, key, api }
    }

    fn ok_values(variant: &str) -> BuildValues {
        validate(raw(Some(variant), Some(SERVER), Some(KEY), Some(API))).unwrap()
    }

    #[test]
    fn validate_ok_trims_and_strips_slash() {
        let b = validate(raw(
            Some(" cliente "),
            Some(" desk.exemplo.com.br "),
            Some(&format!(" {KEY} ")),
            Some(" https://desk.exemplo.com.br/ "),
        ))
        .unwrap();
        assert_eq!(b.variant, Variant::Cliente);
        assert_eq!(b.server, "desk.exemplo.com.br");
        assert_eq!(b.key, KEY);
        assert_eq!(b.api, "https://desk.exemplo.com.br");
    }

    #[test]
    fn validate_rejects_missing_variant() {
        assert_eq!(
            validate(raw(None, Some(SERVER), Some(KEY), Some(API))).unwrap_err(),
            ConfigError::MissingVariant
        );
        assert_eq!(
            validate(raw(Some("  "), Some(SERVER), Some(KEY), Some(API))).unwrap_err(),
            ConfigError::MissingVariant
        );
    }

    #[test]
    fn validate_rejects_unknown_variant() {
        assert_eq!(
            validate(raw(Some("tecnico"), Some(SERVER), Some(KEY), Some(API))).unwrap_err(),
            ConfigError::UnknownVariant("tecnico".to_owned())
        );
    }

    #[test]
    fn validate_rejects_missing_server() {
        assert_eq!(
            validate(raw(Some("cliente"), None, Some(KEY), Some(API))).unwrap_err(),
            ConfigError::MissingServer
        );
        assert_eq!(
            validate(raw(Some("cliente"), Some(" "), Some(KEY), Some(API))).unwrap_err(),
            ConfigError::MissingServer
        );
    }

    #[test]
    fn validate_rejects_server_with_port() {
        assert_eq!(
            validate(raw(Some("cliente"), Some("desk.x:21116"), Some(KEY), Some(API)))
                .unwrap_err(),
            ConfigError::InvalidServer
        );
    }

    #[test]
    fn validate_rejects_server_with_scheme() {
        assert_eq!(
            validate(raw(Some("cliente"), Some("https://desk.x"), Some(KEY), Some(API)))
                .unwrap_err(),
            ConfigError::InvalidServer
        );
    }

    #[test]
    fn validate_rejects_server_with_path() {
        assert_eq!(
            validate(raw(Some("cliente"), Some("desk.x/abc"), Some(KEY), Some(API)))
                .unwrap_err(),
            ConfigError::InvalidServer
        );
        assert_eq!(
            validate(raw(Some("cliente"), Some("desk x"), Some(KEY), Some(API))).unwrap_err(),
            ConfigError::InvalidServer
        );
    }

    #[test]
    fn validate_accepts_ipv4() {
        let b = validate(raw(Some("cliente"), Some("192.168.0.10"), Some(KEY), Some(API)))
            .unwrap();
        assert_eq!(b.server, "192.168.0.10");
    }

    #[test]
    fn validate_public_check_ignores_case_and_trailing_slash() {
        assert_eq!(
            validate(raw(
                Some("cliente"),
                Some("RS-NY.RustDesk.COM"),
                Some(KEY),
                Some(API)
            ))
            .unwrap_err(),
            ConfigError::PublicServer
        );
        assert_eq!(
            validate(raw(
                Some("cliente"),
                Some(SERVER),
                Some(KEY),
                Some("https://admin.rustdesk.com/")
            ))
            .unwrap_err(),
            ConfigError::PublicServer
        );
    }

    #[test]
    fn validate_rejects_missing_key() {
        assert_eq!(
            validate(raw(Some("cliente"), Some(SERVER), None, Some(API))).unwrap_err(),
            ConfigError::MissingKey
        );
    }

    #[test]
    fn validate_rejects_bad_key() {
        assert_eq!(
            validate(raw(Some("cliente"), Some(SERVER), Some("abc"), Some(API))).unwrap_err(),
            ConfigError::InvalidKey
        );
        // base64 de 31 bytes zero
        let k31 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==";
        assert_eq!(
            validate(raw(Some("cliente"), Some(SERVER), Some(k31), Some(API))).unwrap_err(),
            ConfigError::InvalidKey
        );
    }

    #[test]
    fn validate_rejects_missing_api() {
        assert_eq!(
            validate(raw(Some("cliente"), Some(SERVER), Some(KEY), None)).unwrap_err(),
            ConfigError::MissingApi
        );
    }

    #[test]
    fn validate_rejects_bad_api() {
        assert_eq!(
            validate(raw(Some("cliente"), Some(SERVER), Some(KEY), Some("desk.exemplo")))
                .unwrap_err(),
            ConfigError::InvalidApi
        );
    }

    #[test]
    fn validate_rejects_public_server() {
        assert_eq!(
            validate(raw(
                Some("cliente"),
                Some("rs-ny.rustdesk.com"),
                Some(KEY),
                Some(API)
            ))
            .unwrap_err(),
            ConfigError::PublicServer
        );
        assert_eq!(
            validate(raw(
                Some("colaborador"),
                Some(SERVER),
                Some(KEY),
                Some("https://admin.rustdesk.com")
            ))
            .unwrap_err(),
            ConfigError::PublicServer
        );
    }

    #[test]
    fn app_names_differ_from_rustdesk() {
        assert_eq!(Variant::Cliente.app_name(), "PcepDesk");
        assert_eq!(Variant::Colaborador.app_name(), "PcepDeskEquipe");
        for v in [Variant::Cliente, Variant::Colaborador] {
            assert_ne!(v.app_name(), "RustDesk");
            assert!(v
                .app_name()
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-'));
        }
        assert_eq!(Variant::parse("cliente"), Some(Variant::Cliente));
        assert_eq!(Variant::parse("colaborador"), Some(Variant::Colaborador));
        assert_eq!(Variant::parse("x"), None);
        assert_eq!(Variant::Cliente.display_name(), "Pc&P Desk");
        assert_eq!(Variant::Colaborador.display_name(), "Pc&P Desk Equipe");
    }

    #[test]
    fn cliente_json_locks_settings() {
        let b = ok_values("cliente");
        let json = custom_client_json(&b);
        assert_eq!(json["app-name"], "PcepDesk");
        assert_eq!(json["conn-type"], "incoming");
        assert_eq!(json["disable-settings"], "Y");
        assert_eq!(json["disable-account"], "Y");
        assert_eq!(json["disable-ab"], "Y");
        let o = &json["override-settings"];
        assert_eq!(o["approve-mode"], "click");
        assert_eq!(o["custom-rendezvous-server"], SERVER);
        assert_eq!(o["relay-server"], SERVER);
        assert_eq!(o["key"], KEY);
        assert_eq!(o["api-server"], API);
        assert_eq!(o["enable-check-update"], "N");
        assert_eq!(o["allow-auto-update"], "N");
        assert_eq!(o["disable-change-id"], "Y");
        assert_eq!(o["hide-server-settings"], "Y");
        assert_eq!(o["hide-proxy-settings"], "Y");
        assert_eq!(o["hide-websocket-settings"], "Y");
        assert_eq!(o["disable-change-permanent-password"], "Y");
        assert_eq!(o["allow-logon-screen-password"], "N");
    }

    #[test]
    fn cliente_json_requires_open_window() {
        let json = custom_client_json(&ok_values("cliente"));
        assert_eq!(json["override-settings"]["allow-only-conn-window-open"], "Y");
    }

    #[test]
    fn colaborador_json_is_full_app() {
        let json = custom_client_json(&ok_values("colaborador"));
        assert_eq!(json["app-name"], "PcepDeskEquipe");
        assert!(json.get("conn-type").is_none());
        assert!(json.get("disable-settings").is_none());
        let o = &json["override-settings"];
        assert_eq!(o["approve-mode"], "click");
        assert_eq!(o["custom-rendezvous-server"], SERVER);
        assert_eq!(o["key"], KEY);
        assert_eq!(o["api-server"], API);
        assert!(o.get("allow-only-conn-window-open").is_none());
    }

    #[test]
    fn json_values_are_strings_for_read_custom_client() {
        // read_custom_client só aceita valores string nas chaves de topo e em override-settings
        for v in ["cliente", "colaborador"] {
            let json = custom_client_json(&ok_values(v));
            for (k, val) in json.as_object().unwrap() {
                if k != "override-settings" {
                    assert!(val.is_string(), "{k}");
                }
            }
            for (k, val) in json["override-settings"].as_object().unwrap() {
                assert!(val.is_string(), "{k}");
            }
        }
    }

    #[test]
    fn check_outgoing_cliente_blocked() {
        assert_eq!(
            check_outgoing(Variant::Cliente, "abc"),
            Err("Este aplicativo só recebe conexões.")
        );
    }

    #[test]
    fn check_outgoing_colaborador_requires_token() {
        let msg = "Faça login no Pc&P Desk Equipe para conectar.";
        assert_eq!(check_outgoing(Variant::Colaborador, ""), Err(msg));
        assert_eq!(check_outgoing(Variant::Colaborador, "   "), Err(msg));
        assert_eq!(check_outgoing(Variant::Colaborador, "abc"), Ok(()));
    }

    #[test]
    fn config_error_display_is_portuguese() {
        assert_eq!(
            ConfigError::UnknownVariant("x".into()).to_string(),
            "PCEP_VARIANTE desconhecida: \"x\" (use cliente ou colaborador)"
        );
        assert!(!ConfigError::PublicServer.to_string().is_empty());
    }

    #[test]
    fn embedded_em_cache_devolve_sempre_o_mesmo_resultado() {
        assert_eq!(format!("{:?}", embedded()), format!("{:?}", embedded()));
    }
}
