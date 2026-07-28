use anyhow::Result;
use sqlx::PgPool;
use sqlx::postgres::PgPoolOptions;

pub struct Database {
    pool: PgPool,
}

impl Database {
    pub async fn open(database_url: &str) -> Result<Self> {
        let pool = PgPoolOptions::new().max_connections(20).connect(database_url).await?;

        // Migración automática de columnas faltantes (para DBs existentes)
        // updated_at en todas las tablas
        for table in &["users", "device_registry", "certificates", "master_keys", "audit_log", "ca_keys"] {
            sqlx::query(&format!("ALTER TABLE {} ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()", table))
                .execute(&pool).await.ok();
        }

        Ok(Self { pool })
    }

    // ─── Users ──────────────────────────────────────────

    pub async fn create_user(&self, id_number: &str, name: &str, email: &str, password_hash: &str, is_admin: bool) -> Result<i64> {
        let row: (i64,) = sqlx::query_as(
            "INSERT INTO users (identification_number, name, email, password_hash, is_admin) VALUES ($1,$2,$3,$4,$5) RETURNING id"
        ).bind(id_number).bind(name).bind(email).bind(password_hash).bind(is_admin)
         .fetch_one(&self.pool).await?;
        Ok(row.0)
    }

    pub async fn get_user_by_email(&self, email: &str) -> Result<Option<UserRecord>> {
        let user = sqlx::query_as::<_, UserRecord>(
            "SELECT id, identification_number, name, email, password_hash, is_admin, active FROM users WHERE email = $1"
        ).bind(email).fetch_optional(&self.pool).await?;
        Ok(user)
    }

    pub async fn get_user_by_id(&self, id: i64) -> Result<Option<UserRecord>> {
        let user = sqlx::query_as::<_, UserRecord>(
            "SELECT id, identification_number, name, email, password_hash, is_admin, active FROM users WHERE id = $1"
        ).bind(id).fetch_optional(&self.pool).await?;
        Ok(user)
    }

    pub async fn list_users(&self) -> Result<Vec<UserRecord>> {
        let users = sqlx::query_as::<_, UserRecord>(
            "SELECT id, identification_number, name, email, password_hash, is_admin, active FROM users ORDER BY name"
        ).fetch_all(&self.pool).await?;
        Ok(users)
    }

    // ─── Device Registry ────────────────────────────────

    pub async fn register_device(&self, sn: &str, owner_id: i64, registered_by: i64, device_name: &str, mac: &str) -> Result<bool> {
        let exists: bool = sqlx::query_scalar(
            "SELECT COUNT(*) > 0 FROM device_registry WHERE serial_number = $1"
        ).bind(sn).fetch_one(&self.pool).await?;

        if exists {
            sqlx::query(
                "UPDATE device_registry SET last_seen = NOW(), mac_address = $2, device_name = $3 WHERE serial_number = $1"
            ).bind(sn).bind(mac).bind(device_name).execute(&self.pool).await?;
            Ok(false)
        } else {
            sqlx::query(
                "INSERT INTO device_registry (serial_number, owner_user_id, registered_by, device_name, mac_address) VALUES ($1,$2,$3,$4,$5)"
            ).bind(sn).bind(owner_id).bind(registered_by).bind(device_name).bind(mac)
             .execute(&self.pool).await?;
            Ok(true)
        }
    }

    pub async fn get_device_by_sn(&self, sn: &str) -> Result<Option<DeviceRecord>> {
        let d = sqlx::query_as::<_, DeviceRecord>(
            "SELECT id, serial_number, device_name, manufacturer, model, mac_address, owner_user_id, active, last_seen FROM device_registry WHERE serial_number = $1"
        ).bind(sn).fetch_optional(&self.pool).await?;
        Ok(d)
    }

    pub async fn get_user_devices(&self, user_id: i64) -> Result<Vec<DeviceRecord>> {
        let devices = sqlx::query_as::<_, DeviceRecord>(
            "SELECT id, serial_number, device_name, manufacturer, model, mac_address, owner_user_id, active, last_seen FROM device_registry WHERE owner_user_id = $1 ORDER BY device_name"
        ).bind(user_id).fetch_all(&self.pool).await?;
        Ok(devices)
    }

    pub async fn list_all_devices(&self) -> Result<Vec<DeviceRecord>> {
        let devices = sqlx::query_as::<_, DeviceRecord>(
            "SELECT id, serial_number, device_name, manufacturer, model, mac_address, owner_user_id, active, last_seen FROM device_registry ORDER BY device_name"
        ).fetch_all(&self.pool).await?;
        Ok(devices)
    }

