#!/usr/bin/env bash
#
# stop-all.sh
# Detiene los 8 servicios Spring Boot (y opcionalmente la infraestructura).
#
# Uso:
#   ./scripts/stop-all.sh            # detiene solo los servicios
#   ./scripts/stop-all.sh --infra    # detiene servicios + infraestructura Docker
#
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORTS="8080 8081 8082 8083 8084 8085 8761 8888"

echo "==> Deteniendo servicios Spring Boot ..."
for port in $PORTS; do
  pids=$(ss -tlnp 2>/dev/null | grep ":$port " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
  for pid in $pids; do
    kill "$pid" 2>/dev/null && echo "    matado pid $pid (:$port)"
  done
done

if [ "${1:-}" = "--infra" ]; then
  echo ""
  echo "==> Deteniendo infraestructura Docker ..."
  (cd "$ROOT/bank-infrastructure" && docker compose down)
fi

sleep 3
echo ""
echo "==> Estado:"
ss -tln 2>/dev/null | grep -E ':(8080|8081|8082|8083|8084|8085|8761|8888) ' \
  || echo "    todos los puertos del proyecto libres"
