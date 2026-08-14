# Financial Core — Ecosistema Bancario Reactivo (NTT DATA)

> Documentación técnica integral del proyecto. Explica arquitectura, tecnologías, reglas de negocio, flujos y guía de ejecución de todos los microservicios.

---

## 1. Visión general

Este proyecto implementa el **Core Bancario** de una entidad financiera mediante una arquitectura de **microservicios** con **Database per Service**, **Arquitectura Hexagonal (Ports & Adapters)** y un enfoque **reactivo no bloqueante** (Spring WebFlux + Netty + RxJava 3). El sistema cubre clientes, cuentas, créditos, tarjetas (crédito y débito), movimientos, un monedero móvil, descubrimiento de servicios, configuración centralizada, gateway, resiliencia, caché distribuida, seguridad JWT y mensajería basada en eventos (Kafka).

### Objetivo
Ofrecer una plataforma bancaria distribuida, resiliente y escalable que gestione el ciclo de vida completo de clientes y productos pasivos/activos, con transaccionalidad trazable en un ledger de movimientos y comunicación asíncrona por eventos.

---

## 2. Arquitectura

```
                              ┌────────────────────────────┐
                              │   SPRING CLOUD GATEWAY     │  :8080  (routing + JWT)
                              └──────────────┬─────────────┘
                                             │  lb:// (Eureka)
          ┌──────────────┬──────────────┬────┴─────────┬──────────────┐
          ▼              ▼              ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐
   │  CUSTOMER  │ │  ACCOUNT   │ │   CREDIT   │ │ TRANSACTION│ │   YANKI    │
   │  :8081     │ │  :8082     │ │  :8083     │ │   :8084    │ │   :8085    │
   └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └─────┬──────┘ └────────────┘
         │              │              │              │
         │   REST (WebClient @LoadBalanced + Resilience4j)   │
         │              └──────────────┴──────────────┘
         │
         ├──► MongoDB (Database per Service: customer_db, account_db, ...)
         ├──► Redis  (caché de customer-service)
         └──► Kafka  (eventos de dominio: debit-card-payments)

   ┌──────────────────────────────────────────────────────────────┐
   │  Infraestructura transversal                                  │
   │  • Eureka Server   :8761  (Service Discovery)                │
   │  • Config Server   :8888  (Configuración centralizada)       │
   │  • MongoDB :27017 · Redis :6379 · Kafka :9092 · Zookeeper    │
   │  • SonarQube :9000 · Kafka-UI :8089                          │
   └──────────────────────────────────────────────────────────────┘
```

### Principios de diseño

| Principio | Descripción |
|---|---|
| **Database per Service** | Cada servicio tiene su propia base de datos MongoDB (`customer_db`, `account_db`, `credit_db`, `transaction_db`, `yanki_db`). |
| **Arquitectura Hexagonal** | Separación estricta entre dominio (puro), puertos (input/output) y adaptadores de infraestructura (REST, MongoDB, WebClient, Redis, Kafka). |
| **Reactivo no bloqueante** | Spring WebFlux (Netty) + RxJava 3 (`Single`, `Maybe`, `Flowable`, `Completable`). |
| **Descubrimiento de servicios** | Eureka + Spring Cloud LoadBalancer (`lb://service-name`). |
| **Resiliencia** | Resilience4j (circuit breaker) con timeout estricto de 2s en llamadas entre servicios. |
| **Event-driven** | Kafka para la publicación/consumo de eventos de dominio. |
| **Calidad** | JaCoCo (cobertura ≥ 80%), Checkstyle, SonarQube. |

---

## 3. Inventario de microservicios

| Servicio | Puerto | Base de datos | Rol |
|---|---|---|---|
| `eureka-server` | 8761 | — | Registro de servicios (Service Discovery). |
| `config-server` | 8888 | — | Configuración externalizada (backend native). |
| `gateway-service` | 8080 | — | Punto de entrada único, routing y JWT. |
| `customer-service` | 8081 | `customer_db` | Gestión de clientes (personales/empresariales, perfiles VIP/PYME). |
| `account-service` | 8082 | `account_db` | Cuentas (ahorro, corriente, plazo fijo), depósitos, retiros, transferencias, comisiones, tarjetas de débito. |
| `credit-service` | 8083 | `credit_db` | Créditos (personal, empresarial, TC), pagos, consumos, pago de terceros. |
| `transaction-service` | 8084 | `transaction_db` | Ledger de movimientos + consumidor Kafka de eventos. |
| `yanki-service` | 8085 | `yanki_db` | Monedero móvil (registro independiente + transferencias). |

---

## 4. Stack tecnológico

