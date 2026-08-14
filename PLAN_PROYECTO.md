# Plan de ejecución — Proyecto Bancario (Partes I, II, III)

> Hoja de ruta acordada para completar el Financial Core. Incluye el análisis de avance y las fases de trabajo.

---

## Instrucciones de trabajo (obligatorias)

1. **Commit por cada clase creada**: cada vez que se cree una clase, interfaz, DTO, documento o configuración nueva, se debe hacer un commit inmediato con un mensaje descriptivo (`feature(Clase): creada`, `feature(Clase): actualizada`). No se acumulan cambios sin commitear.
2. **Sin referencias a la entidad bancaria real**: no incluir el acrónimo de la entidad bancaria (3 letras) ni nombres de bancos o marcas reales en ningún artefacto del proyecto — código, comentarios, javadocs, `application.yaml`, `pom.xml`, Docker, colecciones Postman ni documentación — para no disparar alertas de ciberseguridad. Usar términos neutros: *Financial Core*, *Banking*, *Core Engine*.

---

## 1. Análisis de avance (estimado)

| Parte | Avance | Detalle |
|---|---|---|
| **Parte I** (Core CRUD) | **~100%** | CRUD + reglas de negocio + transaction-service + config-server + Postman |
| **Parte II** (Cloud + perfiles) | **~15%** | Solo Eureka y plugins Checkstyle/JaCoCo |
| **Parte III** (Event-driven) | **~5%** | Solo contenedores Kafka/Redis sin integrar |
| **Global** | **~40%** | |

### Terminado
- **6 microservicios** con repo git propio: `customer-service` (8081), `account-service` (8082), `credit-service` (8083), `transaction-service` (8084), `config-server` (8888), `eureka-server` (8761). Además un repo en la raíz para infraestructura, Postman y documentación.
- **FASE 0 — Migración a RxJava3** completa en customer, account y credit (`Single`/`Maybe`/`Flowable`/`Completable`, repos `RxJava3CrudRepository`, WebClient vía `RxJava3Adapter`, tests con `TestObserver`/`TestSubscriber`).
- **FASE 1 — Cierre de Parte I** completa:
  - Reglas de límite de cuentas (personal máx 1 ahorro + 1 corriente; empresarial sin ahorro/plazo fijo).
  - Endpoints de depósito/retiro (`POST /{id}/deposits`, `POST /{id}/withdrawals`).
  - Consumos de TC (`POST /{id}/consumptions` + `Credit.consume`).
  - `transaction-service` (ledger de movimientos, best-effort).
  - Registro de movimientos conectado: deposit/withdraw/pay/consume → `transaction-service`.
  - `config-server` (backend native) + configs centralizadas por servicio.
  - Colección Postman en `postman/Financial_Core.postman_collection.json`.
- CRUD REST completo en customer, account y credit.
- Patrón database-per-service. Java 17, Spring Boot 3.4.2, WebFlux, MongoDB Reactivo, Lombok, MapStruct, DI por constructor, Logback.
- Checkstyle + JaCoCo en los 3 servicios. Tests unitarios: **customer 18, account 27, credit 27, transaction 7, config 1**.

### Parcial / Pendiente
- **Config Server sin cablear en clientes**: los servicios aún leen su `application.yaml` local; falta `spring-cloud-config-client` + `spring.config.import` en cada uno.
- **Documentación visual**: draw.io, diagramas de secuencia.
- **Parte II**: API Gateway, Resilience4j, perfiles VIP/PYME, comisiones, transferencias, reportes, Dockerfiles, cobertura JaCoCo ≥80% (hoy account 32.9%, credit 46.1%, customer 42.7%).
- **Parte III**: Kafka, JWT, Redis, tarjetas de débito, Yanki wallet, pago de terceros, bloqueo por deuda vencida.

---

## 2. Decisiones adoptadas

1. **RxJava3 literal** → migrar `Mono/Flux` (Reactor) a `Single/Flowable/Completable/Maybe` (RxJava3) en los servicios + tests.
2. **`transaction-service` dedicado** → registrar y consultar movimientos (best-effort: no bloquea el flujo principal si cae).
3. **Cerrar Parte I primero** antes de infraestructura Parte II.
4. **Repositorio git por microservicio** + repo de raíz para infra/docs/Postman.

---

## 3. Fases de trabajo

### FASE 0 — Migración a RxJava3 ✅ COMPLETADA
- Dependencias: `io.reactivex.rxjava3:rxjava`, `io.projectreactor.addons:reactor-adapter`.
- Mapeo de tipos: `Mono<T>` → `Single<T>`/`Maybe<T>`; `Flux<T>` → `Flowable<T>`; `Mono<Void>` → `Completable`.
- Repositorios: `RxJava3CrudRepository` de Spring Data.
- WebClient: adaptar `bodyToMono()` con `RxJava3Adapter`.
- Tests: `StepVerifier` → `TestSubscriber`/`TestObserver`.

### FASE 1 — Cerrar Parte I ✅ COMPLETADA
1. Límites de cuenta en `CreateAccountUseCaseImpl`.
2. Endpoints depósito/retiro en account-service.
3. Consumos TC en credit-service.
4. `transaction-service` (puerto 8084): colección `movements`.
5. `config-server` (puerto 8888): propiedades centralizadas.
6. Documentación: Postman ✅ (draw.io y secuencia pendientes).

### FASE 2 — Parte II ✅ COMPLETADA
1. Spring Cloud Gateway (routing central a los microservicios).
2. Resilience4j (circuit breaker + timeout 2s).
3. Perfiles VIP/PYME.
4. Comisiones + transferencias.
5. Reportes.
6. Cobertura JaCoCo ≥80%.
7. Dockerfiles por servicio.
8. Cablear `config-server` en los clientes (`spring.config.import`).

### FASE 3 — Parte III (pendiente)
1. Kafka + eventos de dominio.
2. JWT.
3. Redis.
4. Tarjetas de débito + pagos.
5. Yanki wallet.
6. Pago de crédito de terceros + bloqueo por deuda vencida.
