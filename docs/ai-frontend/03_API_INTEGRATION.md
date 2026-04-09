# API Integration

This document lists the backend endpoints used by the current Flutter frontend and shows how they map into provider state and UI workflows.

## Transport and Auth Rules

### `/palletizing-line/*`

- Transport: `ApiClient` with Dio, except for device-key test in `DeviceSettingsScreen`.
- Auth header: `X-Device-Key`.
- Bearer token is explicitly removed for these requests.

### Legacy endpoints

- `/auth/*` and legacy `/palletizing/*` calls use bearer token auth when available.
- These are not wired into the active `main.dart` runtime except for image loading and legacy auth code paths.

## Active Pallettizing-Line Contract

| Endpoint | Method | Frontend caller | Backend concept | Request shape | Parsed response | State / UI impact |
| --- | --- | --- | --- | --- | --- | --- |
| `/palletizing-line/bootstrap` | `GET` | `PalletizingProvider.loadBootstrap()` | `LineStateService` + bootstrap aggregator | none | `BootstrapResponseModel` | hydrates product types, production lines, all line maps |
| `/palletizing-line/bootstrap` | `GET` | `DeviceSettingsScreen._testConnection()` via `HttpClient` | device validation / bootstrap reachability | none | raw JSON success check only | validates device key during setup |
| `/palletizing-line/lines/{lineId}/authorize-pin` | `POST` | `PalletizingProvider.authorizeLineWithPin()` | `LineAuthorizationService` | `{ "pin": "1234" }` | custom parser -> `LineAuthorizationState` | authorizes one line, then line state is refreshed |
| `/palletizing-line/lines/{lineId}/state` | `GET` | `PalletizingProvider._refreshLineStateFromBackend()` | `LineStateService` | none | `BootstrapLineStateModel` | refreshes one line after auth, create pallet, handover, or manual recovery |
| `/palletizing-line/lines/{lineId}/pallets` | `POST` | `PalletizingProvider.createPallet()` | `PalletizingService` | `{ "productTypeId": int, "quantity": int }` | `PalletCreateResponseModel` | creates pallet, opens success/print flow, then refreshes line state |
| `/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts` | `POST` | `PalletizingProvider.logPrintAttempt()` | print-attempt logging inside `PalletizingService` or adjacent backend module | `{ "printerIdentifier": string, "status": "SUCCESS"|"FAILED", "failureReason": string? }` | `PrintAttemptResultModel` | no UI update beyond optional boolean success |
| `/palletizing-line/lines/{lineId}/select-product` | `POST` | `PalletizingProvider.selectProductOnLine()` | `LineStateService` / product selection logic | `{ "productTypeId": int }` | `BootstrapLineStateModel` | first product assignment on a line |
| `/palletizing-line/lines/{lineId}/product-switch` | `POST` | `PalletizingProvider.switchProduct()` | `PalletizingService` | `{ "previousProductTypeId": int, "newProductTypeId": int, "loosePackageCount": int }` | `BootstrapLineStateModel` | records loose balance and moves line to new product |
| `/palletizing-line/lines/{lineId}/handover` | `POST` | `PalletizingProvider.createLineHandover()` | `LineHandoverService` | optional `{ "lastActiveProductTypeId": int, "lastActiveProductFaletQuantity": int, "notes": string }` | `LineHandoverInfoModel` | creates pending handover and transitions line state |
| `/palletizing-line/lines/{lineId}/handover/pending` | `GET` | `PalletizingProvider.getLineHandover()` during bootstrap/refresh | `LineHandoverService` | none | `LineHandoverInfoModel?` | upgrades summary handover data into full review detail when available |
| `/palletizing-line/lines/{lineId}/handover/{handoverId}/confirm` | `POST` | `PalletizingProvider.confirmLineHandover()` | `LineHandoverService` | empty body | `LineHandoverInfoModel` | resolves handover, clears pending state, refreshes line |
| `/palletizing-line/lines/{lineId}/handover/{handoverId}/reject` | `POST` | `PalletizingProvider.rejectLineHandover()` | `LineHandoverService` | optional `{ "notes": string }` | `LineHandoverInfoModel` | rejects handover, clears pending state, refreshes line |
| `/palletizing-line/lines/{lineId}/falet` | `GET` | `PalletizingProvider.fetchFaletItems()` | `FaletService` | none | `FaletResponseModel` | loads open FALET items for one line |
| `/palletizing-line/lines/{lineId}/falet/convert-to-pallet` | `POST` | `PalletizingProvider.convertFaletToPallet()` | `FaletService` + `PalletizingService` | `{ "faletId": int, "additionalFreshQuantity": int }` | `FaletConvertToPalletResponseModel` | creates pallet from FALET, refreshes FALET list and line state |
| `/palletizing-line/lines/{lineId}/falet/dispose` | `POST` | `PalletizingProvider.disposeFalet()` | `FaletService` | `{ "faletId": int, "reason": string? }` | `FaletDisposeResponseModel` | disposes FALET item, refreshes FALET list and line state |
| `/palletizing-line/lines/{lineId}/session-production-detail` | `GET` | `PalletizingProvider.fetchSessionProductionDetail()` | session summary / reporting backend concept | none | `SessionProductionDetailModel` | feeds session drilldown dialog and reprint workflow |

