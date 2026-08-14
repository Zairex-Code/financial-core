#!/usr/bin/env bash
set -euo pipefail

# Exports the OpenAPI (Swagger) spec of each running microservice into docs/openapi/.
# Usage: ./scripts/export-openapi.sh [base-url]
#   base-url defaults to http://localhost

BASE="${1:-http://localhost}"
OUT="docs/openapi"
mkdir -p "$OUT"

SERVICES="customer-service:8081 account-service:8082 credit-service:8083 transaction-service:8084 yanki-service:8085"

for entry in $SERVICES; do
  svc="${entry%%:*}"
  port="${entry##*:}"
  echo "Exporting $svc (port $port) ..."
  if curl -sf "${BASE}:${port}/v3/api-docs" -o "${OUT}/${svc}.yaml"; then
    echo "  -> ${OUT}/${svc}.yaml"
  else
    echo "  ! $svc no esta disponible en ${BASE}:${port}"
  fi
done

echo "Done. Especificaciones en ${OUT}/"