    // ─── Certificates ──────────────────────────────────

    pub async fn issue_certificate(&self, sn: &str, cert_pem: &str, installer_name: &str, installer_id: &str, master_key_id: Option<i64>) -> Result<i64> {
        let row: (i64,) = sqlx::query_as(
            "INSERT INTO certificates (serial_number, certificate_pem, installer_name, installer_identification, master_key_id) VALUES ($1,$2,$3,$4,$5) RETURNING id"
        ).bind(sn).bind(cert_pem).bind(installer_name).bind(installer_id).bind(master_key_id)
         .fetch_one(&self.pool).await?;
        Ok(row.0)
    }

    pub async fn get_certificate_status(&self, sn: &str) -> Result<Option<CertRecord>> {
        let cert = sqlx::query_as::<_, CertRecord>(
            "SELECT id, serial_number, status, issued_at, blocked_at, blocked_by FROM certificates WHERE serial_number = $1 ORDER BY issued_at DESC LIMIT 1"
        ).bind(sn).fetch_optional(&self.pool).await?;
        Ok(cert)
    }

    pub async fn block_certificate(&self, sn: &str, blocked_by: i64) -> Result<()> {
        sqlx::query(
            "UPDATE certificates SET status = 'blocked', blocked_at = NOW(), blocked_by = $2 WHERE serial_number = $1 AND status = 'active'"
        ).bind(sn).bind(blocked_by).execute(&self.pool).await?;
        Ok(())
    }

    pub async fn unblock_certificate(&self, sn: &str) -> Result<()> {
        sqlx::query(
            "UPDATE certificates SET status = 'active', blocked_at = NULL, blocked_by = NULL WHERE serial_number = $1 AND status = 'blocked'"
        ).bind(sn).execute(&self.pool).await?;
        Ok(())
    }

    // ─── Master Keys ──────────────────────────────────

    pub async fn create_master_key(&self, key_hash: &str, valid_from: &chrono::DateTime<chrono::Utc>, valid_until: &chrono::DateTime<chrono::Utc>, created_by: i64) -> Result<i64> {
        let row: (i64,) = sqlx::query_as(
            "INSERT INTO master_keys (key_hash, valid_from, valid_until, created_by) VALUES ($1,$2,$3,$4) RETURNING id"
        ).bind(key_hash).bind(valid_from).bind(valid_until).bind(created_by)
         .fetch_one(&self.pool).await?;
        Ok(row.0)
    }

    pub async fn validate_master_key(&self, key_hash: &str) -> Result<Option<i64>> {
        let result: Option<(i64,)> = sqlx::query_as(
            "SELECT id FROM master_keys WHERE key_hash = $1 AND valid_from <= NOW() AND valid_until >= NOW() LIMIT 1"
        ).bind(key_hash).fetch_optional(&self.pool).await?;
        Ok(result.map(|r| r.0))
    }

    pub async fn get_current_master_key(&self) -> Result<Option<MasterKeyRecord>> {
        let key = sqlx::query_as::<_, MasterKeyRecord>(
            "SELECT id, key_hash, key_plaintext, valid_from, valid_until, created_by, generated_by FROM master_keys WHERE valid_from <= NOW() AND valid_until >= NOW() ORDER BY valid_from DESC LIMIT 1"
        ).fetch_optional(&self.pool).await?;
        Ok(key)
    }

    pub async fn create_master_key_direct(&self, plaintext: &str, hash: &str, valid_from: &chrono::DateTime<chrono::Utc>, valid_until: &chrono::DateTime<chrono::Utc>, created_by: Option<i64>, generated_by: &str) -> Result<i64> {
        let row: (i64,) = sqlx::query_as(
            "INSERT INTO master_keys (key_hash, key_plaintext, valid_from, valid_until, created_by, generated_by) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id"
        ).bind(hash).bind(plaintext).bind(valid_from).bind(valid_until).bind(created_by).bind(generated_by)
         .fetch_one(&self.pool).await?;
        Ok(row.0)
    }

    // ─── Audit Log ─────────────────────────────────────

    pub async fn log_connection_audit(&self, source_user_id: Option<i64>, source_device_sn: &str, source_ip: &str, source_loc: &str, target_sn: &str, target_ip: &str, target_loc: &str, session_id: &str) -> Result<i64> {
        let row: (i64,) = sqlx::query_as(
            "INSERT INTO audit_log (source_user_id, source_device_sn, source_ip_wan, source_location, target_device_sn, target_ip_wan, target_location, session_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id"
        ).bind(source_user_id).bind(source_device_sn).bind(source_ip).bind(source_loc).bind(target_sn).bind(target_ip).bind(target_loc).bind(session_id)
         .fetch_one(&self.pool).await?;
        Ok(row.0)
    }

