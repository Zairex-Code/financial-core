# Especificación de diagramas — Financial Core (NTT DATA)

Documento de referencia para dibujar cada diagrama en **draw.io**. Contiene, para cada uno, el
propósito, los **participantes**, los **mensajes/relaciones** y las **etiquetas exactas**.
Los nombres de servicios, puertos, endpoints y topics son los reales del código.

---

## Convenciones generales

| Elemento | Convención |
|---|---|
| **Microservicios** | Rectángulo redondeado, fondo azul claro (`#dae8fc`), borde azul (`#6c8ebf`), texto con nombre y puerto. |
| **Infraestructura** | Rectángulo, fondo gris (`#f5f5f5`), borde gris (`#666666`). |
| **Base de datos / almacenamiento** | Cilindro (shape `cylinder3` en draw.io), fondo verde claro (`#d5e8d4`). |
| **Consumidor / cliente** | Actor (stick figure) o rectángulo amarillo (`#fff2cc`). |
| **Mensaje síncrono (HTTP/REST)** | Flecha sólida `→`, etiqueta `MÉTODO /ruta`. |
| **Mensaje asíncrono (Kafka/evento)** | Flecha punteada `⇢`, etiqueta `[topic]`. |
| **Registro/descubrimiento (Eureka)** | Flecha punteada fina `⇢`, etiqueta `registro / heartbeat`. |
| **Configuración (Config Server)** | Flecha punteada fina, etiqueta `spring.config.import`. |
| **Llamada interna entre servicios (WebClient)** | Flecha sólida `→`, etiqueta `GET/POST http://<servicio>...`. |

Colores de línea de vida (sequence diagrams): un color por servicio, texto en español.

---

## 1. Diseño de la solución (arquitectura)

**Archivo:** `mermaid/00-diseno-solucion.mmd` · `drawio/00-diseno-solucion.drawio`

**Propósito:** vista global del ecosistema: clientes → gateway → microservicios → almacenamiento, con las
dependencias transversales (Eureka, Config Server, SonarQube) y la comunicación entre servicios.

**Grupos (swimlanes / contenedores):**

1. **Consumidores** — `Postman / Swagger / Frontend`.
2. **API Gateway** — `gateway-service (:8080)`.
3. **Microservicios de negocio** (WebFlux + RxJava3, hexagonal):
   - `customer-service (:8081)`
   - `account-service (:8082)`
   - `credit-service (:8083)`
   - `transaction-service (:8084)`
   - `yanki-service (:8085)`
4. **Transversal**:
   - `config-server (:8888)`
   - `eureka-server (:8761)`
   - `sonarqube (:9000)` + `sonarqube-db (PostgreSQL)`
5. **Almacenamiento / mensajería**:
   - `MongoDB (:27017)` — una única instancia con 5 bases: `customer_db`, `account_db`, `credit_db`, `transaction_db`, `yanki_db`.
   - `Redis (:6379)` — solo customer-service (cache-aside).
   - `Kafka + Zookeeper (:9092 · :2181)` — topic `debit-card-payments`.
   - `kafka-ui (:8089)`.

**Relaciones (etiquetas exactas):**

| Origen | Destino | Tipo | Etiqueta |
|---|---|---|---|
| Consumidor | gateway | HTTP | — |
| gateway | customer-service | routing | `/api/v1/customers/**` |
| gateway | account-service | routing | `/api/v1/accounts/**` y `/api/v1/debit-cards/**` |
| gateway | credit-service | routing | `/api/v1/credits/**` |
| gateway | transaction-service | routing | `/api/v1/movements/**` |
| gateway | yanki-service | routing | `/api/v1/wallets/**` |
| account-service | customer-service | WebClient | `GET /api/v1/customers/{id}` (validar cliente) |
| account-service | transaction-service | WebClient | `POST /api/v1/movements` (registrar movimiento) |
| credit-service | customer-service | WebClient | `GET /api/v1/customers/{id}` (validar cliente) |
| credit-service | transaction-service | WebClient | `POST /api/v1/movements` (registrar movimiento) |
| account-service | Kafka | producer | `debit-card-payments` |
| Kafka | transaction-service | consumer | `debit-card-payments` (registra `WITHDRAWAL`) |
| kafka-ui | Kafka | observabilidad | — |
| cada microservicio (5) | MongoDB | persistencia | base correspondiente |
| customer-service | Redis | cache | `customer:{id}` |
| todos los servicios | eureka-server | registro | `registro / heartbeat` |
| todos los servicios | config-server | config | `spring.config.import` |
| SonarQube | SonarQube-DB | persistencia | — |

---

## 2. Diagramas de secuencia por microservicio

Cada secuencia usa los participantes reales (controlador → caso de uso → puerto → adaptador → infraestructura).
Nota de capas: los casos de uso y puertos son la **lógica hexagonal**; los adaptadores son la infraestructura.

### 2.1 customer-service (`01-customer-service`)

