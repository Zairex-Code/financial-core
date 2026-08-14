# Plan de ejecución — Proyecto Bancario (Partes I, II, III)

> Hoja de ruta acordada para completar el Financial Core. Incluye el análisis de avance y las fases de trabajo.

---

## 1. Análisis de avance (estimado)

| Parte | Avance | Detalle |
|---|---|---|
| **Parte I** (Core CRUD) | **~55%** | CRUD completo, falta reglas de negocio + docs + Config Server |
| **Parte II** (Cloud + perfiles) | **~15%** | Solo Eureka y plugins Checkstyle/JaCoCo |
| **Parte III** (Event-driven) | **~5%** | Solo contenedores Kafka/Redis sin integrar |
| **Global** | **~25%** | |

### Terminado
- 4 microservicios corriendo y registrados en Eureka: `customer-service` (8081), `account-service` (8082), `credit-service` (8083), `eureka-server` (8761).
- CRUD REST completo en customer, account y credit.
- Modelos de dominio: cuentas (SAVINGS/CURRENT/FIXED_TERM), créditos (PERSONAL/BUSINESS/CREDIT_CARD), clientes (PERSONAL/BUSINESS + STANDARD/VIP/PYME).
- Reglas de crédito: máx 1 personal, máx 1 TC, múltiples empresariales, pago/amortización, autonomía crediticia.
- Patrón database-per-service. Java 17, Spring Boot 3.4.2, WebFlux, MongoDB Reactivo, Lombok, MapStruct, DI por constructor, Logback.
- Checkstyle + JaCoCo en los 3 servicios. Tests unitarios (18 customer, 18 account, 22 credit).

### Parcial
- Depósitos/retiros: solo métodos de dominio, sin endpoints REST.
- Saldos: sin endpoint dedicado.
- Titulares/firmantes: campos sin validación.
- Cobertura JaCoCo baja: account 32.9%, credit 46.1%, customer 42.7% (requisito ≥80%).
- Git: account/credit/customer tienen repo; eureka-server y bank-infrastructure no.

### Faltante
- **Parte I**: reglas de límite en account-service, consumos TC, movimientos, Config Server, docs (draw.io, secuencia, OpenAPI, Postman).
- **Parte II**: API Gateway, Resilience4j, perfiles VIP/PYME, comisiones, transferencias, reportes, Dockerfiles.
- **Parte III**: Kafka, JWT, Redis, tarjetas de débito, Yanki wallet, pago de terceros, bloqueo por deuda vencida.

---

## 2. Decisiones adoptadas

1. **RxJava3 literal** → migrar `Mono/Flux` (Reactor) a `Single/Flowable/Completable/Maybe` (RxJava3) en los 4 servicios + tests.
2. **`transaction-service` dedicado** → registrar y consultar movimientos.
3. **Cerrar Parte I primero** antes de infraestructura Parte II.

---

## 3. Fases de trabajo

### FASE 0 — Migración a RxJava3 (fundamento)
- Dependencias: `io.reactivex.rxjava3:rxjava`, `io.projectreactor.addons:reactor-adapter`.
- Mapeo de tipos: `Mono<T>` → `Single<T>`/`Maybe<T>`; `Flux<T>` → `Flowable<T>`; `Mono<Void>` → `Completable`.
- Repositorios: `RxJava3CrudRepository` de Spring Data.
- WebClient: adaptar `bodyToMono()` con `RxJava3Adapter`.
- Tests: `StepVerifier` → `TestSubscriber`/`TestObserver`.
- Orden: customer-service (piloto) → account-service → credit-service, verificando `mvn test` en cada uno.

### FASE 1 — Cerrar Parte I
1. Límites de cuenta en `CreateAccountUseCaseImpl`.
2. Endpoints depósito/retiro en account-service.
3. Consumos TC en credit-service.
4. `transaction-service` (puerto 8084): colección `movements`, CRUD + consultas.
5. `config-server` (puerto 8888): propiedades centralizadas.
6. Documentación: draw.io, secuencia, OpenAPI, Postman.

### FASE 2 — Parte II
1. Spring Cloud Gateway.
2. Resilience4j (circuit breaker + timeout 2s).
3. Perfiles VIP/PYME.
4. Comisiones + transferencias.
5. Reportes.
6. Cobertura JaCoCo ≥80%.
7. Dockerfiles por servicio.

### FASE 3 — Parte III
1. Kafka + eventos de dominio.
2. JWT.
3. Redis.
4. Tarjetas de débito + pagos.
5. Yanki wallet.
6. Pago de crédito de terceros + bloqueo por deuda vencida.
