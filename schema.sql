-- ============================================================
-- Spyware Server — Esquema Completo PostgreSQL
-- ============================================================
-- Crear usuario y base de datos:
--   CREATE USER spyware WITH PASSWORD 'password';
--   CREATE DATABASE spyware OWNER spyware;
--   \c spyware
--   \i schema.sql
-- ============================================================

-- ─── Función para updated_at automático ──────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─── 1. Usuarios ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id                    BIGSERIAL PRIMARY KEY,
    identification_number TEXT UNIQUE NOT NULL,
    name                  TEXT NOT NULL,
    email                 TEXT UNIQUE NOT NULL,
    password_hash         TEXT NOT NULL,
    role                  TEXT NOT NULL DEFAULT 'support' CHECK (role IN ('admin', 'support')),
    active                BOOLEAN NOT NULL DEFAULT true,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 2. Dispositivos ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS device_registry (
    id                  BIGSERIAL PRIMARY KEY,
    serial_number       TEXT UNIQUE NOT NULL,
    device_name         TEXT NOT NULL DEFAULT '',
    manufacturer        TEXT NOT NULL DEFAULT '',
    model               TEXT NOT NULL DEFAULT '',
    mac_address         TEXT NOT NULL DEFAULT '',
    owner_user_id       BIGINT REFERENCES users(id),
    registered_by       BIGINT REFERENCES users(id),
    active              BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen           TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_device_registry_updated_at ON device_registry;
CREATE TRIGGER trg_device_registry_updated_at
    BEFORE UPDATE ON device_registry
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 3. Claves maestras horarias ─────────────────────────
CREATE TABLE IF NOT EXISTS master_keys (
    id              BIGSERIAL PRIMARY KEY,
    key_hash        TEXT NOT NULL,
    key_plaintext   TEXT NOT NULL DEFAULT '',
    valid_from      TIMESTAMPTZ NOT NULL,
    valid_until     TIMESTAMPTZ NOT NULL,
    created_by      BIGINT REFERENCES users(id),
    generated_by    TEXT NOT NULL DEFAULT 'auto',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_master_keys_updated_at ON master_keys;
CREATE TRIGGER trg_master_keys_updated_at
    BEFORE UPDATE ON master_keys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 4. Certificados ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS certificates (
    id                      BIGSERIAL PRIMARY KEY,
    serial_number           TEXT NOT NULL REFERENCES device_registry(serial_number),
    certificate_pem         TEXT NOT NULL,
    issued_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status                  TEXT NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active', 'blocked')),
    blocked_at              TIMESTAMPTZ,
    blocked_by              BIGINT REFERENCES users(id),
    installer_name          TEXT NOT NULL DEFAULT '',
    installer_identification TEXT NOT NULL DEFAULT '',
    master_key_id           BIGINT REFERENCES master_keys(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_certificates_updated_at ON certificates;
CREATE TRIGGER trg_certificates_updated_at
    BEFORE UPDATE ON certificates
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 5. Auditoría de conexiones ─────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
    id                BIGSERIAL PRIMARY KEY,
    source_user_id    BIGINT REFERENCES users(id),
    source_device_sn  TEXT REFERENCES device_registry(serial_number),
    source_ip_wan     TEXT NOT NULL DEFAULT '',
    source_location   TEXT NOT NULL DEFAULT '',
    target_device_sn  TEXT NOT NULL REFERENCES device_registry(serial_number),
    target_ip_wan     TEXT NOT NULL DEFAULT '',
    target_location   TEXT NOT NULL DEFAULT '',
    connected_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    disconnected_at   TIMESTAMPTZ,
    session_id        TEXT NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_audit_log_updated_at ON audit_log;
CREATE TRIGGER trg_audit_log_updated_at
    BEFORE UPDATE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 6. CA interna ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS ca_keys (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    ca_cert_pem TEXT NOT NULL,
    ca_key_pem  TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_ca_keys_updated_at ON ca_keys;
CREATE TRIGGER trg_ca_keys_updated_at
    BEFORE UPDATE ON ca_keys
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── Índices ──────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_device_registry_owner ON device_registry(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_device_registry_serial ON device_registry(serial_number);
CREATE INDEX IF NOT EXISTS idx_certificates_serial ON certificates(serial_number);
CREATE INDEX IF NOT EXISTS idx_certificates_status ON certificates(status);
CREATE INDEX IF NOT EXISTS idx_master_keys_valid ON master_keys(valid_from, valid_until);
CREATE INDEX IF NOT EXISTS idx_audit_log_connected ON audit_log(connected_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_source ON audit_log(source_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON audit_log(target_device_sn);
