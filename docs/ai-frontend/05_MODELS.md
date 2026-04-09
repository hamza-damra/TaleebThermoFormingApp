# Models and DTO Mapping

This document summarizes the main frontend entities, the DTO/model classes that populate them, and the most important field meanings.

## 1. Bootstrap and Line State

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `BootstrapResponse` | `BootstrapResponseModel` | `productTypes`, `productionLines`, `lines` | main app bootstrap payload |
| `BootstrapLineState` | `BootstrapLineStateModel` | `lineId`, `lineNumber`, `lineName`, `isAuthorized`, `authorizedOperator`, `sessionTable`, `pendingHandover`, `selectedProductType`, `lineUiMode`, handover flags, FALET flags | core per-line payload used in bootstrap and line refresh |
| `LineAuthorizationState` | custom parser inside repository | `lineId`, `lineNumber`, `operator`, `authorizedAt`, `isAuthorizing`, `authError` | auth request does not use a separate DTO class |

### Important mapping notes

- Backend field `authorized` is mapped into frontend `isAuthorized`.
- Authorization details are read from nested `authorization`.
- Current-product fallback:
  - if `selectedProductType` object exists, it is parsed fully
  - else if only `currentProductTypeId/currentProductTypeName` exist, frontend constructs a minimal `ProductTypeModel`

## 2. Product Types and Lines

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `ProductType` | `ProductTypeModel` | `id`, `name`, `productName`, `prefix`, `color`, `packageQuantity`, `packageUnitDisplayName`, `imageUrl`, `description` | used heavily in product selection and pallet creation |
| `ProductionLine` | `ProductionLineModel` | `id`, `name`, `code`, `lineNumber` | backend line entity |
| frontend `ProductionLine` enum | none | `line1`, `line2`, color, label, number | UI-only wrapper for fixed two-line shell |

### Important field meanings

- `ProductType.compactLabel` is computed as `productName + packageQuantity`.
- `ProductType.formatCompactName()` strips text after `/` for cleaner UI display.
- `imageUrl` is expected to be a relative API path, not a full absolute URL.

## 3. Pallet Creation and Printing

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `PalletCreateResponse` | `PalletCreateResponseModel` | `palletId`, `scannedValue`, `operator`, `productType`, `productionLine`, `quantity`, `createdAtDisplay` | returned by create pallet and FALET-to-pallet conversion |
| `PrintAttemptResult` | `PrintAttemptResultModel` | `id`, `palletId`, `attemptNumber`, `status`, `createdAt` | backend logging response after print attempt |
| `PrintJob` | none | `value`, `printerId`, `presetId`, `copies` | domain helper, not central to current UI |
| `PrintResult` | none | `status`, `errorMessage` | local result of socket printing |

### Important mapping notes

- `PalletCreateResponseModel` builds nested `Operator`, `ProductType`, and `ProductionLine` inline without dedicated nested DTO classes.
- `PrintAttemptResultModel` reads `palleteId` from JSON, not `palletId`. This is a fragile parser assumption if backend spelling changes.

## 4. Session Summary and Drilldown

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `SessionTableRow` | `SessionTableRowModel` | `productTypeId`, `productTypeName`, `completedPalletCount`, `completedPackageCount`, `loosePackageCount` | compact summary shown on main line card |
| `SessionProductionDetail` | `SessionProductionDetailModel` | `lineId`, `authorizationId`, `groups` | detailed modal data |
| `SessionProductTypeGroup` | `SessionProductTypeGroupModel` | `productTypeId`, `productTypeName`, `productTypePrefix`, `completedPalletCount`, `pallets` | group node in drilldown |
| `SessionPalletDetail` | `SessionPalletDetailModel` | `palletId`, `scannedValue`, `serialNumber`, `quantity`, `sourceType`, `createdAtDisplay` | row-level reprint data |

### Important field meanings

- `loosePackageCount` is what the UI labels as `الفالت` in the session table summary.
- `sourceType` is parsed and stored in drilldown pallet details but not prominently exposed in the current UI.
- `authorizationId` is kept from backend detail payload but not rendered in the current UI.

## 5. Handover Models

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `LineHandoverInfo` | `LineHandoverInfoModel` | `handoverId`, line info, `status`, operator names/ids, `faletItems`, notes, display timestamps | current handover entity used for pending and review states |
| `HandoverFaletItem` | `HandoverFaletItemModel` | `faletId`, `productTypeId`, `productTypeName`, `quantity`, `lastActiveProduct` | shown inside handover card |

