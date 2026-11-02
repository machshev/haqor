//! The app's client for `haqor-sync-server`.
//!
//! It mirrors `crates/haqor-sync-server/src/client.rs` in haqor-core, which
//! the command-line tools use; keep the two in step. It is duplicated rather
//! than shared so the app does not wait on a core release for sync changes.
//!
//! `https://` servers are trusted by certificate fingerprint ("pin") instead of
//! a certificate authority: the server's self-signed certificate is accepted
//! only when its SHA-256 matches the pin from the join link, and the TLS
//! handshake signature is still verified, so the server must hold the key.
//! The token is sent only after that check, so an address that reaches some
//! other machine (a home LAN address tried on another network) learns nothing.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

pub const MAX_SNAPSHOT_BYTES: usize = 64 * 1024 * 1024;
/// Short, because an unreachable address (the overlay while it is down, the
/// home network while away) is tried before the next one on every sync.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(4);
const IO_TIMEOUT: Duration = Duration::from_secs(30);

/// One parsed server address.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Endpoint {
    pub tls: bool,
    pub host: String,
    pub port: u16,
    pub path: String,
}

impl Endpoint {
    pub fn parse(input: &str) -> Result<Self, String> {
        let input = input.trim();
        let (tls, rest) = if let Some(rest) = input.strip_prefix("https://") {
            (true, rest)
        } else if let Some(rest) = input.strip_prefix("http://") {
            (false, rest)
        } else {
            return Err(format!(
                "Sync server {input} must start with https:// or http://."
            ));
        };
        let (authority, path) = match rest.find('/') {
            Some(index) if &rest[index..] == "/" => (&rest[..index], "/v1/progress"),
            Some(index) => (&rest[..index], &rest[index..]),
            None => (rest, "/v1/progress"),
        };
        if authority.is_empty() || authority.contains('@') {
            return Err(format!("Sync server address {input} is invalid."));
        }
        let (host, port) = match authority.rsplit_once(':') {
            Some((host, port)) if !host.is_empty() => (
                host.to_string(),
                port.parse::<u16>()
                    .map_err(|_| format!("Sync server port in {input} is invalid."))?,
            ),
            _ => (authority.to_string(), if tls { 443 } else { 80 }),
        };
        Ok(Self {
            tls,
            host,
            port,
            path: path.to_string(),
        })
    }

    /// Scheme, host and port, as shown to the learner and remembered as the
    /// address that last answered.
    pub fn display(&self) -> String {
        format!(
            "{}://{}:{}",
            if self.tls { "https" } else { "http" },
            self.host,
            self.port
        )
    }
}

/// Normalise a fingerprint as written in a join link or typed by hand:
/// lowercase hex, with any `:` separators removed.
pub fn normalise_pin(pin: &str) -> Result<String, String> {
    let pin = pin
        .trim()
        .chars()
        .filter(|c| *c != ':')
        .collect::<String>()
        .to_ascii_lowercase();
    if pin.len() != 64 || !pin.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("The certificate fingerprint must be 64 hex characters.".to_string());
    }
    Ok(pin)
}

#[cfg(not(target_arch = "wasm32"))]
mod tls {
    use std::sync::Arc;

    use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
    use rustls::crypto::{CryptoProvider, verify_tls12_signature, verify_tls13_signature};
    use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
    use rustls::{DigitallySignedStruct, SignatureScheme};

    pub fn cert_fingerprint(der: &[u8]) -> String {
        ring::digest::digest(&ring::digest::SHA256, der)
            .as_ref()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }

    #[derive(Debug)]
    struct PinnedCertificate {
        fingerprint: String,
        provider: Arc<CryptoProvider>,
    }

