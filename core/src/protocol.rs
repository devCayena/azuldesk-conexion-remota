use serde::{Deserialize, Serialize};
use crate::types::*;

// Messages exchanged with the signaling server (WebSocket JSON)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SignalingMessage {
    // Registration
    Register {
        device: DeviceInfo,
        listen_port: u16,
        certificate: Option<String>,
    },
    Registered {
        peer_id: PeerId,
    },

    // Peer list (broadcast to all connected peers)
    PeerList {
        peers: Vec<OnlinePeer>,
    },

    // Connection request (A -> Server -> B)
    ConnectRequest {
        target_id: PeerId,
        auth: AuthMethod,
    },
    ConnectRequested {
        from: DeviceInfo,
        session_id: SessionId,
    },

    // Connection response (B -> Server -> A)
    ConnectResponse {
        accepted: bool,
        session_id: SessionId,
        target_ip: Option<String>,
        target_port: Option<u16>,
        reason: Option<String>,
    },

    // Device certificate (sent to client on first registration)
    Certificate {
        cert_pem: String,
        serial_number: String,
    },

    // Control
    Heartbeat,
    Disconnect {
        reason: String,
    },
    Error {
        code: u32,
        message: String,
    },
}

// A peer currently online (visible on dashboard)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OnlinePeer {
    pub peer_id: PeerId,
    pub hostname: String,
    pub os: String,
    pub version: String,
    pub public_ip: String,
    pub listen_port: u16,
    pub last_seen: String,
}

// Messages exchanged directly between peers (TCP bincode)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DirectMessage {
    Hello {
        device: DeviceInfo,
        auth: AuthMethod,
        session_id: SessionId,
    },
    HelloAck {
        accepted: bool,
        reason: Option<String>,
    },
    VideoFrame(VideoFrame),
    MouseEvent(MouseEvent),
    KeyboardEvent(KeyboardEvent),
    Clipboard {
        text: String,
    },
    FileTransfer {
        name: String,
        size: u64,
        data: Vec<u8>,
    },
    KeepAlive,
    Disconnect {
        reason: String,
    },
}