### Important mapping notes

- `LineHandoverInfoModel` accepts either `handoverId` or fallback `id`.
- `isPending` is derived locally from `status == 'PENDING'`.

### Stale comment warning

- Provider comments mention review data such as `incompletePallet` and `looseBalances`.
- Current `LineHandoverInfo` entity does not contain those fields.
- That means those comments are `stale comment` relative to the current Dart types, unless backend fields exist but are intentionally ignored.

## 6. FALET Models

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `FaletResponse` | `FaletResponseModel` | `faletItems`, `totalOpenFaletCount`, `hasOpenFalet` | line-level FALET list |
| `FaletItem` | `FaletItemModel` | `faletId`, `productTypeId`, `productTypeName`, `quantity`, `status`, display timestamps | one open FALET entry |
| `FaletConvertToPalletResponse` | `FaletConvertToPalletResponseModel` | `pallet`, `creationMode`, `faletQuantityUsed`, `freshQuantityAdded`, `finalQuantity`, `faletId` | returned after convert-to-pallet |
| `FaletDisposeResponse` | `FaletDisposeResponseModel` | `faletId`, `productTypeId`, `productTypeName`, `disposedQuantity`, `reason`, `disposedAtDisplay` | returned after disposal |

### Important field meanings

- `FaletResponse.isEmpty` is a convenience getter used by `FaletScreen`.
- `additionalFreshQuantity` in convert flow represents extra new cartons added before finishing the pallet.

## 7. Printing Persistence Models

| Domain entity | Storage model | Main fields | Notes |
| --- | --- | --- | --- |
| `PrinterConfig` | `PrinterConfigModel` | `id`, `name`, `ip`, `port`, `isDefault`, `timeoutMs` | stored in Hive |
| `LabelPreset` | `LabelPresetModel` | `id`, `name`, `widthMm`, `heightMm`, `marginMm` | default presets are code-defined; custom presets are stored in Hive |
| `PrintingSettingsModel` | `PrintingSettingsModel` | `lastPrinterId`, `lastPresetId` | persisted selection state |

### Important field meanings

- `PrinterConfig.timeoutMs` controls socket connection timeout.
- `LabelPreset` dimensions directly feed QR render size and TSPL output.
- Default presets are immutable by repository rule; only custom presets can be edited or deleted.

## 8. Legacy Auth Models

| Domain entity | DTO model | Main fields | Notes |
| --- | --- | --- | --- |
| `User` | `UserModel` | `id`, `name`, `email`, `role` | used by legacy auth flow |
| `Operator` | `OperatorModel` | `id`, `name`, `displayLabel` | used in active line authorization and pallet response parsing |

### Current status

- `User` is part of legacy/unwired auth flow.
- `Operator` is still active in the main palletizing flow.

## 9. Frontend-State-Only Structures

These are not backend DTOs but are important to app behavior:

| Structure | Purpose |
| --- | --- |
| `LineAuthorizationState` | stores per-line authorization lifecycle including local error/loading fields |
| frontend `ProductionLine` enum | fixed UI shell for line 1 and line 2 |
| `PrintResult` | local printing outcome before/after backend log call |
| `HandoverCreationResult` | dialog-local payload returned to the handover create flow |

## 10. Notable Mismatches, Unused Fields, and Fragile Areas

- `PrintAttemptResultModel` expects `palleteId`; parser will break if backend returns `palletId` only.
- `blockedReason` is stored in provider and used for `isLineBlocked()`, but the actual reason text is not shown to the user.
- `canConfirmHandovers` and `canRejectHandovers` are stored and exposed in provider but not used by the current review UI.
- `hasOpenFalet` and `openFaletCount` are stored from backend but not rendered directly in the visible UI.
- `LineHandoverInfo` comments in provider imply fields that are not part of the current entity.
- `LoginScreen` and `AuthProvider` are real code but not connected to the current app root.

## Related Screens

- [ProductionLineSection](./screens/ProductionLineSection.md)
- [PalletSuccessDialog](./screens/PalletSuccessDialog.md)
- [FaletScreen](./screens/FaletScreen.md)
- [LoginScreen](./screens/LoginScreen.md)

## Related Services

- `PalletizingRepositoryImpl`
- `PalletizingProvider`
- `PrintingProvider`
- `AuthRepositoryImpl`

## Related Backend Concepts

- `LineStateService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