**Secuencia A — Crear cliente**
- Participantes: `Cliente` → `CustomerController` → `CreateCustomerUseCaseImpl` → `CustomerPersistencePort` → `CustomerMongoAdapter` → `MongoDB`.
- Flujo: `POST /api/v1/customers` → `existsByDocument` (verifica DNI único) → si no existe, `Customer.created(...)` (fija profile STANDARD, status ACTIVE, hasOverdueDebit=false, timestamps) → `save` → 201.
- Caso de error: DNI duplicado → `409 DuplicateCustomerException`.

**Secuencia B — Obtener cliente por id (cache-aside)**
- Participantes: `Cliente` → `CustomerController` → `GetCustomerUseCaseImpl` → `CustomerCachePort` (Redis) / `CustomerPersistencePort` (Mongo).
- Flujo: `GET /api/v1/customers/{id}` → `cache.get(id)` → si hit, retorna; si miss → `findById` (Mongo) → `cache.put(id, customer)` → retorna.
- Caso de error: no encontrado → `404 CustomerNotFoundException`.

**Secuencia C — Marcar deuda vencida (overdue)**
- Participantes: `Cliente` → `CustomerController` → `MarkCustomerOverdueUseCaseImpl` → `CustomerPersistencePort` → `MongoDB`, y `CustomerCachePort` (evict).
- Flujo: `POST /api/v1/customers/{id}/overdue` → `findById` → `updateOverdueDebitStatus(true).block()` → `save` → `cache.evict(id)` → 200 con `status=BLOCKED, hasOverdueDebit=true`.

### 2.2 account-service (`02-account-service`)

**Secuencia A — Crear cuenta**
- Participantes: `Cliente` → `AccountController` → `CreateAccountUseCaseImpl` → `CustomerClientPort` → `CustomerWebClientAdapter` → `customer-service`; y `AccountPersistencePort` → `MongoDB`.
- Flujo: `POST /api/v1/accounts` → WebClient `GET http://customer-service/api/v1/customers/{id}` → valida reglas:
  - 1 cuenta SAVINGS por cliente personal.
  - 1 cuenta CURRENT por cliente.
  - rechazo si `hasOverdueDebit=true` (cliente bloqueado).
  - VIP/PYME permite + tarjetas de débito adicionales.
  → si ok, `save` → 201.
- Errores: `409` (límite de tenencia / cliente bloqueado), `404` (cliente no existe).

**Secuencia B — Depósito / retiro / transferencia**
- Participantes: `Cliente` → `AccountController` → `DepositAccountUseCaseImpl`/`WithdrawAccountUseCaseImpl`/`TransferAccountUseCaseImpl` → `AccountPersistencePort` (Mongo) y `MovementClientPort` → `MovementWebClientAdapter` → `transaction-service`.
- Flujo depósito: `POST /api/v1/accounts/{id}/deposits` → `account.deposit(amount)` → `save` → WebClient `POST http://transaction-service/api/v1/movements` (`DEPOSIT`) → 200.
- Retiro: `withdraw` aplica comisión si excede `maxMonthlyTransactions`; error `InsufficientBalanceException` si saldo insuficiente.
- Transferencia: `POST /api/v1/accounts/{id}/transfers` con `destinationAccountId` y `amount`.

**Secuencia C — Pago con tarjeta de débito (Kafka)**
- Participantes: `Cliente` → `DebitCardController` → `PayWithDebitCardUseCaseImpl` → `AccountPersistencePort` (debita) y `DomainEventPublisher` → `KafkaDomainEventPublisher` → `Kafka` → `transaction-service`.
- Flujo: `POST /api/v1/debit-cards/{id}/payments` → debita la cuenta → publica evento `debit-card-payments` (`DebitCardPaymentEvent{accountId, cardId, amount, timestamp}`) → (asíncrono) transaction-service registra `Movement` `WITHDRAWAL`.

### 2.3 credit-service (`03-credit-service`)

**Secuencia A — Crear crédito**
- Participantes: `Cliente` → `CreditController` → `CreateCreditUseCaseImpl` → `CustomerClientPort` → `customer-service`; y `CreditPersistencePort` → `MongoDB`.
- Flujo: `POST /api/v1/credits` → valida cliente (tipo, perfil, `hasOverdueDebit`):
  - `CREDIT_CARD` requiere `creditLimit`.
  - `PERSONAL` no puede crear `BUSINESS`.
  → `save` → 201.
- Errores: `409` (cliente bloqueado / regla de tipo), `404`.

**Secuencia B — Pago / consumo / pago de terceros**
- Participantes: `Cliente` → `CreditController` → `PayCreditUseCaseImpl`/`ConsumeCreditUseCaseImpl`/`ThirdPartyPaymentUseCaseImpl` → `CreditPersistencePort` (Mongo) y `MovementClientPort` → `transaction-service`.
- Pago: `POST /api/v1/credits/{id}/payments` → `makePayment` → `save` → WebClient `POST /movements` (`PAYMENT`).
- Consumo (solo `CREDIT_CARD`): `POST /api/v1/credits/{id}/consumptions` → `consume` → `save` → `POST /movements` (`CARD_CONSUMPTION`). Error `409` si no es tarjeta de crédito.
- Pago de terceros: `POST /api/v1/credits/number/{creditNumber}/third-party-payments` → `POST /movements`.

