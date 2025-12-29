use anyhow::Result;
use bytes::Bytes;
use quinn::{
    crypto::rustls::QuicServerConfig, Endpoint, RecvStream, SendStream, ServerConfig,
};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::net::SocketAddr;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

use crate::infrastructure::serialization::{Packet, ProtocolAdapter, SerializationFormat};

/// Start QUIC server for modern clients.
pub async fn start_quic_server(addr: SocketAddr) -> Result<()> {
    let (server_config, _cert) = configure_server()?;

    let endpoint = Endpoint::server(server_config, addr)?;
    info!("QUIC server listening on {}", addr);

    while let Some(incoming) = endpoint.accept().await {
        tokio::spawn(async move {
            match incoming.await {
                Ok(connection) => {
                    let remote = connection.remote_address();
                    info!("New QUIC connection from {}", remote);

                    if let Err(e) = handle_connection(connection).await {
                        error!("QUIC connection error from {}: {}", remote, e);
                    }
                }
                Err(e) => {
                    error!("QUIC connection failed: {}", e);
                }
            }
        });
    }

    Ok(())
}

/// Configure QUIC server with self-signed certificate.
fn configure_server() -> Result<(ServerConfig, Vec<CertificateDer<'static>>)> {
    // Generate self-signed certificate
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])?;
    let cert_der = CertificateDer::from(cert.cert);
    let key_der = PrivatePkcs8KeyDer::from(cert.key_pair.serialize_der());

    let mut server_config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![cert_der.clone()], PrivateKeyDer::Pkcs8(key_der))?;

    server_config.alpn_protocols = vec![b"openrsc".to_vec()];

    let quic_config = QuicServerConfig::try_from(server_config)?;
    let config = ServerConfig::with_crypto(Arc::new(quic_config));

    Ok((config, vec![cert_der]))
}

/// Handle a QUIC connection.
async fn handle_connection(connection: quinn::Connection) -> Result<()> {
    let remote = connection.remote_address();

    loop {
        match connection.accept_bi().await {
            Ok((send, recv)) => {
                tokio::spawn(handle_stream(send, recv, remote));
            }
            Err(quinn::ConnectionError::ApplicationClosed(_)) => {
                debug!("Connection closed by {}", remote);
                break;
            }
            Err(e) => {
                error!("Stream error from {}: {}", remote, e);
                break;
            }
        }
    }

    Ok(())
}

/// Handle a bidirectional QUIC stream.
async fn handle_stream(
    mut send: SendStream,
    mut recv: RecvStream,
    remote: SocketAddr,
) -> Result<()> {
    // Read packet data
    let mut buffer = vec![0u8; 65536];
    let mut total_read = 0;

    // Read until we have a complete packet
    while total_read < 6 {
        match recv.read(&mut buffer[total_read..]).await? {
            Some(n) => total_read += n,
            None => {
                debug!("Stream closed by {}", remote);
                return Ok(());
            }
        }
    }

    // Detect protocol
    let format = ProtocolAdapter::detect_protocol(&buffer[..total_read]);
    debug!("Client {} using {:?} protocol", remote, format);

    // Process packet
    match ProtocolAdapter::decode(&buffer[..total_read], format) {
        Ok(packet) => {
            debug!("Received packet opcode={} size={} from {}",
                   packet.opcode, packet.payload.len(), remote);

            // Process and respond
            let response = process_packet(&packet).await?;
            let response_bytes = ProtocolAdapter::encode(&response, format)?;
            send.write_all(&response_bytes).await?;
        }
        Err(e) => {
            warn!("Failed to decode packet from {}: {}", remote, e);
        }
    }

    send.finish().ok();
    Ok(())
}

/// Process a game packet and generate response.
async fn process_packet(packet: &Packet) -> Result<Packet> {
    // Placeholder - actual game logic would go here
    match packet.opcode {
        0 => {
            // Ping/pong
            Ok(Packet::new(0, Bytes::from_static(b"pong")))
        }
        _ => {
            // Echo back
            Ok(Packet::new(packet.opcode, packet.payload.clone()))
        }
    }
}

/// QUIC client for connecting to other servers.
pub struct QuicClient {
    endpoint: Endpoint,
}

impl QuicClient {
    /// Create a new QUIC client.
    pub fn new() -> Result<Self> {
        let mut endpoint = Endpoint::client("0.0.0.0:0".parse()?)?;

        // Configure client
        let crypto = rustls::ClientConfig::builder()
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(SkipServerVerification))
            .with_no_client_auth();

        let mut client_config = quinn::ClientConfig::new(Arc::new(
            quinn::crypto::rustls::QuicClientConfig::try_from(crypto)?
        ));

        let mut transport = quinn::TransportConfig::default();
        transport.max_idle_timeout(Some(std::time::Duration::from_secs(30).try_into()?));
        client_config.transport_config(Arc::new(transport));

        endpoint.set_default_client_config(client_config);

        Ok(Self { endpoint })
    }

    /// Connect to a QUIC server.
    pub async fn connect(&self, addr: SocketAddr, server_name: &str) -> Result<quinn::Connection> {
        let connection = self.endpoint.connect(addr, server_name)?.await?;
        info!("Connected to QUIC server at {}", addr);
        Ok(connection)
    }

    /// Send a packet and receive response.
    pub async fn send_packet(&self, connection: &quinn::Connection, packet: &Packet) -> Result<Packet> {
        let (mut send, mut recv) = connection.open_bi().await?;

        // Send packet
        let data = packet.encode_msgpack()?;
        send.write_all(&data).await?;
        send.finish().ok();

        // Receive response
        let response_data = recv.read_to_end(65536).await?;
        Packet::decode_msgpack(&response_data)
    }
}

/// Skip server certificate verification (for development only).
#[derive(Debug)]
struct SkipServerVerification;

impl rustls::client::danger::ServerCertVerifier for SkipServerVerification {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        vec![
            rustls::SignatureScheme::RSA_PKCS1_SHA256,
            rustls::SignatureScheme::ECDSA_NISTP256_SHA256,
            rustls::SignatureScheme::RSA_PKCS1_SHA384,
            rustls::SignatureScheme::ECDSA_NISTP384_SHA384,
            rustls::SignatureScheme::RSA_PKCS1_SHA512,
            rustls::SignatureScheme::ECDSA_NISTP521_SHA512,
            rustls::SignatureScheme::RSA_PSS_SHA256,
            rustls::SignatureScheme::RSA_PSS_SHA384,
            rustls::SignatureScheme::RSA_PSS_SHA512,
            rustls::SignatureScheme::ED25519,
        ]
    }
}
