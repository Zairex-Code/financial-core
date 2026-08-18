# Prompt reutilizable para generar los diagramas con cualquier IA

Copia TODO el bloque siguiente y pégalo en la IA de tu preferencia (ChatGPT, Claude, Gemini, etc.).
Pídele el formato de salida al final (se recomienda **XML de draw.io** para abrirlo directamente).

---

```
Eres un arquitecto de software. Genera diagramas técnicos para un ecosistema bancario de microservicios
llamado "Financial Core". Usa EXACTAMENTE estos datos (nombres, puertos, endpoints y topics reales).
Todo el texto debe ir en ESPAÑOL.

# CONTEXTO DEL ECOSISTEMA

## Servicios (Spring Boot 3.4.2 + WebFlux + RxJava3, arquitectura hexagonal)
- config-server (puerto 8888): Config Server, perfil "native", classpath:/config.
- eureka-server (puerto 8761): Service Discovery.
- customer-service (puerto 8081): gestión de clientes. BD MongoDB "customer_db", colección "customer".
  Usa Redis (clave customer:{id}) con cache-aside.
- account-service (puerto 8082): cuentas y tarjetas de débito. BD "account_db", colecciones "accounts" y "debit_cards".
- credit-service (puerto 8083): créditos. BD "credit_db", colección "credits".
- transaction-service (puerto 8084): ledger de movimientos. BD "transaction_db", colección "movements".
- yanki-service (puerto 8085): billetera móvil. BD "yanki_db", colección "wallets".
- gateway-service (puerto 8080): API Gateway (Spring Cloud Gateway).

## Infraestructura (Docker)
- MongoDB (27017): UNA instancia con 5 bases: customer_db, account_db, credit_db, transaction_db, yanki_db.
- Redis (6379): solo customer-service.
- Kafka + Zookeeper (9092 · 2181): topic "debit-card-payments".
- kafka-ui (8089). SonarQube (9000) + SonarQube-DB PostgreSQL.

## Rutas del Gateway
- /api/v1/customers/**  -> lb://customer-service
- /api/v1/accounts/**    -> lb://account-service
- /api/v1/debit-cards/** -> lb://account-service
- /api/v1/credits/**     -> lb://credit-service
- /api/v1/movements/**   -> lb://transaction-service
- /api/v1/wallets/**     -> lb://yanki-service

## Comunicación entre servicios (WebClient, resuelto por Eureka)
- account-service -> customer-service: GET /api/v1/customers/{id} (validar cliente).
- account-service -> transaction-service: POST /api/v1/movements (registrar DEPOSIT/WITHDRAWAL/TRANSFER).
- credit-service  -> customer-service: GET /api/v1/customers/{id} (validar cliente).
- credit-service  -> transaction-service: POST /api/v1/movements (registrar PAYMENT/CARD_CONSUMPTION).

## Kafka (asíncrono)
- Productor: account-service publica el evento "debit-card-payments" al pagar con tarjeta de débito.
- Consumidor: transaction-service (@KafkaListener, groupId "transaction-service") registra un Movement WITHDRAWAL.

## Modelos de dominio (campos)
- Customer: id, documentNumber, documentType, name, email, phoneNumber, type[PERSONAL,BUSINESS],
  profile[STANDARD,VIP,PYME], status[ACTIVE,INACTIVE,BLOCKED], hasOverdueDebit(Boolean), createdAt, updatedAt.
- Account: id, accountNumber, customerId, type[SAVINGS,CURRENT,FIXED_TERM],
  status[ACTIVE,BLOCKED,INACTIVE,CLOSED], balance, maintenanceFee, maxMonthlyTransactions,
  currentMonthlyTransactions, allowedTransactionDay, transactionCommission, holders[], signatories[], createdAt, updatedAt.
- DebitCard: id, cardNumber, accountId, status[ACTIVE,BLOCKED], createdAt, updatedAt.
- Credit: id, creditNumber, customerId, type[PERSONAL,BUSINESS,CREDIT_CARD], amount, remainingBalance,
  interestRate, installmentCount, currentInstallment, creditLimit, status[ACTIVE,PAID,OVERDUE,BLOCKED,CANCELLED], createdAt, updatedAt.
- Movement: id, productId, productType[ACCOUNT,CREDIT,CREDIT_CARD],
  movementType[DEPOSIT,WITHDRAWAL,PAYMENT,CARD_CONSUMPTION,TRANSFER], amount, createdAt.
- Wallet: id, phoneNumber, documentNumber, documentType, name, email, imei, balance,
  status[ACTIVE,BLOCKED], createdAt, updatedAt.

## Capas hexagonales (un servicio típico)
- domain/model (entidades y enums), domain/port/input (casos de uso), domain/port/output (puertos).
- application/usecase (implementaciones).
- infrastructure/entrypoints/rest (controllers + DTOs), infrastructure/persistence (adapter/document/repository),
  infrastructure/client (WebClient), infrastructure/messaging (Kafka).

# LO QUE DEBES GENERAR

1. UN "Diagrama de diseño de la solución" (arquitectura de componentes) que muestre:
   consumidores -> gateway -> 5 microservicios -> MongoDB/Redis/Kafka, más config-server, eureka-server y SonarQube.
   Incluye TODAS las flechas de la sección "Comunicación" y "Kafka", y las de registro a Eureka y config a Config Server.

2. DIAGRAMAS DE SECUENCIA (UML) por microservicio:
   - customer-service: (a) crear cliente, (b) obtener cliente por id con cache-aside Redis, (c) marcar deuda vencida -> bloqueo.
   - account-service: (a) crear cuenta validando cliente vía WebClient, (b) depósito/retiro/transferencia,
     (c) pago con tarjeta de débito publicando evento Kafka.
   - credit-service: (a) crear crédito, (b) pago, consumo (solo CREDIT_CARD) y pago de terceros.
   - transaction-service: (a) registrar movimiento vía HTTP, (b) consumir evento Kafka y registrar WITHDRAWAL.
   - yanki-service: (a) crear billetera, (b) transferencia entre billeteras.
   - gateway-service: enrutamiento de una petición (match de ruta -> lb://<servicio> vía Eureka).
   - eureka-server: registro de un servicio y heartbeat.
   - config-server: obtención de configuración al arrancar (spring.config.import).

    En cada secuencia usa participantes reales: Cliente -> Controller -> UseCase -> Port -> Adapter -> Infraestructura,
    con los nombres de endpoints y métodos HTTP exactos, y los códigos de estado (201/200/404/409) y errores de negocio
    (DuplicateCustomerException, CustomerNotFoundException, InsufficientBalanceException, etc.).

3. UN "Diagrama de despliegue (Docker)" que muestre los contenedores y puertos:
   customer-db (mongo:27017), redis-cache (6379), zookeeper (2181), kafka (9092), kafka-ui (8089),
   sonarqube-db (postgres) + sonarqube (9000), y los 8 servicios (eureka 8761, config 8888,
   customer 8081, account 8082, credit 8083, transaction 8084, yanki 8085, gateway 8080),
   todos en la red "financial-network". Indica que los 5 servicios apuntan a customer-db con su propia base.

# ESTILO Y FORMATO
- Idioma: español.
- Convención de flechas: sólida para HTTP síncrono; punteada para Kafka y registro/config.
- Colores: microservicios azul claro, infraestructura gris, base de datos verde (cilindro), cliente amarillo.
- En los diagramas de secuencia usa: barras de activación sobre cada línea de vida,
  self-mensajes como cajas sobre su propia línea de vida, y marcos "alt"/"loop" para las ramas condicionales.
- Salida: XML de draw.io (mxfile válido, un <diagram> por archivo), con nodos y aristas bien separados
  (sin solapes ni nodos fuera de página).
```

---

## Cómo usar el prompt

1. Pega el bloque y pide el formato de salida: **"XML de draw.io (mxfile)"** para abrirlo directamente en draw.io.
2. Puedes pedir "un diagrama por archivo" o "todos en un solo archivo".
3. Si la IA omite algún detalle, pégale de vuelta el bloque de la sección que falte y pídele que lo corrija.

## Verificación rápida del resultado

- ¿Están los 8 servicios y sus puertos correctos?
- ¿El topic es exactamente `debit-card-payments`?
- ¿account-service y credit-service llaman a customer-service y transaction-service vía WebClient?
- ¿Solo customer-service usa Redis?
- ¿Las 5 bases MongoDB comparten una instancia (`customer_db` … `yanki_db`)?
