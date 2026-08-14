# Plan de ejecución — Financial Core Bancario (Partes I, II, III)

> Hoja de ruta única y general del proyecto. Consolida el plan maestro y el plan del credit-service. Incluye el análisis de avance, las decisiones adoptadas y las fases de trabajo.

---

## Instrucciones de trabajo (obligatorias)

1. **Commit por cada clase creada**: cada vez que se cree una clase, interfaz, DTO, documento o configuración nueva, se debe hacer un commit inmediato con un mensaje descriptivo (`feature(Clase): creada`, `feature(Clase): actualizada`). No se acumulan cambios sin commitear.
2. **Sin referencias a la entidad bancaria real**: no incluir el acrónimo de la entidad bancaria (3 letras) ni nombres de bancos o marcas reales en ningún artefacto del proyecto — código, comentarios, javadocs, `application.yaml`, `pom.xml`, Docker, colecciones Postman ni documentación — para no disparar alertas de ciberseguridad. Usar términos neutros: *Financial Core*, *Banking*, *Core Engine*.

---

## 1. Análisis de avance

| Parte | Avance | Detalle |
|---|---|---|
| **Parte I** (Core CRUD) | **~100%** | CRUD + reglas + transaction-service + config-server + Postman |
| **Parte II** (Cloud + perfiles) | **~100%** | Gateway, Resilience4j, VIP/PYME, comisiones, transferencias, reportes, cobertura, Dockerfiles, config-server |
| **Parte III** (Event-driven) | **~5%** | Solo contenedores Kafka/Redis sin integrar |
| **Global** | **~70%** | |

### Terminado (Partes I y II)

- **7 microservicios** con repo git propio: `customer-service` (8081), `account-service` (8082), `credit-service` (8083), `transaction-service` (8084), `config-server` (8888), `eureka-server` (8761), `gateway-service` (8080). Además un repo en la raíz para infraestructura, Postman y documentación.
- **FASE 0** — Migración a RxJava3 completa (customer, account, credit).
- **FASE 1** — Cierre de Parte I: límites de cuentas, depósito/retiro, consumos TC, `transaction-service` (ledger best-effort), `config-server`, colección Postman.
- **FASE 2** — Parte II: `gateway-service`, Resilience4j (circuit breaker + timeout 2s), perfiles VIP/PYME, comisiones + transferencias, reportes por rango de fechas, Dockerfiles por servicio, cableado de config-server, **cobertura JaCoCo ≥80%** (account 91%, credit 88.4%, customer 89.6%).
- CRUD REST completo en customer, account y credit. Database-per-service. Java 17, Spring Boot 3.4.2, WebFlux, MongoDB Reactivo, RxJava3, Lombok, MapStruct, DI por constructor, Logback.
- Tests unitarios: **customer 42, account 77, credit 63, transaction 7, config 1, gateway 1**.

### Pendiente (Parte III)

- Kafka + eventos de dominio.
- Seguridad JWT.
- Redis caching.
- Tarjetas de débito + pagos.
- Yanki wallet (monedero móvil).
- Pago de crédito de terceros + bloqueo por deuda vencida.
- Documentación visual: draw.io y diagramas de secuencia (entregables manuales).

---

## 2. Decisiones adoptadas

1. **RxJava3 literal** → `Single`/`Maybe`/`Flowable`/`Completable` en los servicios + tests.
2. **`transaction-service` dedicado** → registrar y consultar movimientos (best-effort).
3. **Cerrar Parte I, luego Parte II, luego Parte III** en ese orden.
4. **Repositorio git por microservicio** + repo de raíz para infra/docs/Postman.
5. **Registro de movimientos best-effort** → no bloquea el flujo principal si transaction-service cae.
6. **Arquitectura Hexagonal (Ports & Adapters)** replicada en cada servicio.

---

## 3. Fases de trabajo