- **Lenguaje/Runtime:** Java 17 LTS.
- **Framework:** Spring Boot 3.4.2 + Spring WebFlux (Netty).
- **Cloud:** Spring Cloud 2024.0.0 (Netflix Eureka, Config Server, Gateway, LoadBalancer, Circuit Breaker Resilience4j).
- **Reactivo:** RxJava 3 (`rxjava 3.1.10`) + `reactor-adapter` para puentear WebClient/Redis/Kafka.
- **Persistencia:** Spring Data MongoDB Reactive (`RxJava3CrudRepository`).
- **Mensajería:** Spring Kafka (productor/consumidor).
- **Caché:** Spring Data Redis Reactive.
- **Seguridad:** JJWT (0.12.6) — tokens HS256.
- **Mapeo:** MapStruct + Lombok (inmutable).
- **Documentación:** Springdoc OpenAPI (Swagger UI).
- **Calidad:** JUnit 5, Mockito, JaCoCo (≥80%), Checkstyle, SonarQube.
- **Contenerización:** Docker (Dockerfile multi-stage por servicio).

---

## 5. Arquitectura interna de un servicio (hexagonal)

Cada microservicio replica la misma estructura:

```
src/main/java/.../
├── <Service>Application.java          # main
├── domain/
│   ├── model/                          # entidades de dominio puras (Account, Credit, Customer, ...)
│   ├── exception/                      # excepciones de dominio
│   ├── event/                          # eventos de dominio (records)
│   └── port/
│       ├── input/                      # puertos de entrada (UseCase interfaces)
│       └── output/                     # puertos de salida (Persistence, Client, Cache, Publisher)
├── application/
│   └── usecase/                        # implementaciones de los casos de uso (orquestación)
└── infrastructure/
    ├── config/                         # WebClient, Kafka, JWT, etc.
    ├── client/adapter/                 # adaptadores HTTP salientes (WebClient)
    ├── messaging/                      # productor/consumidor Kafka
    ├── entrypoints/rest/               # controllers, DTOs, mappers, GlobalExceptionHandler
    └── persistence/                    # documents, repositories, mappers, adapters Mongo
```

**Reglas clave de la arquitectura:**
- El **dominio** es Java puro (sin dependencias de Spring/Mongo), inmutable, con métodos ricos (`deposit`, `withdraw`, `makePayment`, `consume`, `block`...).
- Los **puertos** son interfaces que definen contratos.
- Los **casos de uso** orquestan puertos de entrada/salida.
- Los **adaptadores** implementan los puertos de salida (Mongo, Redis, WebClient, Kafka).
- La **inyección de dependencias** es por constructor (Lombok `@RequiredArgsConstructor`).

---

## 6. Reglas de negocio por dominio

### 6.1. Customer (`customer-service`)
- Tipos: `PERSONAL` y `BUSINESS`.
- Perfiles: `STANDARD`, `VIP`, `PYME`.
  - **VIP** es exclusivo de clientes PERSONAL (requiere TC activa + saldo promedio).
  - **PYME** es exclusivo de clientes BUSINESS (cuenta corriente sin comisión de mantenimiento + TC activa).
- Estados: `ACTIVE`, `INACTIVE`, `BLOCKED`.
- **Bloqueo por deuda vencida:** al marcarse `hasOverdueDebit=true`, el cliente queda `BLOCKED` y no puede adquirir nuevos productos.
- Unicidad por documento (`documentType` + `documentNumber`).

### 6.2. Account (`account-service`)
- Tipos: `SAVINGS` (ahorro), `CURRENT` (corriente), `FIXED_TERM` (plazo fijo).
- **Límites de tenencia:**
  - Personal: máx. 1 ahorro + 1 corriente; plazo fijo libre.
  - Empresarial: solo corriente (múltiples); sin ahorro ni plazo fijo.
- **Transaccionalidad:** depósito, retiro, transferencia (entre cuentas propias y de terceros).
- **Comisiones:** cada tipo define un límite de transacciones mensuales sin costo; al superarlo se cobra una comisión automática (`transactionCommission`) en retiros/transferencias.
- **Tarjetas de débito:** emitidas y ligadas a una cuenta; el pago debita la cuenta y **publica un evento** `DebitCardPaymentEvent` (event-driven).
- Estados: `ACTIVE`, `BLOCKED`, `INACTIVE`, `CLOSED`.
- Número de cuenta único de 14 dígitos (`191-XXXXXXXXXX`).

### 6.3. Credit (`credit-service`)
- Tipos: `PERSONAL`, `BUSINESS`, `CREDIT_CARD` (TC).
- **Límites de tenencia:**
  - Personal: máx. 1 crédito personal + máx. 1 TC.
  - Empresarial: múltiples empresariales + máx. 1 TC.