    pub async fn close_audit_log(&self, log_id: i64) -> Result<()> {
        sqlx::query("UPDATE audit_log SET disconnected_at = NOW() WHERE id = $1")
            .bind(log_id).execute(&self.pool).await?;
        Ok(())
    }

    pub async fn get_audit_logs(&self, limit: i64) -> Result<Vec<AuditRecord>> {
        let logs = sqlx::query_as::<_, AuditRecord>(
            "SELECT al.*, su.name AS source_user_name, tu.name AS target_user_name FROM audit_log al LEFT JOIN users su ON al.source_user_id = su.id LEFT JOIN device_registry td ON al.target_device_sn = td.serial_number LEFT JOIN users tu ON td.owner_user_id = tu.id ORDER BY al.connected_at DESC LIMIT $1"
        ).bind(limit).fetch_all(&self.pool).await?;
        Ok(logs)
    }

    // ─── CA Storage ────────────────────────────────────

    pub async fn get_ca(&self) -> Result<Option<(String, String)>> {
        let result = sqlx::query_as::<_, (String, String)>(
            "SELECT ca_cert_pem, ca_key_pem FROM ca_keys WHERE id = 1"
        ).fetch_optional(&self.pool).await?;
        Ok(result)
    }

    pub async fn store_ca(&self, cert_pem: &str, key_pem: &str) -> Result<()> {
        sqlx::query(
            "INSERT INTO ca_keys (id, ca_cert_pem, ca_key_pem) VALUES (1, $1, $2) ON CONFLICT (id) DO UPDATE SET ca_cert_pem = $1, ca_key_pem = $2"
        ).bind(cert_pem).bind(key_pem).execute(&self.pool).await?;
        Ok(())
    }

    pub async fn get_user_audit_logs(&self, user_id: i64, limit: i64) -> Result<Vec<AuditRecord>> {
        let logs = sqlx::query_as::<_, AuditRecord>(
            "SELECT al.*, su.name AS source_user_name, tu.name AS target_user_name FROM audit_log al LEFT JOIN users su ON al.source_user_id = su.id LEFT JOIN device_registry td ON al.target_device_sn = td.serial_number LEFT JOIN users tu ON td.owner_user_id = tu.id WHERE al.source_user_id = $1 OR td.owner_user_id = $1 ORDER BY al.connected_at DESC LIMIT $2"
        ).bind(user_id).bind(limit).fetch_all(&self.pool).await?;
        Ok(logs)
    }
}

// ─── Record Types ──────────────────────────────────────

#[derive(Debug, sqlx::FromRow)]
pub struct UserRecord {
    pub id: i64,
    pub identification_number: String,
    pub name: String,
    pub email: String,
    pub password_hash: String,
    pub is_admin: bool,
    pub active: bool,
}

#[derive(Debug, sqlx::FromRow)]
pub struct DeviceRecord {
    pub id: i64,
    pub serial_number: String,
    pub device_name: String,
    pub manufacturer: String,
    pub model: String,
    pub mac_address: String,
    pub owner_user_id: Option<i64>,
    pub active: bool,
    pub last_seen: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct CertRecord {
    pub id: i64,
    pub serial_number: String,
    pub status: String,
    pub issued_at: chrono::DateTime<chrono::Utc>,
    pub blocked_at: Option<chrono::DateTime<chrono::Utc>>,
    pub blocked_by: Option<i64>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct MasterKeyRecord {
    pub id: i64,
    pub key_hash: String,
    pub key_plaintext: String,
    pub valid_from: chrono::DateTime<chrono::Utc>,
    pub valid_until: chrono::DateTime<chrono::Utc>,
    pub created_by: Option<i64>,
    pub generated_by: Option<String>,
}

#[derive(Debug, sqlx::FromRow)]
pub struct AuditRecord {
    pub id: i64,
    pub source_user_id: Option<i64>,
    pub source_device_sn: Option<String>,
    pub source_ip_wan: String,
    pub source_location: String,
    pub target_device_sn: String,
    pub target_ip_wan: String,
    pub target_location: String,
    pub connected_at: chrono::DateTime<chrono::Utc>,
    pub disconnected_at: Option<chrono::DateTime<chrono::Utc>>,
    pub session_id: String,
    pub source_user_name: Option<String>,
    pub target_user_name: Option<String>,
}
