#!/bin/bash
# ============================================================
# AzulDesk — Migración manual de base de datos PostgreSQL
# ============================================================
# Usos:
#   ./migrate.sh                    # aplica migraciones a DB via DATABASE_URL
#   ./migrate.sh docker             # aplica migraciones al contenedor Docker
#   ./migrate.sh fresh             # crea esquema desde cero (peligro: borra datos)
# ============================================================

set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

DB_URL="${DATABASE_URL:-postgres://spyware:password@localhost:5432/spyware}"

migrate() {
    local conn="$1"
    echo "▶ Aplicando migraciones a la base de datos..."

    # Migración 1: columna role en users
    psql "$conn" -c "
        ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'support';
    " 2>/dev/null || true

    # Migración 2: actualizar admins existentes
    psql "$conn" -c "
        UPDATE users SET role = 'admin' WHERE is_admin = true AND role = 'support';
    " 2>/dev/null || true

    # Migración 3: columna updated_at en tablas (por si faltan)
    for table in users device_registry certificates master_keys audit_log ca_keys; do
        psql "$conn" -c "ALTER TABLE $table ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();" 2>/dev/null || true
    done

    echo "✓ Migraciones aplicadas correctamente"
}

case "${1:-}" in
    docker)
        CONTAINER="${2:-azuldesk-postgres-1}"
        echo "▶ Ejecutando dentro del contenedor Docker: $CONTAINER"
        docker exec -i "$CONTAINER" psql -U spyware -d spyware <<'EOSQL'
            ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'support';
            UPDATE users SET role = 'admin' WHERE is_admin = true AND role = 'support';
EOSQL
        echo "✓ Migraciones aplicadas en contenedor Docker"
        ;;
    fresh)
        echo "⚠ ATENCIÓN: Esto borrará todas las tablas existentes"
        read -rp "¿Continuar? (s/N): " confirm
        if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            psql "$DB_URL" -f "$DIR/schema.sql"
            echo "✓ Esquema creado desde cero"
        else
            echo "Cancelado"
        fi
        ;;
    *)
        migrate "$DB_URL"
        ;;
esac