### FASE 0 — Migración a RxJava3 ✅
Dependencias `rxjava` + `reactor-adapter`; repos `RxJava3CrudRepository`; WebClient vía `RxJava3Adapter`; tests con `TestObserver`/`TestSubscriber`.

### FASE 1 — Cerrar Parte I ✅
1. Límites de cuenta (personal máx 1 ahorro + 1 corriente; empresarial sin ahorro/plazo fijo).
2. Depósito/retiro en account-service.
3. Consumos TC en credit-service.
4. `transaction-service` (colección `movements`).
5. `config-server` (backend native).
6. Postman ✅ (draw.io y secuencia pendientes).

### FASE 2 — Parte II ✅
1. Spring Cloud Gateway.
2. Resilience4j (circuit breaker + timeout 2s).
3. Perfiles VIP/PYME.
4. Comisiones + transferencias.
5. Reportes.
6. Cobertura JaCoCo ≥80%.
7. Dockerfiles por servicio.
8. Cablear config-server en clientes.

### FASE 3 — Parte III (pendiente)
1. **Kafka + eventos de dominio** (`YankiTransactionEvent`, `DebitCardPaymentEvent`, `DebtStatusEvent`).
2. **JWT** (Spring Security Reactive).
3. **Redis** (caché reactiva para datos maestros/catálogos).
4. **Tarjetas de débito + pagos**.
5. **Yanki wallet** (registro independiente por DNI/celular/IMEI; transferencias entre cuentas propias y de terceros).
6. **Pago de crédito de terceros + bloqueo por deuda vencida** (flag `hasOverdueDebit` → bloqueo).

---

## 4. Anexo — Arquitectura del credit-service

Paquete `com.nttdata.bootcamp.credit_service` (hexagonal):

```
src/main/java/com/nttdata/bootcamp/credit_service/
├── CreditServiceApplication.java
├── domain/
│   ├── model/            Credit, CreditType, CreditStatus, CustomerType,
│   │                     CustomerProfile, CustomerInfo
│   ├── exception/        CreditLimitExceededException
│   └── port/
│       ├── input/        Create/Get/Update/Delete/Pay/ConsumeCreditUseCase
│       └── output/       CreditPersistencePort, CustomerClientPort, MovementClientPort
├── application/usecase/  ...UseCaseImpl
└── infrastructure/
    ├── config/           WebClientConfig (@LoadBalanced)
    ├── client/adapter/   CustomerWebClientAdapter, MovementWebClientAdapter
    ├── entrypoints/rest/ CreditController + DTOs + GlobalExceptionHandler + CreditRestMapper
    └── persistence/      CreditDocument, CreditPersistenceMapper, CreditMongoAdapter, RxCreditRepository
```

### Reglas de negocio (credit-service)

| Regla | Detalle |
|---|---|
| Productos | Crédito Personal, Crédito Empresarial, Tarjeta de Crédito (TC) |
| Personal | Máx. 1 crédito personal + máx. 1 TC. Sin créditos empresariales |
| Empresarial | Múltiples créditos empresariales + máx. 1 TC. Sin créditos personales |
| Autonomía crediticia | Crédito sin cuenta bancaria activa (no depende de account-service) |
| VIP / PYME | Requieren TC activa (dato consumido de customer-service) |
| Transaccionalidad | Pagos (amortización) y consumos TC → transaction-service |

### Endpoints (`/api/v1/credits`)

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/` | Crear crédito (201) |
| GET | `/{id}` | Obtener por ID |
| GET | `/number/{creditNumber}` | Obtener por número |
| GET | `/customer/{customerId}` | Créditos de un cliente |
| GET | `/customer/{customerId}/report` | Reporte por rango de fechas |
| GET | `/` | Listar todos |
| PUT | `/{id}` | Actualizar |
| POST | `/{id}/payments` | Pagar cuota (amortización) |
| POST | `/{id}/consumptions` | Consumo con TC |
| DELETE | `/{id}` | Eliminar (204) |
