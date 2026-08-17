# Financial Core — Ecosistema Bancario Reactivo (NTT DATA)

> **Documento maestro del proyecto.** Guía integral y detallada para entender cómo funciona, qué componentes lo conforman, cómo se comunican, cómo se construyó y cómo se pone en marcha. Pensada como material de estudio y soporte para la exposición.

---

## Tabla de contenido

1. [Visión general](#1-visión-general)
2. [El problema que resuelve](#2-el-problema-que-resuelve)
3. [Arquitectura general](#3-arquitectura-general)
4. [Inventario de componentes](#4-inventario-de-componentes)
5. [Stack tecnológico](#5-stack-tecnológico)
6. [Patrones y principios de diseño](#6-patrones-y-principios-de-diseño)
7. [Arquitectura interna (hexagonal)](#7-arquitectura-interna-hexagonal)
8. [Modelo de programación reactiva (RxJava 3)](#8-modelo-de-programación-reactiva-rxjava-3)
9. [Reglas de negocio por dominio](#9-reglas-de-negocio-por-dominio)
10. [Cómo se comunican los servicios](#10-cómo-se-comunican-los-servicios)
11. [Flujos end-to-end de ejemplo](#11-flujos-end-to-end-de-ejemplo)
12. [Event-Driven (Kafka)](#12-event-driven-kafka)
13. [Seguridad (JWT)](#13-seguridad-jwt)
14. [Caché distribuida (Redis)](#14-caché-distribuida-redis)
15. [Resiliencia (Resilience4j)](#15-resiliencia-resilience4j)
16. [Service Discovery (Eureka)](#16-service-discovery-eureka)
17. [Configuración centralizada (Config Server)](#17-configuración-centralizada-config-server)
18. [API Gateway](#18-api-gateway)
19. [Persistencia (MongoDB database-per-service)](#19-persistencia-mongodb-database-per-service)
20. [Calidad de código (JaCoCo + SonarQube + Checkstyle)](#20-calidad-de-código-jacoco--sonarqube--checkstyle)
21. [Contenerización (Docker)](#21-contenedorización-docker)
22. [Documentación de API (OpenAPI + Postman)](#22-documentación-de-api-openapi--postman)
23. [Paso a paso: cómo encender el proyecto](#23-paso-a-paso-cómo-encender-el-proyecto)
24. [Pruebas](#24-pruebas)
25. [Fases del proyecto](#25-fases-del-proyecto)
26. [Estructura de repositorios](#26-estructura-de-repositorios)
27. [Variables de entorno](#27-variables-de-entorno)
28. [Comandos útiles y troubleshooting](#28-comandos-útiles-y-troubleshooting)
29. [Glosario](#29-glosario)

---

## 1. Visión general

Este proyecto implementa el **Core Bancario** de una entidad financiera mediante una arquitectura de **microservicios** con **Database per Service**, **Arquitectura Hexagonal (Ports & Adapters)** y un enfoque **reactivo no bloqueante** (Spring WebFlux + Netty + RxJava 3).

Cubre el ciclo de vida completo de los productos financieros:
- **Clientes** (personales y empresariales, con perfiles VIP/PYME).
- **Cuentas bancarias** (ahorro, corriente y plazo fijo).
- **Créditos** (personal, empresarial y tarjeta de crédito).
- **Tarjetas de débito**.
- **Movimientos** (ledger de transacciones).
- **Monedero móvil (Yanki)**.

Todo ello soportado por una infraestructura transversal de **descubrimiento de servicios** (Eureka), **configuración centralizada** (Config Server), **API Gateway**, **resiliencia** (Resilience4j), **caché distribuida** (Redis), **seguridad** (JWT) y **mensajería por eventos** (Kafka).

### Objetivos
1. Ofrecer una plataforma bancaria **distribuida, resiliente y escalable**.
2. Aplicar **buenas prácticas de arquitectura limpia** (hexagonal, puertos/adaptadores).
3. Garantizar **calidad** medible (cobertura de pruebas ≥ 80%, análisis estático con SonarQube).
4. Demostrar un enfoque **event-driven** para las operaciones asíncronas.

---

## 2. El problema que resuelve

Un banco necesita gestionar de forma **desacoplada** sus distintos productos y procesos:

| Dominio | Necesidad |
|---|---|
| Clientes | Registrar personas y empresas, asignar perfiles comerciales, controlar deudas vencidas. |
| Cuentas | Ahorro, corriente y plazo fijo, con límites de tenencia por cliente, depósitos, retiros, transferencias y comisiones. |
| Créditos | Préstamos y tarjetas de crédito con límites, amortización y consumos. |
| Movimientos | Registrar **todas** las operaciones monetarias en un ledger auditable. |
| Monedero | Permitir transferencias rápidas entre celulares sin ser necesariamente cliente bancario. |

La solución debe:
- Escalar cada dominio por separado (un equipo, un servicio, una base de datos).
- Resistir fallos (si un servicio cae, los demás siguen operando).
- Mantener trazabilidad de cada transacción.
- Comunicar cambios de forma asíncrona (eventos).

---

## 3. Arquitectura general

```
                              ┌──────────────────────────────┐
                              │     SPRING CLOUD GATEWAY     │  :8080
                              │  Routing central + JWT       │
                              └──────────────┬───────────────┘
                                             │  lb://service-name  (via Eureka)
       ┌──────────────┬──────────────┬───────┴───────┬──────────────┬──────────────┐
       ▼              ▼              ▼               ▼              ▼              ▼
┌────────────┐ ┌────────────┐ ┌────────────┐  ┌────────────┐ ┌────────────┐ ┌────────────┐
│  CUSTOMER  │ │  ACCOUNT   │ │   CREDIT   │  │TRANSACTION │ │   YANKI    │ │  DEBIT     │
│  :8081     │ │  :8082     │ │  :8083     │  │   :8084    │ │   :8085    │ │  CARDS*    │
└─────┬──────┘ └─────┬──────┘ └─────┬──────┘  └─────┬──────┘ └────────────┘ └────────────┘
      │              │              │                │               (* dentro de account-service)
      │              └──── REST (WebClient @LoadBalanced + Resilience4j) ─┘
      │
      ├──► MongoDB  (database per service)
      │      customer_db / account_db / credit_db / transaction_db / yanki_db
      ├──► Redis    (caché de customer-service)
      └──► Kafka    (eventos de dominio: debit-card-payments)

┌────────────────────────────────────────────────────────────────────────┐
│  INFRAESTRUCTURA TRANSVERSAL                                           │
│  • Eureka Server  :8761   → Service Discovery                          │
│  • Config Server  :8888   → Configuración externalizada                │
│  • MongoDB :27017 · Redis :6379 · Kafka :9092 · Zookeeper :2181        │
│  • Kafka-UI :8089 · SonarQube :9000                                    │
└────────────────────────────────────────────────────────────────────────┘
```

### Flujo de una petición
1. El cliente llama al **Gateway** (`:8080`).
2. El Gateway resuelve el nombre lógico (`lb://account-service`) usando **Eureka** y enruta.
3. El servicio destino ejecuta su **caso de uso** (hexagonal) y responde.
4. Si la operación es monetaria, el servicio registra el movimiento (REST a `transaction-service`) y/o **publica un evento** (Kafka).

---

## 4. Inventario de componentes

### 4.1 Microservicios de negocio

| Servicio | Puerto | Base de datos | Responsabilidad |
|---|---|---|---|
| `customer-service` | 8081 | `customer_db` | Alta/baja/consulta de clientes personales y empresariales; perfiles VIP/PYME; bloqueo por deuda vencida. |
| `account-service` | 8082 | `account_db` | Cuentas (ahorro/corriente/plazo fijo), depósitos, retiros, transferencias, comisiones y tarjetas de débito. |
| `credit-service` | 8083 | `credit_db` | Créditos personales/empresariales/tarjeta de crédito, pagos, consumos y pago de terceros. |
| `transaction-service` | 8084 | `transaction_db` | Ledger de movimientos (append-only) + consumidor Kafka de eventos de débito. |
| `yanki-service` | 8085 | `yanki_db` | Monedero móvil: registro independiente y transferencias entre billeteras. |

### 4.2 Microservicios de infraestructura

| Servicio | Puerto | Responsabilidad |
|---|---|---|
| `eureka-server` | 8761 | Registro central de servicios (Service Discovery). |
| `config-server` | 8888 | Configuración centralizada externalizada (backend nativo). |
| `gateway-service` | 8080 | Punto único de entrada, enrutamiento y JWT. |

### 4.3 Infraestructura de datos/mensajería (Docker)

| Componente | Puerto | Imagen | Rol |
|---|---|---|---|
| MongoDB | 27017 | `mongo:7.0` | Base de datos NoSQL (una BD por servicio). |
| Redis | 6379 | `redis:7.2-alpine` | Caché distribuida. |
| Kafka | 9092 | `confluentinc/cp-kafka:7.5.0` | Broker de mensajería. |
| Zookeeper | 2181 | `confluentinc/cp-zookeeper:7.5.0` | Coordinador de Kafka. |
| Kafka-UI | 8089 | `provectuslabs/kafka-ui` | UI para inspeccionar topics/eventos. |
| SonarQube | 9000 | `sonarqube:10.3-community` | Análisis estático de calidad. |
| Postgres | (interno) | `postgres:15-alpine` | Base de datos interna de SonarQube. |

---

## 5. Stack tecnológico

| Capa | Tecnología | Versión |
|---|---|---|
| Lenguaje | Java | 17 LTS |
| Framework | Spring Boot | 3.4.2 |
| Web reactivo | Spring WebFlux + Netty | — |
| Cloud | Spring Cloud | 2024.0.0 |
| Reactivo | RxJava 3 (`io.reactivex.rxjava3`) | 3.1.10 |
| Puente Reactor↔RxJava | `reactor-adapter` | gestionado por Boot |
| Persistencia | Spring Data MongoDB Reactive | — |
| Mensajería | Spring Kafka | gestionado por Boot |
| Caché | Spring Data Redis Reactive | — |
| Descubrimiento | Netflix Eureka Client/Server | 2024.0.0 |
| Config | Spring Cloud Config | 2024.0.0 |
| Gateway | Spring Cloud Gateway | 2024.0.0 |
| Resiliencia | Spring Cloud Circuit Breaker (Resilience4j) | 2024.0.0 |
| Seguridad | JJWT | 0.12.6 |
| Mapeo | MapStruct | 1.5.5.Final |
| Boilerplate | Lombok | 1.18.36 |
| Documentación | Springdoc OpenAPI | 2.8.5 |
| Testing | JUnit 5, Mockito, reactor-test | — |
| Cobertura | JaCoCo | 0.8.11 |
| Análisis estático | Checkstyle (google_checks) · SonarQube | 3.3.1 · 10.3 |
| Contenedores | Docker | — |

---

## 6. Patrones y principios de diseño

| Patrón/Principio | Aplicación en el proyecto |
|---|---|
| **Microservicios** | Cada dominio (cliente, cuenta, crédito, movimiento, monedero) es un servicio independiente. |
| **Database per Service** | Cada microservicio posee su propia base MongoDB; no comparten tablas. |
| **Arquitectura Hexagonal (Ports & Adapters)** | Dominio puro en el centro; puertos (interfaces) y adaptadores (infraestructura) en la periferia. |
| **DDD (táctico)** | Entidades inmutables con métodos ricos (`Account.deposit()`, `Credit.makePayment()`). |
| **CQRS-lite** | Lecturas (Get*UseCase) separadas de escrituras (Create/Update/Delete/Transacción). |
| **Event-Driven** | Operaciones asíncronas comunicadas mediante eventos en Kafka. |
| **SAGA (compensación parcial)** | Registro best-effort de movimientos/eventos: no se rompe el flujo principal si el destino falla. |
| **Inyección por constructor** | Dependencias finales vía Lombok `@RequiredArgsConstructor`. |
| **Fail-fast** | Validaciones de entrada antes de tocar red o base de datos. |

---

## 7. Arquitectura interna (hexagonal)

Cada microservicio replica la misma estructura de paquetes:

```
src/main/java/com/nttdata/bootcamp/<service>/
├── <Service>Application.java            # punto de entrada
├── domain/
│   ├── model/                            # entidades puras: Account, Credit, Customer, Movement, Wallet, DebitCard
│   ├── exception/                        # excepciones de dominio (InsufficientBalanceException, ...)
│   ├── event/                            # eventos de dominio (records): DebitCardPaymentEvent
│   └── port/
│       ├── input/                        # puertos de entrada (casos de uso): CreateAccountUseCase, ...
│       └── output/                       # puertos de salida: AccountPersistencePort, CustomerClientPort, ...
├── application/
│   └── usecase/                          # implementaciones de casos de uso (orquestación)
└── infrastructure/
    ├── config/                           # WebClientConfig (@LoadBalanced), KafkaConfig, JwtConfig
    ├── client/adapter/                   # adaptadores HTTP salientes (CustomerWebClientAdapter, ...)
    ├── messaging/                        # KafkaDomainEventPublisher / DebitCardPaymentEventConsumer
    ├── entrypoints/rest/                 # controllers, DTOs, mappers, GlobalExceptionHandler
    └── persistence/                      # documents, repositories (RxJava3CrudRepository), mappers, adapters Mongo
```

**Flujo interno de una operación (ej. "crear cuenta"):**
1. `AccountController` recibe la petición HTTP y mapea el DTO a dominio.
2. Invoca `CreateAccountUseCaseImpl` (puerto de entrada).
3. El caso de uso llama a `CustomerClientPort` (vía WebClient) para validar el cliente.
4. Aplica las reglas de límite de tenencia.
5. Persiste vía `AccountPersistencePort` (adaptador MongoDB).
6. Devuelve la entidad; el controller la mapea a `AccountResponseDto`.

**Ventajas:** el dominio no depende de Spring/Mongo/WebFlux → es **testeable**, **portable** y **fácil de cambiar** (se puede reemplazar MongoDB por otra BD sin tocar el dominio).

---

## 8. Modelo de programación reactiva (RxJava 3)

Los servicios **no bloquean** hilos: usan flujos reactivos.

| Tipo RxJava 3 | Equivalente Reactor | Uso en el proyecto |
|---|---|---|
| `Single<T>` | `Mono<T>` | Una respuesta esperada (crear, actualizar, depositar…). |
| `Maybe<T>` | `Mono<T>` (0 o 1) | Consultas que pueden no encontrar nada (`findById`). |
| `Flowable<T>` | `Flux<T>` | Listas/streams (listar cuentas, movimientos…). |
| `Completable` | `Mono<Void>` | Operaciones sin valor (borrar, registrar movimiento). |

**Integración con Spring Data:** se usa `RxJava3CrudRepository` (de Spring Data Commons), que expone `Single/Maybe/Flowable`.

**Puente con Reactor:** WebClient (Reactor), Spring Data Redis y Spring Kafka devuelven `Mono/Flux`; se convierten a RxJava con `RxJava3Adapter` (`monoToSingle`, `monoToMaybe`, `monoToCompletable`).

**Tests reactivos:** `TestObserver` (para Single/Maybe/Completable) y `TestSubscriber` (para Flowable).

---

## 9. Reglas de negocio por dominio

### 9.1 Customer (`customer-service`)
- **Tipos:** `PERSONAL`, `BUSINESS`.
- **Perfiles:** `STANDARD`, `VIP`, `PYME`.
  - `VIP` → exclusivo de PERSONAL (requiere tarjeta de crédito activa + saldo promedio).
  - `PYME` → exclusivo de BUSINESS (cuenta corriente sin comisión + TC activa).
- **Estados:** `ACTIVE`, `INACTIVE`, `BLOCKED`.
- **Bloqueo por deuda vencida:** endpoint `POST /{id}/overdue` marca `hasOverdueDebit=true` y bloquea al cliente. Un cliente bloqueado **no puede** adquirir cuentas ni créditos.
- **Unicidad:** no puede haber dos clientes con el mismo `documentType` + `documentNumber`.

### 9.2 Account (`account-service`)
- **Tipos:** `SAVINGS`, `CURRENT`, `FIXED_TERM`.
- **Límites de tenencia:**
  - Personal: máx. 1 ahorro + 1 corriente; plazo fijo libre.
  - Empresarial: solo corriente (múltiples); **no** ahorro ni plazo fijo.
- **Transacciones:** depósito, retiro, transferencia (propias y de terceros).
- **Comisiones:** cada tipo define `maxMonthlyTransactions` (transacciones sin costo) y `transactionCommission` (cargo por superar el límite).
  - Ahorro: 5 libres/mes · Corriente: ilimitadas · Plazo fijo: 1.
- **Tarjeta de débito:** ligada a una cuenta; el pago debita la cuenta y publica `DebitCardPaymentEvent`.
- Número de cuenta único de 14 dígitos (`191-XXXXXXXXXX`).

### 9.3 Credit (`credit-service`)
- **Tipos:** `PERSONAL`, `BUSINESS`, `CREDIT_CARD`.
- **Límites de tenencia:**
  - Personal: máx. 1 personal + 1 TC.
  - Empresarial: múltiples empresariales + 1 TC.
- **Autonomía crediticia:** crédito sin cuenta bancaria activa.
- **Pago (amortización):** reduce saldo y avanza cuota; saldo 0 → `PAID`.
- **Consumo TC:** solo en `CREDIT_CARD` activa, hasta `creditLimit`.
- **Pago de terceros:** por número de crédito, con `payerCustomerId`.
- **Estados:** `ACTIVE`, `PAID`, `OVERDUE`, `BLOCKED`, `CANCELLED`.

### 9.4 Transaction (`transaction-service`)
- Ledger **append-only** (no se edita ni borra).
- `ProductType`: `ACCOUNT`, `CREDIT`, `CREDIT_CARD`.
- `MovementType`: `DEPOSIT`, `WITHDRAWAL`, `PAYMENT`, `CARD_CONSUMPTION`, `TRANSFER`.
- Consultas: por producto, últimos N movimientos.
- **Consumidor Kafka:** convierte `DebitCardPaymentEvent` en un movimiento `WITHDRAWAL`.

### 9.5 Yanki (`yanki-service`)
- **Registro independiente:** documento (DNI/CEX/Pasaporte), celular, IMEI, correo. **No** requiere ser cliente bancario.
- **Transferencias** entre billeteras identificadas por celular.
- Estados: `ACTIVE`, `BLOCKED`.

---

## 10. Cómo se comunican los servicios

| Origen → Destino | Mecanismo | Detalle |
|---|---|---|
| account/credit → customer | REST (WebClient `@LoadBalanced`) | Validar tipo/perfil/deuda del cliente (`GET /api/v1/customers/{id}`). |
| account/credit → transaction | REST (WebClient) | Registrar movimiento (`POST /api/v1/movements`). |
| account → Kafka → transaction | Evento | `debit-card-payments` (pago con débito). |
| Todos → Eureka | Registro/heartbeat | `lb://<service>` resuelve a la IP/puerto real. |
| Todos → Config Server | `spring.config.import` | Configuración externalizada (opcional). |
| Cliente externo → servicios | Vía Gateway | Punto único de entrada (`:8080`). |

**Configuración del WebClient** (en `WebClientConfig`):
```java
@Bean
@LoadBalanced
public WebClient.Builder webClientBuilder() { ... }
```
`@LoadBalanced` habilita la resolución de `http://<service-name>` a través de Eureka + LoadBalancer.

**Tolerancia a fallos:** las llamadas salientes se envuelven en **Resilience4j** (circuit breaker + timeout 2s), y el registro de movimientos/eventos es **best-effort** (`onErrorComplete`).

---

## 11. Flujos end-to-end de ejemplo

### 11.1 Depósito (síncrono)
```
POST /api/v1/accounts/{id}/deposits (Gateway → account-service)
  1. account-service valida la cuenta (findById).
  2. account.deposit(amount)  → aumenta balance y contador.
  3. Persiste la cuenta.
  4. Registra el movimiento vía REST → transaction-service (Movement: DEPOSIT).
  5. Responde con la cuenta actualizada.
```

### 11.2 Pago con tarjeta de débito (event-driven)
```
POST /api/v1/debit-cards/{id}/payments (Gateway → account-service)
  1. Valida la tarjeta (ACTIVE) y la cuenta.
  2. account.withdraw(amount) → debita la cuenta.
  3. Persiste la cuenta.
  4. Publica DebitCardPaymentEvent en Kafka (topic debit-card-payments).
  5. transaction-service CONSUME el evento y registra el movimiento WITHDRAWAL.
```

### 11.3 Bloqueo por deuda vencida (cross-service)
```
POST /api/v1/customers/{id}/overdue (customer-service)
  → hasOverdueDebit=true + status=BLOCKED.
Luego, si se intenta crear cuenta/crédito para ese cliente:
  account/credit consultan customer-service y RECHAZAN ("overdue debit").
```

---

## 12. Event-Driven (Kafka)

- **Productor:** `account-service` (`KafkaDomainEventPublisher` envuelve `KafkaTemplate`).
- **Evento:** `DebitCardPaymentEvent { accountId, cardId, amount, timestamp }` (record inmutable).
- **Topic:** `debit-card-payments`.
- **Consumidor:** `transaction-service` (`DebitCardPaymentEventConsumer` con `@KafkaListener`).
- **Serialización:** productor `JsonSerializer`; consumidor `StringDeserializer` + `ObjectMapper`.
- **Config productor** (`application.yaml`):
```yaml
spring:
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP_SERVERS:localhost:9092}
    producer:
      value-serializer: org.springframework.kafka.support.serializer.JsonSerializer
```
- **Config consumidor:**
```yaml
spring:
  kafka:
    consumer:
      group-id: transaction-service
      auto-offset-reset: earliest
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
```

---

## 13. Seguridad (JWT)

- `gateway-service` incluye `JwtService` (JJWT, HS256).
- Genera tokens firmados con expiración; valida firma y extrae `subject`.
- Secreto configurable por variable de entorno `JWT_SECRET`.
- La integración con un filtro de Spring Security (proteger rutas) es la **extensión natural** de esta pieza.

---

## 14. Caché distribuida (Redis)

`customer-service` aplica el patrón **cache-aside** en `findById`:

1. Consulta Redis (`customer:{id}`).
2. Si falla (miss) → consulta MongoDB.
3. Guarda el resultado en Redis (best-effort).
4. Devuelve el cliente.

- La entidad `Customer` usa `@Jacksonized` para serializar/deserializar JSON sin configuración manual.
- Si Redis está caído, el servicio sigue funcionando leyendo de MongoDB (degradación elegante).

---

## 15. Resiliencia (Resilience4j)

Configurada en `account-service` y `credit-service` para las llamadas HTTP salientes:

```yaml
resilience4j:
  circuitbreaker:
    instances:
      customer-service:
        sliding-window-size: 10
        minimum-number-of-calls: 5
        failure-rate-threshold: 50
        wait-duration-in-open-state: 10s
      transaction-service:
        sliding-window-size: 10
        minimum-number-of-calls: 5
        failure-rate-threshold: 50
        wait-duration-in-open-state: 10s
```

- **Timeout estricto de 2s** aplicado con `Mono.timeout(Duration.ofSeconds(2))`.
- El `ReactiveCircuitBreaker` envuelve la llamada y aplica el fallback (devuelve vacío/error controlado) sin romper el flujo.

---

## 16. Service Discovery (Eureka)

- `eureka-server` registra todos los servicios.
- Cada servicio es `eureka-client` (se registra y consulta el registro).
- El `@LoadBalanced WebClient` resuelve `http://<service-name>` → IP:puerto real.
- Dashboard: `http://localhost:8761`.

---

## 17. Configuración centralizada (Config Server)

- `config-server` usa el backend **nativo** (sirve `src/main/resources/config/<service>.yaml`).
- Los clientes lo importan de forma **opcional** (no bloquea el arranque si cae):
```yaml
spring:
  config:
    import: optional:configserver:${CONFIG_SERVER_URL:http://localhost:8888}
```
- Configuraciones disponibles: `customer`, `account`, `credit`, `transaction`, `yanki`.

---

## 18. API Gateway

- Único punto de entrada (`:8080`), routing por ruta hacia `lb://<service>`.

| Ruta | Destino |
|---|---|
| `/api/v1/customers/**` | customer-service |
| `/api/v1/accounts/**` | account-service |
| `/api/v1/debit-cards/**` | account-service |
| `/api/v1/credits/**` | credit-service |
| `/api/v1/movements/**` | transaction-service |
| `/api/v1/wallets/**` | yanki-service |

---

## 19. Persistencia (MongoDB database-per-service)

- Una **base de datos por servicio**: `customer_db`, `account_db`, `credit_db`, `transaction_db`, `yanki_db` (todas en una sola instancia MongoDB local, separadas por nombre).
- Documentos (`@Document`) desacoplados del dominio mediante mappers MapStruct.
- Repositorios reactivos `RxJava3CrudRepository` + consultas derivadas (`findByCustomerId`, `findByCustomerIdAndCreatedAtBetween`, etc.).
- Índices únicos para números de cuenta/crédito/teléfono.

---

## 20. Calidad de código (JaCoCo + SonarQube + Checkstyle)

### JaCoCo (cobertura)
- Todos los servicios generan reporte HTML en `target/site/jacoco/index.html` al ejecutar `mvn test` o `mvn verify`.
- **Gate ≥ 80%** en los servicios de negocio (se valida en `mvn verify`):

| Servicio | Cobertura |
|---|---|
| account-service | 87.3% |
| credit-service | 87.0% |
| customer-service | 85.6% |
| transaction-service | 93.9% |
| yanki-service | 91.1% |
| gateway-service | 100% |

### SonarQube
- `sonar-maven-plugin` configurado en los 8 poms (host, projectKey y ruta del reporte XML de JaCoCo).
- Token por variable de entorno `SONAR_TOKEN`.
```bash
export SONAR_TOKEN=<token>
./scripts/sonar.sh          # analiza los 8 servicios
```

### Checkstyle
- Reglas `google_checks.xml` ejecutadas en la fase `validate`.

---

## 21. Contenedorización (Docker)

- Cada microservicio tiene un **Dockerfile multi-stage** (build con `maven:3.9-eclipse-temurin-17`, runtime con `eclipse-temurin:17-jre`).
- La infraestructura se levanta con `bank-infrastructure/docker-compose.yaml`.
- Los microservicios se orquestan con `bank-infrastructure/docker-compose.services.yaml`.

---

## 22. Documentación de API (OpenAPI + Postman)

- **Swagger UI** por servicio: `http://localhost:<puerto>/webjars/swagger-ui/index.html`.
- **OpenAPI crudo:** `http://localhost:<puerto>/v3/api-docs`.
- **Exportar specs:** `./scripts/export-openapi.sh` (genera `docs/openapi/*.yaml`).
- **Postman:** colección completa en `postman/Financial_Core.postman_collection.json`. Usa el Gateway como única URL base (`{{baseUrl}} = http://localhost:8080`) e incluye todos los endpoints (clientes, cuentas, débito, créditos, movimientos y Yanki). Importa la colección, llena las variables (`customerId`, `accountId`, `creditId`, `creditNumber`, `debitCardId`, `walletPhone`) y ejecuta los flujos.
- **Datos de demostración:** `./scripts/seed.sh` crea clientes, cuentas, créditos, movimientos, tarjeta de débito y billeteras de ejemplo.

---

## 23. Paso a paso: cómo encender el proyecto

> **Atajo (recomendado):** `./scripts/start-all.sh` levanta infraestructura + los 8 servicios en orden y espera a que estén sanos. Para apagar: `./scripts/stop-all.sh` (o `--infra` para bajar también Docker). Los pasos 23.2–23.5 siguientes son la versión manual.

### 23.1 Prerrequisitos
- **Docker** instalado y corriendo.
- **JDK 17** (el wrapper `mvnw` lo requiere).

```bash
export JAVA_HOME=$HOME/.jdks/temurin-17.0.20
export PATH=$JAVA_HOME/bin:$PATH
java -version   # debe mostrar 17
```

### 23.2 Levantar la infraestructura (Docker)
```bash
cd ~/Desktop/Dylan_Projects/Final_Project_NTT_DATA_Bank/bank-infrastructure
docker compose up -d
docker ps    # confirmar: customer-db, redis-cache, kafka, zookeeper, sonarqube, kafka-ui
```

### 23.3 Crear el topic de Kafka
```bash
docker exec kafka kafka-topics --bootstrap-server localhost:9092 \
  --create --topic debit-card-payments --partitions 1 --replication-factor 1
```

### 23.4 Arrancar los microservicios (en orden)
Abrir una terminal por servicio (o lanzarlos en background):

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

### 23.5 Verificar
```bash
# Eureka (servicios registrados)
curl -s http://localhost:8761/eureka/apps | grep -o '<name>[^<]*</name>'

# Health de cada servicio
for p in 8080 8081 8082 8083 8084 8085; do
  echo -n "$p -> "; curl -s -o /dev/null -w "%{http_code}\n" http://localhost:$p/actuator/health
done
```

### 23.6 Datos de demostración (seed)
```bash
./scripts/seed.sh          # crea clientes, cuentas, créditos, movimientos, débito y billeteras
```

### 23.7 Alternativa contenerizada
```bash
cd bank-infrastructure
docker compose -f docker-compose.services.yaml up --build
```

---

## 24. Pruebas

```bash
# dentro de cada servicio:
./mvnw test       # ejecuta los tests unitarios
./mvnw verify     # tests + gate de cobertura JaCoCo (≥80%)
```

**Totales: 249 tests**

| Servicio | Tests |
|---|---|
| customer-service | 46 |
| account-service | 87 |
| credit-service | 68 |
| transaction-service | 18 |
| yanki-service | 24 |
| gateway-service | 4 |
| eureka-server | 1 |
| config-server | 1 |

---

## 25. Fases del proyecto (todas completadas)

| Fase | Alcance | Estado |
|---|---|---|
| **FASE 0** | Migración de Reactor (Mono/Flux) a RxJava 3 (Single/Maybe/Flowable/Completable). | ✅ |
| **FASE 1** (Parte I) | CRUD completo + reglas de límite + depósitos/retiros + consumos TC + transaction-service + config-server + Postman. | ✅ |
| **FASE 2** (Parte II) | Gateway, Resilience4j, perfiles VIP/PYME, comisiones + transferencias, reportes, cobertura ≥80%, Dockerfiles, config client. | ✅ |
| **FASE 3** (Parte III) | Kafka + eventos, JWT, Redis, tarjetas de débito, Yanki, pago de terceros + bloqueo por deuda. | ✅ |

---

## 26. Estructura de repositorios

```
Final_Project_NTT_DATA_Bank/
├── README.md                  ← este documento maestro
├── PLAN_PROYECTO.md           ← hoja de ruta y convenciones
├── bank-infrastructure/       ← docker-compose (infra + servicios)
├── postman/                   ← colección Postman
├── scripts/                   ← start-all.sh, stop-all.sh, seed.sh, sonar.sh, export-openapi.sh
├── customer-service/          ← repo git propio
├── account-service/           ← repo git propio
├── credit-service/            ← repo git propio
├── transaction-service/       ← repo git propio
├── yanki-service/             ← repo git propio
├── gateway-service/           ← repo git propio
├── eureka-server/             ← repo git propio
└── config-server/             ← repo git propio
```

Cada microservicio tiene su propio repositorio git, y la raíz tiene otro repo para infraestructura/documentación/scripts.

---

## 27. Variables de entorno

| Variable | Default | Uso |
|---|---|---|
| `EUREKA_SERVER_URL` | `http://localhost:8761/eureka` | Dónde se registra cada servicio. |
| `CONFIG_SERVER_URL` | `http://localhost:8888` | Config Server. |
| `SPRING_DATA_MONGODB_URI` | `mongodb://localhost:27017/<db>` | Conexión a MongoDB. |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Broker Kafka. |
| `REDIS_HOST` / `REDIS_PORT` | `localhost` / `6379` | Redis. |
| `JWT_SECRET` | (en gateway) | Secreto de firma JWT. |
| `SONAR_TOKEN` | — | Token para análisis SonarQube. |

---

## 28. Comandos útiles y troubleshooting

| Situación | Comando |
|---|---|
| Ver cobertura en el navegador | `cd account-service/target/site/jacoco && python3 -m http.server 8080` |
| Ver contenedores | `docker ps` |
| Ver logs de un servicio | `tail -f /tmp/opencode/<servicio>.log` |
| Detener un servicio | `kill $(ss -tlnp \| grep :8082 \| grep -o 'pid=[0-9]*' \| cut -d= -f2)` |
| Recrear infraestructura | `cd bank-infrastructure && docker compose down && docker compose up -d` |
| Analizar con SonarQube | `export SONAR_TOKEN=<token> && ./scripts/sonar.sh` |
| Exportar OpenAPI | `./scripts/export-openapi.sh` |
| Listar topics Kafka | `docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list` |

---

## 29. Glosario

- **Hexagonal (Ports & Adapters):** arquitectura que aísla el dominio del framework y la infraestructura.
- **Database per Service:** cada microservicio tiene su propia base de datos.
- **Reactive / no bloqueante:** modelo en el que los hilos no esperan I/O; se usan flujos.
- **Circuit Breaker:** patrón que "abre" el circuito ante fallos repetidos para no saturar el servicio caído.
- **Cache-aside:** patrón de caché en el que la app consulta caché primero y luego la BD.
- **Event-driven:** comunicación asíncrona mediante eventos publicados/consumidos en un broker.
- **Ledger:** registro inmutable (append-only) de movimientos.
- **Best-effort:** operación auxiliar que no debe romper el flujo principal si falla.
- **JWT (JSON Web Token):** token firmado para autenticación sin estado.
- **Topic:** canal lógico en Kafka donde se publican/consumen eventos.
