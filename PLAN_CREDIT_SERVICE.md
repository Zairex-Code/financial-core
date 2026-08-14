# Plan de implementación — credit-service

> Plan de construcción del microservicio de créditos para el Financial Core (NTT DATA).

## Instrucciones de trabajo (obligatorias)

1. **Commit por cada clase creada**: commit inmediato con mensaje descriptivo (`feature(Clase): creada`) por cada clase, interfaz, DTO, documento o configuración nueva.
2. **Sin referencias a la entidad bancaria real**: no incluir el acrónimo de la entidad bancaria (3 letras) ni nombres de bancos/marcas reales en ningún artefacto (código, comentarios, configs, Docker, Postman, docs). Usar términos neutros: *Financial Core*, *Banking*, *Core Engine*.

## 1. Objetivo

Implementar `credit-service` replicando la arquitectura hexagonal (Ports & Adapters) de `account-service`, con los productos **Crédito Personal**, **Crédito Empresarial** y **Tarjeta de Crédito (TC)**.

## 2. Reglas de negocio

| Regla | Detalle |
|---|---|
| Productos | Crédito Personal, Crédito Empresarial, Tarjeta de Crédito (TC) |
| Cliente Personal | Máx. **1 crédito personal** + máx. **1 TC**. No créditos empresariales |
| Cliente Empresarial | **Múltiples créditos empresariales** + máx. **1 TC**. No créditos personales |
| Autonomía crediticia | El cliente puede adquirir crédito **sin cuenta bancaria activa** (no depende de account-service) |
| VIP / PYME | Requieren TC activa (dato consumido por customer-service) |
| Transaccionalidad | Pagos de crédito (amortización) ✅ | consumos TC ✅ → transaction-service |

## 3. Arquitectura (paquete `com.nttdata.bootcamp.credit_service`)

```
src/main/java/com/nttdata/bootcamp/credit_service/
├── CreditServiceApplication.java
├── domain/
│   ├── model/            Credit, CreditType, CreditStatus, CustomerType,
│   │                     CustomerProfile, CustomerInfo
│   ├── exception/        CreditLimitExceededException
│   └── port/
│       ├── input/        CreateCreditUseCase, GetCreditUseCase, UpdateCreditUseCase,
│       │                 DeleteCreditUseCase, PayCreditUseCase
│       └── output/       CreditPersistencePort, CustomerClientPort
├── application/usecase/  Create/Get/Update/Delete/PayCreditUseCaseImpl
└── infrastructure/
    ├── config/           WebClientConfig (@LoadBalanced)
    ├── client/adapter/   CustomerWebClientAdapter
    ├── entrypoints/rest/ CreditController, CreditRequestDto, CreditResponseDto,
    │                     PaymentRequestDto, ErrorResponseDto, GlobalExceptionHandler,
    │                     CreditRestMapper
    └── persistence/      CreditDocument, CreditPersistenceMapper, CreditMongoAdapter,
                          ReactiveCreditRepository
```

## 4. Reglas de límite (en `CreateCreditUseCaseImpl`)

- **PERSONAL:** máx 1 `PERSONAL` + máx 1 `CREDIT_CARD`; rechaza `BUSINESS`.
- **BUSINESS:** múltiples `BUSINESS` + máx 1 `CREDIT_CARD`; rechaza `PERSONAL`.
- Validación de cliente vía `CustomerClientPort.getById` (customer-service).

## 5. Endpoints REST (`/api/v1/credits`)

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/` | Crear crédito (201) |
| GET | `/{id}` | Obtener por ID |
| GET | `/number/{creditNumber}` | Obtener por número |
| GET | `/customer/{customerId}` | Créditos de un cliente |
| GET | `/` | Listar todos |
| PUT | `/{id}` | Actualizar |
| POST | `/{id}/payments` | Pagar cuota (amortización) |
| DELETE | `/{id}` | Eliminar (204) |

## 6. Tests unitarios

`CreateCreditUseCaseImplTest`, `GetCreditUseCaseImplTest`, `UpdateCreditUseCaseImplTest`, `DeleteCreditUseCaseImplTest`, `PayCreditUseCaseImplTest` (Mockito + StepVerifier).

## 7. Verificación

1. `mvn test` → todo en verde.
2. Levantar con Eureka → `CREDIT-SERVICE` registrado en 8083.
3. Smoke test: crear cliente → crear crédito personal (2º debe fallar por límite) → pago de cuota.
