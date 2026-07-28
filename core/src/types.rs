use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub type PeerId = Uuid;
pub type SessionId = Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub peer_id: PeerId,
    pub hostname: String,
    pub os: String,
    pub version: String,
    pub public_ip: Option<String>,
    pub mac_address: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerEntry {
    pub peer_id: PeerId,
    pub hostname: String,
    pub ip: String,
    pub port: u16,
    pub os: String,
    pub last_seen: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PeerListConfig {
    pub peers: Vec<PeerEntry>,
    pub update_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionConfig {
    pub use_relay: bool,
    pub relay_addr: Option<String>,
    pub password: Option<String>,
    pub master_key: Option<String>,
    pub quality: VideoQuality,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VideoQuality {
    Low,
    Medium,
    High,
    Ultra,
}

impl Default for VideoQuality {
    fn default() -> Self {
        VideoQuality::Medium
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VideoFrame {
    pub session_id: SessionId,
    pub sequence: u64,
    pub timestamp: u64,
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub codec: VideoCodec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum VideoCodec {
    H264,
    H265,
    VP8,
    VP9,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MouseEvent {
    pub x: f64,
    pub y: f64,
    pub button: MouseButton,
    pub action: MouseAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MouseButton {
    Left,
    Right,
    Middle,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MouseAction {
    Down,
    Up,
    Move,
    Scroll,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyboardEvent {
    pub key: String,
    pub action: KeyAction,
    pub modifiers: Vec<KeyModifier>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum KeyAction {
    Down,
    Up,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum KeyModifier {
    Ctrl,
    Alt,
    Shift,
    Meta,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthMethod {
    Password(String),
    MasterKey(String),
    Certificate(String),
    AutoApprove,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateManifest {
    pub version: String,
    pub download_url: String,
    pub checksum: String,
    pub mandatory: bool,
    pub release_notes: String,
}