### 2.4 transaction-service (`04-transaction-service`)

**Secuencia A — Registrar movimiento (HTTP)**
- Participantes: `Origen (account/credit-service)` → `MovementController` → `RecordMovementUseCase` → `MovementPersistencePort` → `MongoDB`.
- Flujo: `POST /api/v1/movements` con `{productId, productType, movementType, amount}` → `save` → 201.

**Secuencia B — Consumir evento Kafka**
- Participantes: `Kafka` → `DebitCardPaymentEventConsumer` (@KafkaListener `debit-card-payments`) → `RecordMovementUseCase` → `MongoDB`.
- Flujo: consume `DebitCardPaymentEvent` → construye `Movement` `WITHDRAWAL` sobre `ProductType.ACCOUNT` → `save`.

### 2.5 yanki-service (`05-yanki-service`)

**Secuencia A — Crear billetera**
- Participantes: `Cliente` → `WalletController` → `CreateWalletUseCase` → `WalletPersistencePort` → `MongoDB`.
- Flujo: `POST /api/v1/wallets` → valida teléfono único → `save` → 201.

**Secuencia B — Transferencia entre billeteras**
- Participantes: `Cliente` → `WalletController` → `TransferWalletUseCase` → `WalletPersistencePort` → `MongoDB`.
- Flujo: `POST /api/v1/wallets/transfers` con `sourcePhoneNumber`, `destinationPhoneNumber`, `amount` → debita origen, acredita destino → 200. Error si saldo insuficiente.

### 2.6 gateway-service (`06-gateway-service`)

**Secuencia — Enrutamiento**
- Participantes: `Cliente` → `Spring Cloud Gateway (gateway-service :8080)` → `Eureka` → `servicio destino`.
- Flujo: `GET/POST /api/v1/<recurso>/**` → match de ruta (tabla de 6 rutas) → resuelve `lb://<servicio>` vía Eureka → reenvía al microservicio → respuesta de vuelta.
- Nota: tiene `JwtService` (HS256) como utilería, pero el filtro de validación JWT **no está cableado** (no aplicar en el diagrama como paso de seguridad).

### 2.7 eureka-server (`07-eureka-server`)

**Secuencia — Registro y heartbeat**
- Participantes: `microservicio (cliente Eureka)` → `eureka-server (:8761)`.
- Flujo: al arrancar, `register-with-eureka` → `POST /eureka/apps/<service>` → 204; cada 30s envía `heartbeat` (`PUT /eureka/apps/<service>/<instance>`). El gateway y los servicios resuelven `lb://<service>` consultando el registro.

### 2.8 config-server (`08-config-server`)

**Secuencia — Obtención de configuración**
- Participantes: `microservicio (cliente config)` → `config-server (:8888, perfil native)`.
- Flujo: al arrancar, `spring.config.import: optional:configserver:http://localhost:8888` → `GET /<service>/default` → devuelve config centralizada (puerto, nombre, MongoDB, Eureka). Si el servidor no responde, cae a la config local (`application.yaml`).

---

## 3. Leyenda y notas de dominio (para no equivocarse)

- **Hexagonal**: domain (modelo + puertos input/output) / application (casos de uso) / infrastructure (entrypoints REST, adaptadores de persistencia/cliente/mensajería).
- **Enums**: `CustomerType{PERSONAL,BUSINESS}`, `CustomerProfile{STANDARD,VIP,PYME}`, `CustomerStatus{ACTIVE,INACTIVE,BLOCKED}`, `AccountType{SAVINGS,CURRENT,FIXED_TERM}`, `AccountStatus{ACTIVE,BLOCKED,INACTIVE,CLOSED}`, `CreditType{PERSONAL,BUSINESS,CREDIT_CARD}`, `CreditStatus{ACTIVE,PAID,OVERDUE,BLOCKED,CANCELLED}`, `ProductType{ACCOUNT,CREDIT,CREDIT_CARD}`, `MovementType{DEPOSIT,WITHDRAWAL,PAYMENT,CARD_CONSUMPTION,TRANSFER}`, `WalletStatus{ACTIVE,BLOCKED}`, `DebitCardStatus{ACTIVE,BLOCKED}`.
- **Kafka**: único topic `debit-card-payments`. Producer = account-service; consumer = transaction-service (`groupId=transaction-service`).
- **Redis**: solo customer-service, clave `customer:{id}`, cache-aside con `get/put/evict`.
- **WebClient**: account-service y credit-service llaman a customer-service (`GET /customers/{id}`) y a transaction-service (`POST /movements`), resueltos por Eureka (`http://<nombre>`).
