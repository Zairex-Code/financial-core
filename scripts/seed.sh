#!/usr/bin/env bash
set -uo pipefail

# Seed de datos de demostracion para el Financial Core.
# Requiere los microservicios y la infraestructura levantados.
# Uso: ./scripts/seed.sh [base-url]  (default http://localhost:8080)

BASE="${1:-http://localhost:8080}"

extract_id() {
  grep -oE '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

post() {
  curl -s -X POST "$BASE$1" -H "Content-Type: application/json" -d "$2"
}

echo "=== 1) Clientes ==="
C1=$(post /api/v1/customers '{"documentNumber":"12345678","documentType":"DNI","name":"Juan Perez","email":"juan.perez@gmail.com","phoneNumber":"+51999111222","type":"PERSONAL"}')
C1_ID=$(echo "$C1" | extract_id)
echo "C1 (personal Juan) = $C1_ID"

C2=$(post /api/v1/customers '{"documentNumber":"87654321","documentType":"DNI","name":"Maria Lopez","email":"maria.lopez@gmail.com","phoneNumber":"+51999333444","type":"PERSONAL"}')
C2_ID=$(echo "$C2" | extract_id)
echo "C2 (personal Maria) = $C2_ID"

C3=$(post /api/v1/customers '{"documentNumber":"20123456789","documentType":"RUC","name":"Tech Solutions SAC","email":"contacto@techsol.com","phoneNumber":"+5111234567","type":"BUSINESS"}')
C3_ID=$(echo "$C3" | extract_id)
echo "C3 (empresarial Tech) = $C3_ID"

C4=$(post /api/v1/customers '{"documentNumber":"20234567890","documentType":"RUC","name":"Grupo Andino SRL","email":"info@grupoandino.com","phoneNumber":"+5117654321","type":"BUSINESS"}')
C4_ID=$(echo "$C4" | extract_id)
echo "C4 (empresarial Andino) = $C4_ID"

echo ""
echo "=== 2) Perfiles VIP / PYME ==="
curl -s -X PUT "$BASE/api/v1/customers/$C1_ID" -H "Content-Type: application/json" \
  -d '{"documentNumber":"12345678","documentType":"DNI","name":"Juan Perez","email":"juan.perez@gmail.com","phoneNumber":"+51999111222","type":"PERSONAL","profile":"VIP"}' > /dev/null
echo "C1 -> VIP"
curl -s -X PUT "$BASE/api/v1/customers/$C3_ID" -H "Content-Type: application/json" \
  -d '{"documentNumber":"20123456789","documentType":"RUC","name":"Tech Solutions SAC","email":"contacto@techsol.com","phoneNumber":"+5111234567","type":"BUSINESS","profile":"PYME"}' > /dev/null
echo "C3 -> PYME"

echo ""
echo "=== 3) Cuentas ==="
A1=$(post /api/v1/accounts "{\"customerId\":\"$C1_ID\",\"type\":\"SAVINGS\",\"balance\":5000.0}")
A1_ID=$(echo "$A1" | extract_id)
echo "A1 (ahorro Juan) = $A1_ID"

A2=$(post /api/v1/accounts "{\"customerId\":\"$C3_ID\",\"type\":\"CURRENT\",\"balance\":10000.0}")
A2_ID=$(echo "$A2" | extract_id)
echo "A2 (corriente Tech) = $A2_ID"

A3=$(post /api/v1/accounts "{\"customerId\":\"$C1_ID\",\"type\":\"FIXED_TERM\",\"balance\":20000.0}")
A3_ID=$(echo "$A3" | extract_id)
echo "A3 (plazo fijo Juan) = $A3_ID"

A4=$(post /api/v1/accounts "{\"customerId\":\"$C2_ID\",\"type\":\"SAVINGS\",\"balance\":3000.0}")
A4_ID=$(echo "$A4" | extract_id)
echo "A4 (ahorro Maria) = $A4_ID"

echo ""
echo "=== 4) Creditos ==="
CR1=$(post /api/v1/credits "{\"customerId\":\"$C1_ID\",\"type\":\"PERSONAL\",\"amount\":50000.0,\"interestRate\":15.5,\"installmentCount\":12}")
CR1_ID=$(echo "$CR1" | extract_id)
echo "CR1 (personal Juan) = $CR1_ID"

CR2=$(post /api/v1/credits "{\"customerId\":\"$C1_ID\",\"type\":\"CREDIT_CARD\",\"creditLimit\":10000.0}")
CR2_ID=$(echo "$CR2" | extract_id)
echo "CR2 (TC Juan) = $CR2_ID"

CR3=$(post /api/v1/credits "{\"customerId\":\"$C3_ID\",\"type\":\"BUSINESS\",\"amount\":200000.0,\"interestRate\":12.0,\"installmentCount\":24}")
CR3_ID=$(echo "$CR3" | extract_id)
echo "CR3 (empresarial Tech) = $CR3_ID"

CR4=$(post /api/v1/credits "{\"customerId\":\"$C2_ID\",\"type\":\"CREDIT_CARD\",\"creditLimit\":5000.0}")
CR4_ID=$(echo "$CR4" | extract_id)
echo "CR4 (TC Maria) = $CR4_ID"

echo ""
echo "=== 5) Transacciones (generan movimientos) ==="
post "/api/v1/accounts/$A1_ID/deposits" '{"amount":1000.0}' > /dev/null && echo "deposito A1 +1000"
post "/api/v1/accounts/$A1_ID/withdrawals" '{"amount":500.0}' > /dev/null && echo "retiro A1 -500"
post "/api/v1/accounts/$A1_ID/transfers" "{\"destinationAccountId\":\"$A4_ID\",\"amount\":500.0}" > /dev/null && echo "transferencia A1 -> A4 (500)"
post "/api/v1/credits/$CR1_ID/payments" '{"amount":5000.0}' > /dev/null && echo "pago CR1 (5000)"
post "/api/v1/credits/$CR2_ID/consumptions" '{"amount":1500.0}' > /dev/null && echo "consumo TC CR2 (1500)"
CR1_NUMBER=$(curl -s "$BASE/api/v1/credits/$CR1_ID" | grep -oE '"creditNumber":"[^"]*"' | cut -d'"' -f4)
post "/api/v1/credits/number/$CR1_NUMBER/third-party-payments" "{\"payerCustomerId\":\"$C2_ID\",\"amount\":2000.0}" > /dev/null && echo "pago de tercero a CR1 (2000, pagador Maria)"

echo ""
echo "=== 6) Tarjetas de debito ==="
DC=$(post /api/v1/debit-cards "{\"accountId\":\"$A1_ID\"}")
DC_ID=$(echo "$DC" | extract_id)
echo "tarjeta debito para A1 = $DC_ID"
post "/api/v1/debit-cards/$DC_ID/payments" '{"amount":300.0}' > /dev/null && echo "pago con debito (300) -> evento Kafka"

echo ""
echo "=== 7) Billeteras Yanki ==="
W1=$(post /api/v1/wallets '{"phoneNumber":"+51999111222","documentNumber":"12345678","documentType":"DNI","name":"Juan Perez","email":"juan.perez@gmail.com","imei":"123456789012345"}')
W1_ID=$(echo "$W1" | extract_id)
echo "W1 = $W1_ID"

W2=$(post /api/v1/wallets '{"phoneNumber":"+51999333444","documentNumber":"87654321","documentType":"DNI","name":"Maria Lopez","email":"maria.lopez@gmail.com","imei":"123456789099999"}')
W2_ID=$(echo "$W2" | extract_id)
echo "W2 = $W2_ID"

echo ""
echo "=== Resumen de IDs ==="
echo "clientes:   C1=$C1_ID C2=$C2_ID C3=$C3_ID C4=$C4_ID"
echo "cuentas:    A1=$A1_ID A2=$A2_ID A3=$A3_ID A4=$A4_ID"
echo "creditos:   CR1=$CR1_ID CR2=$CR2_ID CR3=$CR3_ID CR4=$CR4_ID"
echo "debito:     DC=$DC_ID"
echo "billeteras: W1=$W1_ID W2=$W2_ID"
