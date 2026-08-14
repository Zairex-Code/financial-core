#!/usr/bin/env bash
set -euo pipefail

# Ejecuta el analisis de SonarQube para todos los microservicios.
# Requisitos:
#   - SonarQube corriendo en http://localhost:9000
#   - Token exportado: export SONAR_TOKEN=<token>
#
# Uso: ./scripts/sonar.sh

if [ -z "${SONAR_TOKEN:-}" ]; then
  echo "ERROR: falta SONAR_TOKEN. Exportalo primero:"
  echo "  export SONAR_TOKEN=<tu-token>"
  exit 1
fi

SERVICES="customer-service account-service credit-service transaction-service yanki-service gateway-service eureka-server config-server"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for svc in $SERVICES; do
  echo "==> Analizando $svc ..."
  (
    cd "$ROOT/$svc"
    export JAVA_HOME="${JAVA_HOME:-$HOME/.jdks/temurin-17.0.20}"
    export PATH="$JAVA_HOME/bin:$PATH"
    ./mvnw sonar:sonar \
      -Dsonar.host.url=http://localhost:9000 \
      -Dsonar.token="$SONAR_TOKEN"
  )
done

echo "==> Analisis completo. Revisa http://localhost:9000"
