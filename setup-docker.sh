#!/usr/bin/env bash
set -euo pipefail
# ============================================================
# AzulDesk Server — Instalación con Docker
# ============================================================
# Uso:
#   chmod +x setup-docker.sh
#   sudo ./setup-docker.sh
# ============================================================

SPYWARE_USER="${SPYWARE_USER:-spyware}"
SPYWARE_DB="${SPYWARE_DB:-spyware}"
SPYWARE_PASS="${SPYWARE_PASS:-$(openssl rand -hex 24)}"
SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-7980}"
RELAY_ENABLED="${RELAY_ENABLED:-false}"
RELAY_PORT="${RELAY_PORT:-7981}"

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== AzulDesk Server — Instalación con Docker ==="

# ─── 1. Dependencias del sistema ──────────────────────────
echo "[1/5] Instalando Docker y dependencias..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
if ! command -v docker compose &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq docker-compose-plugin
fi
apt-get install -y -qq logrotate curl openssl

# ─── 2. Crear directorios locales ─────────────────────────
echo "[2/5] Creando directorios locales..."
mkdir -p "$DIR/logs"
mkdir -p "$DIR/updates"

# ─── 3. Crear .env para docker-compose ────────────────────
echo "[3/5] Creando .env..."
# Forzamos 0.0.0.0 para bind interno del contenedor
# (el dominio público se configura en el cliente Flutter)
BIND_HOST="0.0.0.0"

if [ ! -f "$DIR/.env" ]; then
    cat > "$DIR/.env" <<EOF
DB_PASSWORD=$SPYWARE_PASS
SERVER_HOST=$BIND_HOST
SERVER_PORT=$SERVER_PORT
RELAY_ENABLED=$RELAY_ENABLED
RELAY_HOST=$BIND_HOST
RELAY_PORT=$RELAY_PORT
UPDATES_DIR=/updates
RUST_LOG=azuldesk_server=info
EOF
    echo "  .env creado con contraseña generada"
else
    echo "  .env ya existe, se respeta"
fi

# ─── 4. Configurar logrotate para logs del contenedor ────
echo "[4/5] Configurando logrotate..."
mkdir -p /etc/logrotate.d
cat > /etc/logrotate.d/azuldesk-server <<LOGROTATE
$DIR/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE

# ─── 5. Construir y levantar ──────────────────────────────
echo "[5/5] Construyendo y levantando contenedores..."
cd "$DIR"
docker compose build
docker compose up -d

echo ""
echo "=== Instalación completada ==="
echo "  DB:       postgres://$SPYWARE_USER:***@postgres:5432/$SPYWARE_DB"
echo "  Password: $SPYWARE_PASS"
echo "  WebSocket: ws://$SERVER_HOST:$SERVER_PORT"
echo "  REST API:  http://$SERVER_HOST:$((SERVER_PORT + 1))"
echo ""
echo "  Crear admin inicial:"
echo "    docker exec -it \$(docker compose ps -q server) /azuldesk-server create-admin \\"
echo "      --id ADMIN-001 --name \"Mi Admin\" \\"
echo "      --email admin@midominio.com --password <password>"
echo ""
echo "  Comandos útiles:"
echo "    cd $DIR && docker compose logs -f     # Ver logs"
echo "    cd $DIR && docker compose restart     # Reiniciar"
echo "    cd $DIR && docker compose ps          # Estado"
echo "    ls -la $DIR/logs/                     # Logs locales"
