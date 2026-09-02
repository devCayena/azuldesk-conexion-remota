use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;
use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::Path;
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;

/// Cuanto tiempo sin recibir NADA del cliente (ni frames, ni input, ni pong)
/// antes de considerar la conexion muerta y cerrar la sesion para ambos lados.
/// Cubre el caso de una caida de red donde nunca llega un Close frame.
const IDLE_TIMEOUT: Duration = Duration::from_secs(20);
/// Cada cuanto se manda un Ping para mantener viva la conexion y detectar
/// cortes a mitad de camino (NAT timeouts, wifi inestable, etc).
const PING_INTERVAL: Duration = Duration::from_secs(8);

struct SessionRelay {
    peer_a: Option<mpsc::UnboundedSender<Message>>,
    peer_b: Option<mpsc::UnboundedSender<Message>>,
}

fn relays() -> &'static Mutex<HashMap<String, SessionRelay>> {
    static INSTANCE: OnceLock<Mutex<HashMap<String, SessionRelay>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub async fn handle_session(
    ws: WebSocketUpgrade,
    Path(session_id): Path<String>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| session_ws(socket, session_id))
}

async fn session_ws(mut ws: WebSocket, session_id: String) {
    let relays = relays();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    let (my_id, room_full) = {
        let mut map = relays.lock().unwrap();
        let entry = map.entry(session_id.clone()).or_insert(SessionRelay {
            peer_a: None,
            peer_b: None,
        });
        if entry.peer_a.is_none() {
            entry.peer_a = Some(tx);
            (0u8, false)
        } else if entry.peer_b.is_none() {
            entry.peer_b = Some(tx);
            (1u8, false)
        } else {
            (0u8, true)
        }
    };

    if room_full {
        tracing::warn!("Session {} full, rejecting", session_id);
        let _ = ws.close().await;
        return;
    }

    tracing::info!("Session peer {} joined session {}", my_id, session_id);

    let mut ping_ticker = tokio::time::interval(PING_INTERVAL);
    ping_ticker.tick().await; // el primer tick es inmediato, lo descartamos
    let mut idle = Box::pin(tokio::time::sleep(IDLE_TIMEOUT));
    // Placeholder: siempre se sobreescribe antes del log final, pero el
    // compilador no puede probarlo a traves de tokio::select!.
    #[allow(unused_assignments)]
    let mut reason = "closed";

    loop {
        tokio::select! {
            msg = ws.next() => {
                match msg {
                    Some(Ok(msg @ Message::Binary(_))) | Some(Ok(msg @ Message::Text(_))) => {
                        idle.as_mut().reset(tokio::time::Instant::now() + IDLE_TIMEOUT);
                        let target = {
                            let map = relays.lock().unwrap();
                            map.get(&session_id).and_then(|entry| {
                                if my_id == 0 { entry.peer_b.clone() } else { entry.peer_a.clone() }
                            })
                        };
                        if let Some(tx) = target {
                            let _ = tx.send(msg);
                        }
                    }
                    Some(Ok(Message::Ping(_))) => {
                        idle.as_mut().reset(tokio::time::Instant::now() + IDLE_TIMEOUT);
                        let _ = ws.send(Message::Pong(Bytes::new())).await;
                    }
                    Some(Ok(Message::Pong(_))) => {
                        idle.as_mut().reset(tokio::time::Instant::now() + IDLE_TIMEOUT);
                    }
                    Some(Ok(Message::Close(_))) => { reason = "closed by peer"; break; }
                    None => { reason = "connection dropped"; break; }
                    Some(Err(e)) => { tracing::warn!("session {} read error: {}", session_id, e); reason = "read error"; break; }
                }
            }
            data = rx.recv() => {
                match data {
                    Some(Message::Close(frame)) => {
                        // El otro peer termino la operacion: propagamos el cierre y salimos.
                        let _ = ws.send(Message::Close(frame)).await;
                        reason = "peer ended the session";
                        break;
                    }
                    Some(data) => {
                        if ws.send(data).await.is_err() { reason = "send failed"; break; }
                    }
                    None => { reason = "peer channel closed"; break; }
                }
            }
            _ = ping_ticker.tick() => {
                if ws.send(Message::Ping(Bytes::new())).await.is_err() {
                    reason = "ping failed";
                    break;
                }
            }
            _ = &mut idle => {
                tracing::warn!("Session {} peer {} idle timeout, closing", session_id, my_id);
                reason = "idle timeout";
                break;
            }
        }
    }

    // Notificar al otro lado (si sigue conectado) para que la operacion
    // termine en ambos equipos, no solo en el que se desconecto.
    let mut map = relays.lock().unwrap();
    if let Some(entry) = map.get_mut(&session_id) {
        let other = if my_id == 0 { entry.peer_b.take() } else { entry.peer_a.take() };
        if let Some(other_tx) = other {
            let _ = other_tx.send(Message::Close(None));
        }
        if my_id == 0 {
            entry.peer_a = None;
        } else {
            entry.peer_b = None;
        }
        if entry.peer_a.is_none() && entry.peer_b.is_none() {
            map.remove(&session_id);
        }
    }
    drop(map);
    tracing::info!("Session peer {} left session {} ({})", my_id, session_id, reason);
}
