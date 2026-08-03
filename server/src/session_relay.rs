use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::Path;
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;

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

    loop {
        tokio::select! {
            msg = ws.next() => {
                match msg {
                    Some(Ok(msg @ Message::Binary(_))) | Some(Ok(msg @ Message::Text(_))) => {
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
                        let _ = ws.send(Message::Pong(Bytes::new())).await;
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    _ => {}
                }
            }
            data = rx.recv() => {
                if let Some(data) = data {
                    if ws.send(data).await.is_err() {
                        break;
                    }
                }
            }
        }
    }

    let mut map = relays.lock().unwrap();
    if let Some(entry) = map.get_mut(&session_id) {
        if my_id == 0 {
            entry.peer_a = None;
        } else {
            entry.peer_b = None;
        }
        if entry.peer_a.is_none() && entry.peer_b.is_none() {
            map.remove(&session_id);
        }
    }
    tracing::info!("Session peer {} left session {}", my_id, session_id);
}
