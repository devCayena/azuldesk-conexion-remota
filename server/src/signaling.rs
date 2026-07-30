use crate::AppState;
use anyhow::Result;
use futures_util::{SinkExt, StreamExt};
use azuldesk_core::protocol::{SignalingMessage, OnlinePeer};
use azuldesk_core::types::PeerId;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio_tungstenite::accept_async;

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
                    SignalingMessage::Register { device, listen_port } => {
                        let peer_id = device.peer_id;

                        // Find device by serial number
                        let sn = device.mac_address.clone().unwrap_or_else(|| peer_id.to_string());
                        let device_record = state.db.get_device_by_sn(&sn).await.ok().flatten();

                        if let Some(ref rec) = device_record {
                            if !rec.active { continue; }
                            // Log audit connection
                            let log_id = state.db.log_connection_audit(
                                rec.owner_user_id, &sn, &addr.ip().to_string(), "", &sn,
                                &addr.ip().to_string(), "", &peer_id.to_string(),
                            ).await?;
                            current_log_id = Some(log_id);
                        }

                        // Add to online peers
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
                        current_id = Some(peer_id);
                        tracing::info!("Registered: {} from {}", peer_id, addr.ip());

                        let resp = SignalingMessage::Registered { peer_id };
                        if let Ok(json) = serde_json::to_string(&resp) {
                            let _ = ws_tx.send(json.into()).await;
                        }
                        broadcast_peers(&state).await;
                    }

                    SignalingMessage::ConnectRequest { target_id: _target_id, auth } => {
                        if let Some(from_id) = current_id {
                            if let Some(from) = state.peers.read().await.get(&from_id).cloned() {
                                // Verify certificate if present
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
                                if let Ok(json) = serde_json::to_string(&req) {
                                    let _ = state.broadcast.send(json);
                                }
                            }
                        }
                    }

                    SignalingMessage::ConnectResponse { accepted, session_id, target_ip, target_port, reason } => {
                        let resp = SignalingMessage::ConnectResponse {
                            accepted, session_id, target_ip, target_port, reason,
                        };
                        if let Ok(json) = serde_json::to_string(&resp) {
                            let _ = state.broadcast.send(json);
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
                    Err(_) => break,
                }
            }
        }
    }

    // Cleanup
    if let Some(id) = current_id {
        state.peers.write().await.remove(&id);
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