## Legacy or Adjacent Endpoints

These are present in the repo but not part of the active app entry flow.

| Endpoint | Method | Frontend caller | Status |
| --- | --- | --- | --- |
| `/auth/login` | `POST` | `AuthRepositoryImpl.login()` | legacy/unwired |
| `/auth/pin-login` | `POST` | `AuthRepositoryImpl.pinLogin()` | legacy/unwired |
| `/palletizing/operators` | `GET` | `PalletizingRepositoryImpl.getOperators()` | legacy/unused in active contract |
| `/palletizing/product-types` | `GET` | `PalletizingRepositoryImpl.getProductTypes()` | legacy/unused in active contract |
| `/palletizing/production-lines` | `GET` | `PalletizingRepositoryImpl.getProductionLines()` | legacy/unused in active contract |

## Request / Response Notes

### Bootstrap

- Response parser expects `json['data']` to contain:
  - `productTypes`
  - `productionLines`
  - `lines`
- `BootstrapLineStateModel` maps backend `authorized` into `isAuthorized`.
- Authorization data is expected inside nested `authorization`.

### Product selection and switching

- Both `/select-product` and `/product-switch` return a `BootstrapLineState`-shaped payload, not a minimal success response.
- This lets the provider immediately rehydrate line state from the action response.

### Handover detail loading

- The provider assumes bootstrap and `/state` may only contain condensed handover data.
- When `lineUiMode == PENDING_HANDOVER_REVIEW`, it performs an additional `/handover/pending` fetch for full detail.
- Current `LineHandoverInfo` entity only exposes `faletItems` and related metadata. Comments mentioning `incompletePallet` or `looseBalances` are a `stale comment` relative to current entity definitions.

### Print attempt logging

- Logging happens after local socket printing, not before.
- The parsed DTO expects `palleteId` from JSON, not `palletId`. This may be an intentional backend spelling or a fragile parser assumption.

## Error Handling

- All Dio request failures are normalized through `ApiClient._handleDioException()`.
- Application-level backend errors are parsed from:
  - `success == false`
  - or `error` object in a bad HTTP response
- UI-facing Arabic messages come from `ApiException.displayMessage`.

### Notable error-driven flows

- `PRODUCT_ALREADY_SELECTED`: provider refreshes line state instead of trusting the local choice.
- `CURRENT_PRODUCT_MISMATCH` / `NO_CURRENT_PRODUCT`: provider refreshes stale line state.
- `LINE_NOT_AUTHORIZED`: session drilldown auto-closes and shows snackbar.

## Retry and Recovery Behavior

- No automatic exponential retry exists.
- Recovery patterns are manual or action-specific:
  - global retry button after bootstrap failure
  - pull-to-refresh
  - stale-state refresh on selected product errors
  - rerunning print after local failure

## Model Mapping Summary

- JSON parsing classes live in `lib/data/models/*`.
- Most active palletizing endpoints map into domain entities directly through DTO models.
- See [05_MODELS.md](./05_MODELS.md) for field-level mapping details.

## Backend Service Concept Mapping

The frontend does not contain classes named after backend services, but the current endpoint groups map cleanly to these backend concepts:

| Backend concept | Frontend endpoint group |
| --- | --- |
| `LineAuthorizationService` | `/authorize-pin` |
| `LineStateService` | `/bootstrap`, `/state`, product-selection state payloads |
| `PalletizingService` | `/pallets`, `/product-switch`, `/print-attempts` |
| `FaletService` | `/falet`, `/falet/convert-to-pallet`, `/falet/dispose` |
| `LineHandoverService` | `/handover`, `/handover/pending`, `/handover/{id}/confirm`, `/handover/{id}/reject` |

## Related Screens

- [DeviceSettingsScreen](./screens/DeviceSettingsScreen.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [FaletScreen](./screens/FaletScreen.md)
- [PalletSuccessDialog](./screens/PalletSuccessDialog.md)

## Related Services

- `ApiClient`
- `PalletizingRepositoryImpl`
- `PalletizingProvider`
- `PrintingProvider`

## Related Backend Concepts

- `LineAuthorizationService`
- `LineStateService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
