use crate::AppState;
use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use azuldesk_core::protocol::{SignalingMessage, OnlinePeer};
use azuldesk_core::types::PeerId;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio_tungstenite::accept_async;

/// Normaliza el bloque CERTIFICATE de un PEM: extrae solo el body base64 y
/// quita todo whitespace (ignora la clave privada y diferencias de salto de línea).
/// None si no hay bloque válido.
fn cert_der(pem: &str) -> Option<String> {
    let start = "-----BEGIN CERTIFICATE-----";
    let end = "-----END CERTIFICATE-----";
    let a = pem.find(start)?;
    let b = pem.find(end)?;
    if b <= a {
        return None;
    }
    let body: String = pem[a + start.len()..b]
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect();
    if body.is_empty() {
        None
    } else {
        Some(body)
    }
}

pub async fn handle_connection(
    stream: tokio::net::TcpStream,
    addr: SocketAddr,
    state: Arc<AppState>,
) -> Result<()> {
    let ws = accept_async(stream).await?;
    let (mut ws_tx, mut ws_rx) = ws.split();
    let mut current_id: Option<PeerId> = None;
    let mut current_log_id: Option<i64> = None;
    let mut brx = state.broadcast.subscribe();
    let (peer_tx, mut peer_rx) = tokio::sync::mpsc::unbounded_channel::<String>();

    loop {
        tokio::select! {
            msg = ws_rx.next() => {
                let msg = match msg {
                    Some(Ok(m)) => m,
                    _ => break,
                };
                if !msg.is_text() { continue; }

                let text = msg.to_text().unwrap_or("").to_string();
                let signal: SignalingMessage = match serde_json::from_str(&text) {
                    Ok(m) => m,
                    Err(_) => continue,
                };

                match signal {
                    SignalingMessage::Register { device, listen_port, certificate } => {
                        let sn = device.mac_address.as_deref().unwrap_or("").to_string();
                        if sn.is_empty() {
                            let err = SignalingMessage::Error {
                                code: 400,
                                message: "Serial number required (send as mac_address)".into(),
                            };
                            if let Ok(json) = serde_json::to_string(&err) {
                                let _ = ws_tx.send(json.into()).await;
                            }
                            continue;
                        }

                        // El peer_id se deriva SIEMPRE del serial del equipo (hash SHA-256).
                        // Así el ID es determinista, nunca se repite y queda atado al serial.
                        use sha2::Digest;
                        let mut hasher = sha2::Sha256::new();
                        hasher.update(sn.as_bytes());
                        let hash = hex::encode(hasher.finalize());
                        let short_id = format!("{}-{}-{}", &hash[..4], &hash[4..8], &hash[8..12]).to_uppercase();
                        let peer_id = PeerId::parse_str(&hash[..32]).unwrap_or_else(|_| uuid::Uuid::new_v4());

                        let device_record = state.db.get_device_by_sn(&sn).await.ok().flatten();

                        if let Some(ref rec) = device_record {
                            if !rec.active {
                                let err = SignalingMessage::Error {
                                    code: 403,
                                    message: "Tu certificado de ingreso ha sido expirado o desactivado".into(),
                                };
                                if let Ok(json) = serde_json::to_string(&err) {
                                    let _ = ws_tx.send(json.into()).await;
                                }
                                continue;
                            }
                            // Verificar certificado
                            let cert_status = state.db.get_certificate_status(&sn).await.ok().flatten();
                            if let Some(ref cert) = cert_status {
                                if cert.status != "active" {
                                    let err = SignalingMessage::Error {
                                        code: 403,
                                        message: "Tu certificado de ingreso ha sido expirado o desactivado".into(),
                                    };
                                    if let Ok(json) = serde_json::to_string(&err) {
                                        let _ = ws_tx.send(json.into()).await;
                                    }
                                    continue;
                                }
                                // Si el cliente presenta certificado, verificar que coincida con un
                                // certificado ACTIVO del serial en la DB. Si coincide (DER), es
                                // prueba suficiente de identidad: el propio servidor lo emitió.
                                // El binding serial/peer_id se usa solo como validación secundaria
                                // (acepta certs emitidos por versiones anteriores sin esos campos).
                                if let Some(ref client_cert) = certificate {
                                    let active_certs = state.db.get_active_certificates(&sn).await.unwrap_or_default();
                                    let client_der = cert_der(client_cert);
                                    let mut matched = false;
                                    if let Some(cd) = client_der {
                                        for stored in &active_certs {
                                            if let Some(sd) = cert_der(stored) {
                                                if sd == cd {
                                                    matched = true;
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                    if matched {
                                        tracing::info!("certificate matched for {} ({} certs active)", sn, active_certs.len());
                                    } else {
                                        // No coincide con la DB: solo aceptar si el binding es válido
                                        // (cert emitido por nuestra CA con serial/peer_id correctos).
                                        if let Err(e) = state.ca.verify_device_binding(client_cert, &sn, &peer_id.to_string()) {
                                            tracing::warn!("cert binding failed for {}: {}", sn, e);
                                            let err = SignalingMessage::Error {
                                                code: 403,
                                                message: "Certificado no válido para este equipo".into(),
                                            };
                                            if let Ok(json) = serde_json::to_string(&err) {
                                                let _ = ws_tx.send(json.into()).await;
                                            }
                                            continue;
                                        }
                                    }
                                }
                            }
                            if let Err(e) = state.db.log_connection_audit(
                                rec.owner_user_id, &sn, &addr.ip().to_string(), "", &sn,
                                &addr.ip().to_string(), "", &sn,
                            ).await {
                                tracing::warn!("audit log failed: {}", e);
                            }
                            // Mantener el hostname del equipo actualizado en la DB
                            // (register_device hace UPDATE si el serial ya existe).
                            let _ = state.db.register_device(
                                &sn, rec.owner_user_id.unwrap_or(1), 1,
                                &device.hostname, &sn,
                            ).await;
                        } else {
                            // Primera vez: crear dispositivo y emitir certificado
                            // vinculado a serial + peer_id derivado.
                            match state.ca.issue_device_cert(&peer_id.to_string(), &sn) {
                                Ok(cert_pem) => {
                                    state.db.register_device(&sn, 1, 1, &device.hostname, &sn).await.ok();
                                    state.db.issue_certificate(&sn, &cert_pem, "auto", "auto", None).await.ok();

                                    let cert_msg = SignalingMessage::Certificate {
                                        cert_pem,
                                        serial_number: sn.clone(),
                                    };
                                    if let Ok(json) = serde_json::to_string(&cert_msg) {
                                        let _ = ws_tx.send(json.into()).await;
                                    }
                                }
                                Err(e) => {
                                    tracing::error!("failed to issue certificate: {}", e);
                                }
                            }
                        }

                        let online = OnlinePeer {
                            peer_id,
                            hostname: device.hostname,
                            os: device.os,
                            version: device.version,
                            public_ip: addr.ip().to_string(),
                            listen_port,
                            last_seen: chrono_now(),
                        };
                        state.peers.write().await.insert(peer_id, online);
                        state.peer_channels.write().await.insert(peer_id, peer_tx.clone());
                        current_id = Some(peer_id);
                        tracing::info!("Registered: {} ({})", short_id, addr.ip());

                        let resp = SignalingMessage::Registered { peer_id };
                        if let Ok(json) = serde_json::to_string(&resp) {
                            let _ = ws_tx.send(json.into()).await;
                        }
                        broadcast_peers(&state).await;
                    }

                    SignalingMessage::ConnectRequest { target_id: _target_id, auth } => {
                        if let Some(from_id) = current_id {
                            if let Some(from) = state.peers.read().await.get(&from_id).cloned() {
                                if let azuldesk_core::types::AuthMethod::Certificate(ref cert) = auth {
                                    if !state.ca.verify_certificate(cert).unwrap_or(false) {
                                        let err = SignalingMessage::Error {
                                            code: 403,
                                            message: "Invalid certificate".into(),
                                        };
                                        if let Ok(json) = serde_json::to_string(&err) {
                                            let _ = ws_tx.send(json.into()).await;
                                        }
                                        continue;
                                    }
                                    // El cert presentado debe llevar el peer_id del que solicita.
                                    if state.ca.verify_device_binding(cert, "", &from_id.to_string()).is_err() {
                                        let err = SignalingMessage::Error {
                                            code: 403,
                                            message: "Invalid certificate for peer".into(),
                                        };
                                        if let Ok(json) = serde_json::to_string(&err) {
                                            let _ = ws_tx.send(json.into()).await;
                                        }
                                        continue;
                                    }
                                }
                                let session_id = uuid::Uuid::new_v4();
                                let req = SignalingMessage::ConnectRequested {
                                    from: azuldesk_core::types::DeviceInfo {
                                        peer_id: from.peer_id,
                                        hostname: from.hostname,
                                        os: from.os,
                                        version: from.version,
                                        public_ip: Some(from.public_ip),
                                        mac_address: None,
                                    },
                                    session_id,
                                };
                                // Enviar SOLO al objetivo (no broadcast)
                                if let Some(tx) = state.peer_channels.read().await.get(&_target_id) {
                                    if let Ok(json) = serde_json::to_string(&req) {
                                        let _ = tx.send(json);
                                    }
                                }
                                // Recordar el solicitante de esta sesión para rutear la respuesta
                                state.sessions.write().await.insert(session_id, from_id);
                            }
                        }
                    }

                    SignalingMessage::ConnectResponse { accepted, session_id, target_ip, target_port, reason } => {
                        let resp = SignalingMessage::ConnectResponse {
                            accepted, session_id, target_ip, target_port, reason,
                        };
                        // Enviar SOLO al solicitante de la sesión (no broadcast)
                        if let Ok(json) = serde_json::to_string(&resp) {
                            if let Some(requester) = state.sessions.read().await.get(&session_id).cloned() {
                                if let Some(tx) = state.peer_channels.read().await.get(&requester) {
                                    let _ = tx.send(json);
                                }
                            }
                        }
                    }

                    SignalingMessage::Heartbeat => {
                        let _ = ws_tx.send(serde_json::to_string(&SignalingMessage::Heartbeat)?.into()).await;
                    }

                    _ => {}
                }
            }

            broadcast = brx.recv() => {
                match broadcast {
                    Ok(msg) => { if ws_tx.send(msg.into()).await.is_err() { break; } }
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(_) => break,
                }
            }

            peer_msg = peer_rx.recv() => {
                match peer_msg {
                    Some(msg) => { if ws_tx.send(msg.into()).await.is_err() { break; } }
                    None => break,
                }
            }
        }
    }

    if let Some(id) = current_id {
        state.peers.write().await.remove(&id);
        state.peer_channels.write().await.remove(&id);
        {
            let mut sessions = state.sessions.write().await;
            sessions.retain(|_, requester| *requester != id);
        }
        tracing::info!("Peer {} disconnected from {}", id, addr);
        broadcast_peers(&state).await;
    }
    if let Some(log_id) = current_log_id {
        let _ = state.db.close_audit_log(log_id).await;
    }

    Ok(())
}

async fn broadcast_peers(state: &AppState) {
    let map = state.peers.read().await;
    let list: Vec<OnlinePeer> = map.values().cloned().collect();
    if let Ok(json) = serde_json::to_string(&SignalingMessage::PeerList { peers: list }) {
        let _ = state.broadcast.send(json);
    }
}

fn chrono_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}
