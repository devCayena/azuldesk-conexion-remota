use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tower_http::cors::{Any, CorsLayer};

use crate::AppState;
use crate::db::{AuditRecord, MasterKeyRecord};

// ─── Auth helper ───────────────────────────────────────

fn extract_user_id(headers: &HeaderMap) -> Option<i64> {
    headers.get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer tok_"))
        .and_then(|v| v.parse::<i64>().ok())
}

fn simple_hash(input: &str) -> String {
    use sha2::Digest;
    let mut h = sha2::Sha256::new();
    h.update(input.as_bytes());
    hex::encode(h.finalize())
}

async fn require_admin(state: &AppState, headers: &HeaderMap) -> Result<(i64, String), StatusCode> {
    let uid = extract_user_id(headers).ok_or(StatusCode::UNAUTHORIZED)?;
    let user = state.db.get_user_by_id(uid).await.map_err(|_| StatusCode::UNAUTHORIZED)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    if !user.is_admin {
        return Err(StatusCode::FORBIDDEN);
    }
    Ok((uid, user.name))
}

// ─── Request/Response ──────────────────────────────────

#[derive(Deserialize)]
pub struct LoginRequest { pub email: String, pub password: String }

#[derive(Serialize)]
pub struct LoginResponse { pub user_id: i64, pub name: String, pub is_admin: bool }

#[derive(Deserialize)]
pub struct RegisterDeviceRequest {
    pub serial_number: String, pub device_name: String, pub mac_address: String,
    pub master_key: String, pub installer_name: String, pub installer_identification: String,
}

#[derive(Serialize)]
pub struct MasterKeyResponse {
    pub id: i64, pub key: String, pub valid_from: String, pub valid_until: String,
    pub generated_by: String,
}

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/api/auth/login", post(login))
        .route("/api/devices", get(list_devices))
        .route("/api/devices", post(register_device))
        .route("/api/devices/{sn}", get(get_device))
        .route("/api/devices/{sn}/certificate", post(issue_certificate))
        .route("/api/devices/{sn}/block", put(block_device))
        .route("/api/devices/{sn}/unblock", put(unblock_device))
        .route("/api/master-keys/current", get(get_current_key))
        .route("/api/master-keys/rotate", post(rotate_key))
        .route("/api/master-keys/validate", post(validate_key))
        .route("/api/audit", get(get_audit))
        .route("/api/audit/user/{user_id}", get(get_user_audit))
        .layer(CorsLayer::new().allow_origin(Any))
        .with_state(state)
}

// ─── Auth ──────────────────────────────────────────────

async fn login(State(state): State<Arc<AppState>>, Json(req): Json<LoginRequest>) -> Result<Json<LoginResponse>, StatusCode> {
    let user = state.db.get_user_by_email(&req.email).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    if !bcrypt::verify(&req.password, &user.password_hash).unwrap_or(false) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(Json(LoginResponse { user_id: user.id, name: user.name, is_admin: user.is_admin }))
}

// ─── Devices ──────────────────────────────────────────

async fn list_devices(State(state): State<Arc<AppState>>) -> Json<Vec<serde_json::Value>> {
    let devices = state.db.list_all_devices().await.unwrap_or_default();
    Json(devices.into_iter().map(|d| serde_json::json!({
        "serial_number": d.serial_number, "device_name": d.device_name,
        "active": d.active, "last_seen": d.last_seen,
    })).collect())
}

async fn register_device(
    State(state): State<Arc<AppState>>,
    Json(req): Json<RegisterDeviceRequest>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let key_hash = simple_hash(&req.master_key);
    let mk_id = state.db.validate_master_key(&key_hash).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::FORBIDDEN)?;

    state.db.register_device(&req.serial_number, 1, 1, &req.device_name, &req.mac_address)
        .await.map_err(|_| StatusCode::CONFLICT)?;

    let cert_pem = state.ca.issue_device_cert(&req.serial_number, &req.mac_address)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    state.db.issue_certificate(&req.serial_number, &cert_pem, &req.installer_name, &req.installer_identification, Some(mk_id))
        .await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({"status": "ok", "serial_number": req.serial_number})))
}

async fn get_device(State(state): State<Arc<AppState>>, Path(sn): Path<String>) -> Result<Json<serde_json::Value>, StatusCode> {
    let d = state.db.get_device_by_sn(&sn).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(serde_json::json!({"serial_number": d.serial_number, "device_name": d.device_name, "active": d.active})))
}