- **Autonomía crediticia:** se puede adquirir crédito sin cuenta bancaria activa.
- **Pagos:** amortización (`makePayment`); al saldar la deuda pasa a `PAID`.
- **Consumos TC:** solo en `CREDIT_CARD` activas, hasta el `creditLimit`.
- **Pago de terceros:** un cliente puede pagar el crédito de otro por número de crédito.
- Estados: `ACTIVE`, `PAID`, `OVERDUE`, `BLOCKED`, `CANCELLED`.

### 6.4. Transaction (`transaction-service`)
- **Ledger append-only** de movimientos.
- `ProductType`: `ACCOUNT`, `CREDIT`, `CREDIT_CARD`.
- `MovementType`: `DEPOSIT`, `WITHDRAWAL`, `PAYMENT`, `CARD_CONSUMPTION`, `TRANSFER`.
- Consultas: por producto, últimos N movimientos.
- **Consumidor Kafka:** consume `debit-card-payments` y registra el movimiento (WITHDRAWAL).

### 6.5. Yanki (`yanki-service`)
- **Registro independiente** (no requiere ser cliente bancario): documento (DNI/CEX/Pasaporte), celular, IMEI, correo.
- **Transferencias** entre billeteras identificadas por número de celular.
- Estados: `ACTIVE`, `BLOCKED`.

---

## 7. Comunicación entre servicios

| Origen → Destino | Mecanismo | Detalle |
|---|---|---|
| account/credit → customer | REST (WebClient `@LoadBalanced`) | Validar tipo/perfil/deuda del cliente. |
| account/credit → transaction | REST (WebClient) | Registrar movimiento (depósito, retiro, pago, consumo). |
| account → Kafka → transaction | Evento | `DebitCardPaymentEvent` para pagos con débito. |
| Todos → Eureka | Registro | `lb://<service>` para resolución de nombres. |
| Todos → Config Server | `spring.config.import` | Configuración centralizada (opcional). |

**Tolerancia a fallos:**
- Las llamadas salientes se envuelven en **Resilience4j** (circuit breaker + timeout 2s).
- El registro de movimientos y la publicación de eventos son **best-effort** (no rompen el flujo principal si el destino cae).

---

## 8. Event-Driven (Kafka)

- **Productor:** `account-service` publica `DebitCardPaymentEvent` en el topic `debit-card-payments`.
- **Consumidor:** `transaction-service` escucha el topic y registra el movimiento (WITHDRAWAL) asociado a la cuenta debitada.
- Serialización: JSON (productor `JsonSerializer`, consumidor `StringDeserializer` + ObjectMapper).
- Topology: Zookeeper + Kafka Broker (`:9092`) + Kafka-UI (`:8089`).

---

## 9. Seguridad (JWT)

- `gateway-service` incluye `JwtService` (JJWT, HS256) para generar y validar tokens firmados con expiración.
- El secreto se configura por variable de entorno `JWT_SECRET`.
- La integración con Spring Security (filtro de autorización) queda como extensión futura.

---

## 10. Caché distribuida (Redis)

- `customer-service` aplica **cache-aside** en `findById`:
  1. Consulta Redis (`customer:{id}`).
  2. Si falla, consulta MongoDB.
  3. Almacena el resultado en Redis (best-effort).
- La entidad `Customer` usa `@Jacksonized` para serialización/deserialización JSON.

---

## 11. Resiliencia (Resilience4j)

Configurada en `account-service` y `credit-service` para las llamadas salientes:

- `customer-service` (circuit breaker): sliding window 10, min calls 5, failure rate 50%.
- `transaction-service` (circuit breaker): idem.
- **Timeout estricto de 2s** aplicado con `Mono.timeout` en los WebClient.

---

## 12. Calidad de código (JaCoCo + SonarQube)

### JaCoCo (cobertura)
- Todos los servicios generan el **reporte HTML** en `target/site/jacoco/index.html` al ejecutar `mvn test` (o `mvn verify`).
- **Gate de cobertura ≥ 80%** en los 6 servicios de negocio (verificado en `mvn verify`):
  - account: 87.3% · credit: 87.0% · customer: 85.6% · transaction: 93.9% · yanki: 91.1% · gateway: 100%.
- `eureka-server` y `config-server` generan reporte (servicios de infraestructura, sin gate).

Para ver el reporte en el navegador:
```bash
cd account-service/target/site/jacoco
python3 -m http.server 8080     # luego abre http://localhost:8080
```

### SonarQube
- Configurado en los **8 poms** (`sonar-maven-plugin` + `sonar.host.url`, `sonar.projectKey`, `sonar.coverage.jacoco.xmlReportPaths`).
- El token se pasa por **variable de entorno** `SONAR_TOKEN` (no se commitea).
1. Genera el token: http://localhost:9000 → login `admin`/`admin` → Administration → Security → Users → Tokens → Generate.
2. Exporta el token y ejecuta el análisis de todos los servicios:
```bash
export SONAR_TOKEN=<tu-token>
./scripts/sonar.sh
```
O un servicio individual: `./mvnw sonar:sonar` (usa las propiedades del pom + `SONAR_TOKEN`).

