use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::Path;
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;

struct AudioSession {
    peer_a: Option<mpsc::UnboundedSender<Vec<u8>>>,
    peer_b: Option<mpsc::UnboundedSender<Vec<u8>>>,
}

fn sessions() -> &'static Mutex<HashMap<String, AudioSession>> {
    static INSTANCE: OnceLock<Mutex<HashMap<String, AudioSession>>> = OnceLock::new();
    INSTANCE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub async fn handle_audio(
    ws: WebSocketUpgrade,
    Path(session_id): Path<String>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| audio_session(socket, session_id))
}

async fn audio_session(mut ws: WebSocket, session_id: String) {
    let sessions = sessions();
    let (tx, mut rx) = mpsc::unbounded_channel::<Vec<u8>>();

    let (my_id, room_full) = {
        let mut map = sessions.lock().unwrap();
        let entry = map.entry(session_id.clone()).or_insert(AudioSession {
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
        tracing::warn!("Audio session {} full, rejecting", session_id);
        let _ = ws.close().await;
        return;
    }

    tracing::info!("Audio peer {} joined session {}", my_id, session_id);

    loop {
        tokio::select! {
            msg = ws.next() => {
                match msg {
                    Some(Ok(Message::Binary(data))) => {
                        let target = {
                            let map = sessions.lock().unwrap();
                            map.get(&session_id).and_then(|entry| {
                                if my_id == 0 { entry.peer_b.clone() } else { entry.peer_a.clone() }
                            })
                        };
                        if let Some(tx) = target {
                            let _ = tx.send(data.to_vec());
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    _ => {}
                }
            }
            data = rx.recv() => {
                if let Some(data) = data {
                    if ws.send(Message::Binary(data.into())).await.is_err() {
                        break;
                    }
                }
            }
        }
    }

    let mut map = sessions.lock().unwrap();
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
    tracing::info!("Audio peer {} left session {}", my_id, session_id);
}