    impl ServerCertVerifier for PinnedCertificate {
        fn verify_server_cert(
            &self,
            end_entity: &CertificateDer<'_>,
            _intermediates: &[CertificateDer<'_>],
            _server_name: &ServerName<'_>,
            _ocsp_response: &[u8],
            _now: UnixTime,
        ) -> Result<ServerCertVerified, rustls::Error> {
            if cert_fingerprint(end_entity) == self.fingerprint {
                Ok(ServerCertVerified::assertion())
            } else {
                Err(rustls::Error::General(
                    "the server's certificate does not match the join link".into(),
                ))
            }
        }

        fn verify_tls12_signature(
            &self,
            message: &[u8],
            cert: &CertificateDer<'_>,
            dss: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, rustls::Error> {
            verify_tls12_signature(
                message,
                cert,
                dss,
                &self.provider.signature_verification_algorithms,
            )
        }

        fn verify_tls13_signature(
            &self,
            message: &[u8],
            cert: &CertificateDer<'_>,
            dss: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, rustls::Error> {
            verify_tls13_signature(
                message,
                cert,
                dss,
                &self.provider.signature_verification_algorithms,
            )
        }

        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            self.provider
                .signature_verification_algorithms
                .supported_schemes()
        }
    }

    pub fn wrap(
        stream: std::net::TcpStream,
        host: &str,
        fingerprint: String,
    ) -> Result<rustls::StreamOwned<rustls::ClientConnection, std::net::TcpStream>, String> {
        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let config = rustls::ClientConfig::builder_with_provider(provider.clone())
            .with_safe_default_protocol_versions()
            .map_err(|e| format!("Could not configure TLS: {e}"))?
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(PinnedCertificate {
                fingerprint,
                provider,
            }))
            .with_no_client_auth();
        let name = ServerName::try_from(host.to_string())
            .map_err(|e| format!("Invalid sync server name {host}: {e}"))?;
        let connection = rustls::ClientConnection::new(Arc::new(config), name)
            .map_err(|e| format!("Could not start TLS: {e}"))?;
        Ok(rustls::StreamOwned::new(connection, stream))
    }
}

trait Stream: Read + Write {}
impl<T: Read + Write> Stream for T {}

fn connect(endpoint: &Endpoint, pin: Option<&str>) -> Result<Box<dyn Stream>, String> {
    // Check the pin before touching the network: an https address without one
    // could never be trusted, so there is no point reaching it.
    let pin = match (endpoint.tls, pin.filter(|pin| !pin.trim().is_empty())) {
        (true, Some(pin)) => Some(normalise_pin(pin)?),
        (true, None) => {
            return Err(format!(
                "{} needs the certificate fingerprint from a join link",
                endpoint.display()
            ));
        }
        (false, _) => None,
    };
    let address = format!("{}:{}", endpoint.host, endpoint.port);
    let socket = address
        .to_socket_addrs()
        .map_err(|e| format!("could not resolve {}: {e}", endpoint.host))?
        .next()
        .ok_or_else(|| format!("could not resolve {}", endpoint.host))?;
    let stream = TcpStream::connect_timeout(&socket, CONNECT_TIMEOUT)
        .map_err(|e| format!("could not reach {}: {e}", endpoint.display()))?;
    let _ = stream.set_read_timeout(Some(IO_TIMEOUT));
    let _ = stream.set_write_timeout(Some(IO_TIMEOUT));
    let Some(pin) = pin else {
        return Ok(Box::new(stream));
    };
    #[cfg(not(target_arch = "wasm32"))]
    {
        Ok(Box::new(tls::wrap(stream, &endpoint.host, pin)?))
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = (stream, pin);
        Err("HTTPS sync is not available in the browser".to_string())
    }
}

/// POST a progress snapshot, trying `servers` in order. Returns the merged
/// snapshot and the address that answered. The first address that gives any
/// HTTP response is used, even an error response, so a wrong token is
/// reported rather than hidden behind the next address. A snapshot resent to a
/// second address after a broken connection is harmless: merging is
/// idempotent.
pub fn post_snapshot(
    servers: &[String],
    pin: Option<&str>,
    token: &str,
    body: &[u8],
) -> Result<(Vec<u8>, String), String> {
    if body.len() > MAX_SNAPSHOT_BYTES {
        return Err("Local progress snapshot is unexpectedly large.".to_string());
    }
    let endpoints = servers
        .iter()
        .filter(|s| !s.trim().is_empty())
        .map(|s| Endpoint::parse(s))
        .collect::<Result<Vec<_>, _>>()?;
    if endpoints.is_empty() {
        return Err("No sync server address is configured.".to_string());
    }
    let mut failures = Vec::new();
    for endpoint in &endpoints {
        match post_one(endpoint, pin, token, body) {
            Ok(Ok(merged)) => return Ok((merged, endpoint.display())),
            Ok(Err(status)) => {
                return Err(format!(
                    "Sync server {} returned {status}",
                    endpoint.display()
                ));
            }
            Err(message) => failures.push(message),
        }
    }
    Err(format!(
        "Could not reach the sync server: {}.",
        failures.join("; ")
    ))
}

/// Read the response headers up to the blank line, returning `Content-Length`.
fn read_content_length(reader: &mut impl BufRead) -> Result<Option<usize>, String> {
    let mut content_length = None;
    loop {
        let mut line = String::new();
        let read = reader
            .read_line(&mut line)
            .map_err(|e| format!("Could not read sync response: {e}"))?;
        if read == 0 {
            return Err("Sync server closed the connection mid-response.".to_string());
        }
        if line == "\r\n" || line == "\n" {
            break;
        }
        if let Some((name, value)) = line.split_once(':')
            && name.eq_ignore_ascii_case("content-length")
        {
            content_length = value.trim().parse::<usize>().ok();
        }
    }
    Ok(content_length)
}

/// `Err` when no HTTP response arrived; `Ok(Err(status))` for a non-200 one.
fn post_one(
    endpoint: &Endpoint,
    pin: Option<&str>,
    token: &str,
    body: &[u8],
) -> Result<Result<Vec<u8>, String>, String> {
    let mut stream = connect(endpoint, pin)?;
    let sent = write!(
        stream,
        "POST {} HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/vnd.sqlite3\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        endpoint.path,
        endpoint.host,
        body.len(),
    )
    .and_then(|()| stream.write_all(body))
    .and_then(|()| stream.flush());
    sent.map_err(|e| format!("{}: {e}", endpoint.display()))?;

    let mut reader = BufReader::new(stream);
    let mut status = String::new();
    reader
        .read_line(&mut status)
        .map_err(|e| format!("{}: {e}", endpoint.display()))?;
    if status.is_empty() {
        return Err(format!("{} closed the connection", endpoint.display()));
    }
    let status = status.trim().to_string();
    if !status.starts_with("HTTP/1.1 200") && !status.starts_with("HTTP/1.0 200") {
        return Ok(Err(status));
    }
    let length = read_content_length(&mut reader)?
        .ok_or_else(|| "Sync server omitted its response length.".to_string())?;
    if length > MAX_SNAPSHOT_BYTES {
        return Ok(Err("an unexpectedly large snapshot".to_string()));
    }
    let mut merged = vec![0; length];
    reader
        .read_exact(&mut merged)
        .map_err(|e| format!("Could not read progress snapshot: {e}"))?;
    Ok(Ok(merged))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints_parse_scheme_port_and_default_path() {
        assert_eq!(
            Endpoint::parse("https://10.0.0.2:8788"),
            Ok(Endpoint {
                tls: true,
                host: "10.0.0.2".into(),
                port: 8788,
                path: "/v1/progress".into()
            })
        );
        let plain = Endpoint::parse(" http://sync.example:8788/ ");
        assert_eq!(plain.as_ref().map(|e| e.tls), Ok(false));
        assert_eq!(plain.map(|e| e.path), Ok("/v1/progress".to_string()));
        assert_eq!(
            Endpoint::parse("https://sync-host.lan").map(|e| e.port),
            Ok(443)
        );
        assert!(Endpoint::parse("ftp://x").is_err());
        assert!(Endpoint::parse("http://user@x").is_err());
    }

    #[test]
    fn pins_are_normalised() {
        assert_eq!(normalise_pin(&"AB".repeat(32)), Ok("ab".repeat(32)));
        assert_eq!(
            normalise_pin(&vec!["ab"; 32].join(":")),
            Ok("ab".repeat(32))
        );
        assert!(normalise_pin("abc").is_err());
    }

    #[test]
    fn headers_end_at_blank_line_or_bare_newline() {
        let mut crlf = "Content-Length: 7\r\nX: y\r\n\r\nbody".as_bytes();
        assert_eq!(read_content_length(&mut crlf), Ok(Some(7)));
        let mut lf = "content-length: 3\n\nbody".as_bytes();
        assert_eq!(read_content_length(&mut lf), Ok(Some(3)));
    }

    #[test]
    fn headers_error_at_end_of_stream() {
        let mut truncated = "Content-Length: 7\r\n".as_bytes();
        assert!(read_content_length(&mut truncated).is_err());
    }

    #[test]
    fn https_without_a_pin_is_refused_before_connecting() {
        // Nothing listens on port 9, so reaching the network would fail
        // differently; the pin check comes first.
        let error = post_snapshot(&["https://127.0.0.1:9".to_string()], None, "t", b"x");
        assert!(error.is_err_and(|e| e.contains("fingerprint")));
    }

    #[test]
    fn every_unreachable_address_is_reported() {
        let error = post_snapshot(
            &[
                "http://127.0.0.1:9".to_string(),
                "http://127.0.0.1:9/again".to_string(),
            ],
            None,
            "token",
            b"x",
        );
        assert!(error.is_err_and(|e| e.matches("127.0.0.1:9").count() == 2));
    }

    #[test]
    fn invalid_addresses_are_reported_as_such() {
        let error = post_snapshot(&["sync-host:8788".to_string()], None, "t", b"x");
        assert!(error.is_err_and(|e| e.contains("must start with")));
    }

    /// Against a running `haqor-sync-server`. Run with
    /// `HAQOR_SYNC_E2E="<https url> <pin> <token>" cargo test -p hub -- --ignored`.
    #[test]
    #[ignore = "needs a running haqor-sync-server"]
    fn pinned_https_against_a_real_server() {
        let Ok(spec) = std::env::var("HAQOR_SYNC_E2E") else {
            return;
        };
        let parts: Vec<&str> = spec.split_whitespace().collect();
        let [url, pin, token] = parts[..] else {
            panic!("HAQOR_SYNC_E2E needs a url, pin and token");
        };
        let snapshot = b"not a database";
        // A dead first address falls through to the real server, which then
        // rejects the non-database body: proof the pinned TLS session and the
        // token both got through.
        let result = post_snapshot(
            &["https://127.0.0.1:9".to_string(), url.to_string()],
            Some(pin),
            token,
            snapshot,
        );
        assert!(
            result.as_ref().is_err_and(|e| e.contains("400")),
            "{result:?}"
        );
        let wrong_pin = post_snapshot(&[url.to_string()], Some(&"00".repeat(32)), token, snapshot);
        assert!(
            wrong_pin
                .as_ref()
                .is_err_and(|e| e.contains("does not match")),
            "{wrong_pin:?}"
        );
    }
}