async fn issue_certificate(State(state): State<Arc<AppState>>, Json(req): Json<serde_json::Value>) -> Result<Json<serde_json::Value>, StatusCode> {
    let key = req["master_key"].as_str().unwrap_or("");
    let sn = req["serial_number"].as_str().unwrap_or("");
    let installer = req["installer_name"].as_str().unwrap_or("");
    let installer_id = req["installer_identification"].as_str().unwrap_or("");

    let key_hash = simple_hash(key);
    let mk_id = state.db.validate_master_key(&key_hash).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::FORBIDDEN)?;

    let device = state.db.get_device_by_sn(sn).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    let cert_pem = state.ca.issue_device_cert(sn, &device.mac_address)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    state.db.issue_certificate(sn, &cert_pem, installer, installer_id, Some(mk_id))
        .await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(serde_json::json!({"status": "issued"})))
}

async fn block_device(State(state): State<Arc<AppState>>, Path(sn): Path<String>) -> StatusCode {
    state.db.block_certificate(&sn, 1).await.ok();
    StatusCode::OK
}

async fn unblock_device(State(state): State<Arc<AppState>>, Path(sn): Path<String>) -> StatusCode {
    state.db.unblock_certificate(&sn).await.ok();
    StatusCode::OK
}

// ─── Master Keys (solo admin) ─────────────────────────

async fn get_current_key(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<MasterKeyResponse>, StatusCode> {
    let (uid, name) = require_admin(&state, &headers).await?;

    // If no valid key exists, auto-generate one
    let key = match state.db.get_current_master_key().await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)? {
        Some(k) => k,
        None => {
            let plain = generate_random_key();
            let hash = simple_hash(&plain);
            let now = chrono::Utc::now();
            let until = now + chrono::Duration::hours(1);
            let id = state.db.create_master_key_direct(&plain, &hash, &now, &until, Some(uid), &name)
                .await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            MasterKeyRecord { id, key_hash: hash, key_plaintext: plain, valid_from: now, valid_until: until, created_by: Some(uid), generated_by: Some(name.clone()) }
        }
    };

    Ok(Json(MasterKeyResponse {
        id: key.id,
        key: key.key_plaintext,
        valid_from: key.valid_from.to_rfc3339(),
        valid_until: key.valid_until.to_rfc3339(),
        generated_by: key.generated_by.unwrap_or_else(|| "auto".into()),
    }))
}

async fn rotate_key(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> Result<Json<MasterKeyResponse>, StatusCode> {
    let (uid, name) = require_admin(&state, &headers).await?;

    let plain = generate_random_key();
    let hash = simple_hash(&plain);
    let now = chrono::Utc::now();
    let until = now + chrono::Duration::hours(1);

    let id = state.db.create_master_key_direct(&plain, &hash, &now, &until, Some(uid), &name)
        .await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(MasterKeyResponse {
        id, key: plain,
        valid_from: now.to_rfc3339(),
        valid_until: until.to_rfc3339(),
        generated_by: name,
    }))
}

async fn validate_key(State(state): State<Arc<AppState>>, Json(req): Json<serde_json::Value>) -> Json<serde_json::Value> {
    let key = req["key"].as_str().unwrap_or("");
    let hash = simple_hash(key);
    match state.db.validate_master_key(&hash).await {
        Ok(Some(id)) => Json(serde_json::json!({"valid": true, "master_key_id": id})),
        _ => Json(serde_json::json!({"valid": false})),
    }
}

// ─── Audit ────────────────────────────────────────────

async fn get_audit(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    let (_, _) = require_admin(&state, &headers).await?;
    let logs = state.db.get_audit_logs(100).await.unwrap_or_default();
    Ok(Json(logs.into_iter().map(to_json).collect()))
}

async fn get_user_audit(State(state): State<Arc<AppState>>, Path(user_id): Path<i64>, headers: HeaderMap) -> Result<Json<Vec<serde_json::Value>>, StatusCode> {
    let (_, _) = require_admin(&state, &headers).await?;
    let logs = state.db.get_user_audit_logs(user_id, 50).await.unwrap_or_default();
    Ok(Json(logs.into_iter().map(to_json).collect()))
}

fn to_json(r: AuditRecord) -> serde_json::Value {
    serde_json::json!({
        "id": r.id, "source_user": r.source_user_name,
        "source_device": r.source_device_sn, "source_ip": r.source_ip_wan,
        "source_location": r.source_location, "target_device": r.target_device_sn,
        "target_ip": r.target_ip_wan, "target_location": r.target_location,
        "connected_at": r.connected_at.to_rfc3339(),
        "disconnected_at": r.disconnected_at.map(|d| d.to_rfc3339()),
        "session_id": r.session_id,
    })
}

// ─── Helpers ──────────────────────────────────────────

fn generate_random_key() -> String {
    use sha2::Digest;
    let mut h = sha2::Sha256::new();
    h.update(uuid::Uuid::new_v4().to_string());
    h.update(chrono::Utc::now().to_rfc3339());
    hex::encode(h.finalize())[..32].to_uppercase()
}