### Checkstyle
- Reglas `google_checks.xml` aplicadas en `validate`.

---

## 13. Guía de ejecución

### 13.1. Prerrequisitos
- **Docker** (para MongoDB, Redis, Kafka, Sonar).
- **JDK 17** (el wrapper `mvnw` lo requiere; usa `~/.jdks/temurin-17.0.20` si el `java` del sistema es otra versión).

```bash
export JAVA_HOME=$HOME/.jdks/temurin-17.0.20
export PATH=$JAVA_HOME/bin:$PATH
java -version   # debe ser 17
```

### 13.2. Levantar infraestructura
```bash
cd bank-infrastructure
docker compose up -d            # Mongo, Redis, Kafka, Zookeeper, Sonar, Kafka-UI
docker ps                      # confirmar healthy
```

### 13.3. Levantar los microservicios (en orden)
```bash
# 1) eureka-server
cd eureka-server && ./mvnw spring-boot:run
# 2) config-server
cd ../config-server && ./mvnw spring-boot:run
# 3) servicios de negocio
cd ../customer-service && ./mvnw spring-boot:run
cd ../account-service && ./mvnw spring-boot:run
cd ../credit-service && ./mvnw spring-boot:run
cd ../transaction-service && ./mvnw spring-boot:run
cd ../yanki-service && ./mvnw spring-boot:run
# 4) gateway
cd ../gateway-service && ./mvnw spring-boot:run
```

### 13.4. Contenerizado (alternativa)
```bash
# primero la infraestructura (arriba), luego los servicios:
cd bank-infrastructure
docker compose -f docker-compose.services.yaml up --build
```

### 13.5. Topic Kafka (opcional, se autocrea)
```bash
docker exec -it kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic debit-card-payments --partitions 1 --replication-factor 1
```

### 13.6. Verificación
- Eureka: http://localhost:8761
- Swagger por servicio: http://localhost:8082/webjars/swagger-ui/index.html (cambiar puerto).
- Health: `curl http://localhost:8080/actuator/health`
- Kafka-UI: http://localhost:8089
- SonarQube: http://localhost:9000

---

## 14. Tests

```bash
# dentro de cada servicio:
./mvnw test      # ejecuta tests unitarios
./mvnw verify    # tests + gate de cobertura JaCoCo (≥80%)
```

Totales actuales: **249 tests** (customer 46, account 87, credit 68, transaction 18, yanki 24, gateway 4, eureka 1, config 1).

---

## 15. Fases del proyecto (todas completadas)

| Fase | Alcance | Estado |
|---|---|---|
| **FASE 0** | Migración a RxJava 3. | ✅ |
| **FASE 1** (Parte I) | CRUD + reglas de límite + depósitos/retiros + consumos TC + transaction-service + config-server + Postman. | ✅ |
| **FASE 2** (Parte II) | Gateway, Resilience4j, VIP/PYME, comisiones + transferencias, reportes, cobertura ≥80%, Dockerfiles, config client. | ✅ |
| **FASE 3** (Parte III) | Kafka + eventos, JWT, Redis, tarjetas de débito, Yanki, pago de terceros + bloqueo por deuda. | ✅ |

---

## 16. Estructura de repositorios

- Un **repositorio git por microservicio** (8) + un repo raíz (`Final_Project_NTT_DATA_Bank`) para infraestructura, Postman, scripts y documentación.
- Cada commit sigue la convención `feature(Clase): ...` / `test(Clase): ...` (commit por clase creada).

```
Final_Project_NTT_DATA_Bank/
├── README.md                  ← este documento
├── PLAN_PROYECTO.md           ← plan general y hoja de ruta
├── bank-infrastructure/       ← docker-compose (infra + servicios)
├── postman/                   ← colección Postman
├── scripts/                   ← export-openapi.sh
├── customer-service/          ← repo git
├── account-service/           ← repo git
├── credit-service/            ← repo git
├── transaction-service/       ← repo git
├── yanki-service/             ← repo git
├── gateway-service/           ← repo git
├── eureka-server/             ← repo git
└── config-server/             ← repo git
```

---

## 17. Variables de entorno útiles

| Variable | Default | Uso |
|---|---|---|
| `EUREKA_SERVER_URL` | `http://localhost:8761/eureka` | Dónde se registra cada servicio. |
| `CONFIG_SERVER_URL` | `http://localhost:8888` | Config Server. |
| `SPRING_DATA_MONGODB_URI` | `mongodb://localhost:27017/<db>` | Conexión a MongoDB. |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Broker Kafka. |
| `REDIS_HOST` / `REDIS_PORT` | `localhost` / `6379` | Redis. |
| `JWT_SECRET` | (definido en gateway) | Secreto de firma JWT. |
