use std::collections::HashMap;
use std::sync::Arc;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, State};
use axum::response::IntoResponse;
use futures_util::StreamExt;
use tokio::sync::Mutex;
use crate::AppState;

type AudioSessions = Arc<Mutex<HashMap<String, AudioSession>>>;

struct AudioSession {
    peer_a: Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>,
    peer_b: Option<tokio::sync::mpsc::UnboundedSender<Vec<u8>>>,
}

fn sessions() -> AudioSessions {
    Arc::new(Mutex::new(HashMap::new()))
}

pub async fn handle_audio(
    ws: WebSocketUpgrade,
    Path(session_id): Path<String>,
    State(_state): State<Arc<AppState>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| audio_session(socket, session_id))
}

async fn audio_session(mut ws: WebSocket, session_id: String) {
    let sessions = sessions();
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    let my_id: u8;

    {
        let mut map = sessions.lock().await;
        let entry = map.entry(session_id.clone()).or_insert(AudioSession {
            peer_a: None,
            peer_b: None,
        });
        if entry.peer_a.is_none() {
            entry.peer_a = Some(tx);
            my_id = 0;
        } else if entry.peer_b.is_none() {
            entry.peer_b = Some(tx);
            my_id = 1;
        } else {
            tracing::warn!("Audio session {} full, rejecting", session_id);
            return;
        }
    }

    tracing::info!("Audio peer {} joined session {}", my_id, session_id);

    loop {
        tokio::select! {
            msg = ws.next() => {
                match msg {
                    Some(Ok(Message::Binary(data))) => {
                        let map = sessions.lock().await;
                        if let Some(entry) = map.get(&session_id) {
                            let target = if my_id == 0 { &entry.peer_b } else { &entry.peer_a };
                            if let Some(tx) = target {
                                let _ = tx.send(data.to_vec());
                            }
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

    let mut map = sessions.lock().await;
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
