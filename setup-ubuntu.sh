#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# AzulDesk Server — Instalación en Ubuntu 22.04 / 24.04
# ============================================================
# Uso:
#   chmod +x setup-ubuntu.sh
#   sudo ./setup-ubuntu.sh
# ============================================================

SPYWARE_USER="${SPYWARE_USER:-spyware}"
SPYWARE_DB="${SPYWARE_DB:-spyware}"
SPYWARE_PASS="${SPYWARE_PASS:-$(openssl rand -base64 24)}"
SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-7980}"
RELAY_ENABLED="${RELAY_ENABLED:-false}"

echo "=== AzulDesk Server — Instalación ==="

# ─── 1. Dependencias del sistema ──────────────────────────
echo "[1/7] Instalando dependencias del sistema..."
apt-get update -qq
apt-get install -y -qq curl wget gnupg lsb-release ca-certificates \
    build-essential pkg-config libssl-dev git

# ─── 2. PostgreSQL 18 ─────────────────────────────────────
echo "[2/7] Instalando PostgreSQL 18..."
if ! command -v psql &>/dev/null; then
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    sh -c 'echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    apt-get update -qq
    apt-get install -y -qq postgresql-18
fi

# ─── 3. Crear base de datos y usuario ─────────────────────
echo "[3/7] Creando base de datos '$SPYWARE_DB'..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$SPYWARE_USER'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER $SPYWARE_USER WITH PASSWORD '$SPYWARE_PASS';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$SPYWARE_DB'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE $SPYWARE_DB OWNER $SPYWARE_USER;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $SPYWARE_DB TO $SPYWARE_USER;"

# ─── 4. Ejecutar schema.sql ──────────────────────────────
echo "[4/7] Ejecutando schema.sql..."
DIR="$(cd "$(dirname "$0")" && pwd)"
PGPASSWORD="$SPYWARE_PASS" psql -h localhost -U "$SPYWARE_USER" -d "$SPYWARE_DB" -f "$DIR/schema.sql"

# ─── 5. Instalar Rust ────────────────────────────────────
echo "[5/7] Instalando Rust..."
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    . "$HOME/.cargo/env"
fi

# ─── 6. Compilar el servidor ─────────────────────────────
echo "[6/7] Compilando azuldesk-server..."
cd "$DIR"
cargo build --release -p azuldesk-server

# ─── 7. Crear .env, systemd y lanzar ────────────────────
echo "[7/7] Configurando servicio systemd..."

# .env
cat > "$DIR/.env" <<EOF
DATABASE_URL=postgres://$SPYWARE_USER:$SPYWARE_PASS@localhost:5432/$SPYWARE_DB
SERVER_HOST=$SERVER_HOST
SERVER_PORT=$SERVER_PORT
RELAY_ENABLED=$RELAY_ENABLED
RELAY_HOST=$SERVER_HOST
RELAY_PORT=7981
UPDATES_DIR=$DIR/updates
RUST_LOG=azuldesk_server=info
EOF

# systemd unit
cat > /etc/systemd/system/azuldesk-server.service <<UNIT
[Unit]
Description=AzulDesk Remote Desktop Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=$DIR
EnvironmentFile=$DIR/.env
ExecStart=$DIR/target/release/azuldesk-server
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable azuldesk-server
systemctl restart azuldesk-server

echo ""
echo "=== Instalación completada ==="
echo "  DB:       postgres://$SPYWARE_USER:***@localhost:5432/$SPYWARE_DB"
echo "  Password: $SPYWARE_PASS"
echo "  WebSocket: ws://$SERVER_HOST:$SERVER_PORT"
echo "  REST API:  http://$SERVER_HOST:$((SERVER_PORT + 1))"
echo ""
echo "  Crear admin inicial (ejecutar como azuldesk):"
echo "    cd $DIR"
echo "    ./target/release/azuldesk-server create-admin \\"
echo "      --id ADMIN-001 --name \"Mi Admin\" \\"
echo "      --email admin@midominio.com --password <password>"
echo ""
echo "  Comandos útiles:"
echo "    sudo journalctl -u azuldesk-server -f   # Ver logs"
echo "    sudo systemctl restart azuldesk-server   # Reiniciar"
echo "    sudo systemctl status azuldesk-server    # Estado"
