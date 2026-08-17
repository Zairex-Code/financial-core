#!/usr/bin/env bash
#
# start-all.sh
# Levanta la infraestructura Docker + los 8 servicios en orden correcto,
# en background, y espera hasta que esten sanos.
#
# Uso: ./scripts/start-all.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

# JDK 17
export JAVA_HOME="${JAVA_HOME:-$HOME/.jdks/temurin-17.0.20}"
export PATH="$JAVA_HOME/bin:$PATH"

echo "==> Java: $(java -version 2>&1 | head -1)"

echo ""
echo "==> 1. Infraestructura Docker (mongo, redis, zookeeper, kafka, kafka-ui, sonarqube) ..."
(cd "$ROOT/bank-infrastructure" && docker compose up -d)
echo "    Esperando 30s a que Mongo/Kafka esten listos ..."
sleep 30

# Asegurar el topic de debit-cards (idempotente)
docker exec kafka kafka-topics --create --if-not-exists \
  --topic debit-card-payments --bootstrap-server localhost:9092 \
  --partitions 1 --replication-factor 1 >/dev/null 2>&1 \
  && echo "    Topic 'debit-card-payments' listo" || true

wait_port() {
  local port="$1" name="$2"
  for i in $(seq 1 60); do
    if ss -tln 2>/dev/null | grep -q ":$port "; then
      echo "    $name listo en :$port (~$((i*5))s)"
      return 0
    fi
    sleep 5
  done
  echo "    ERROR: $name no abrio el puerto $port" >&2
  return 1
}

start_service() {
  local svc="$1" port="$2"
  if ss -tln 2>/dev/null | grep -q ":$port "; then
    echo "    $svc ya esta corriendo en :$port (omitido)"
    return 0
  fi
  echo "==> Levantando $svc (:$port) ..."
  ( cd "$ROOT/$svc" && nohup ./mvnw spring-boot:run > "$LOG_DIR/$svc.log" 2>&1 & )
}

echo ""
echo "==> 2. Servicios base (config-server y eureka-server) ..."
start_service config-server 8888
start_service eureka-server 8761
wait_port 8888 "config-server"
wait_port 8761 "eureka-server"
sleep 10

echo ""
echo "==> 3. Microservicios ..."
start_service customer-service 8081
start_service account-service 8082
start_service credit-service 8083
start_service transaction-service 8084
start_service yanki-service 8085

echo ""
echo "==> 4. Gateway ..."
start_service gateway-service 8080

echo ""
echo "==> 5. Esperando a que todos esten sanos ..."
for p in 8081 8082 8083 8084 8085 8080; do wait_port "$p" "servicio"; done

echo ""
echo "==> 6. Resumen de salud:"
for p in 8080 8081 8082 8083 8084 8085; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$p/actuator/health")
  echo "    :$p -> $code"
done

echo ""
echo "==> Registrados en Eureka:"
curl -s http://localhost:8761/eureka/apps | grep -o '<name>[^<]*</name>' | sort -u

echo ""
echo "==> Listo. Logs en: $LOG_DIR"
