# AI Frontend Docs: Taleeb ThermoForming

This folder is a code-derived documentation set for the production Flutter palletizing app used for `تكوين الطبليات / تكوين المشاتيح` in a factory environment.

The goal is to let another AI agent understand the current frontend without re-reading the source code: how the app boots, how each production line is isolated, how the UI maps to backend state, and where business workflows are enforced in screens, dialogs, and providers.

## App Overview

- Primary runtime purpose: line-scoped palletizing for two production lines, including operator PIN authorization, product selection, pallet creation, FALET handling, handover between shifts, session summaries, and QR label printing.
- Current entry path: `main.dart` starts `DeviceKeyWrapper`, which sends the user either to `DeviceSettingsScreen` for initial device-key setup or directly to `PalletizingScreen`.
- UI language: Arabic RTL.
- Runtime layout: mobile/tablet uses tabbed line switching; desktop/tablet-wide uses dual-pane line rendering.

## High-Level Architecture

- App root: `MultiProvider` registers `PalletizingProvider` and `PrintingProvider`.
- Primary business state: `PalletizingProvider` stores global bootstrap state plus per-line maps keyed by `lineNumber`.
- Printing state: `PrintingProvider` manages printer configs, label presets, selected printer/preset, and live print state.
- Dependency wiring: `ServiceLocator` creates `ApiClient`, repositories, and providers.
- Storage split:
  - `FlutterSecureStorage` for device key and legacy auth token/user info.
  - `Hive` for printers, custom label presets, and persisted printing settings.
- Network split:
  - `/palletizing-line/*` endpoints use `X-Device-Key`.
  - Legacy `/auth/*` and `/palletizing/*` endpoints use bearer tokens.

See [01_APP_ARCHITECTURE.md](./01_APP_ARCHITECTURE.md), [03_API_INTEGRATION.md](./03_API_INTEGRATION.md), and [04_STATE_MANAGEMENT.md](./04_STATE_MANAGEMENT.md).

## Folder Map

```text
lib/
  core/           app config, DI, constants, theme, exceptions, responsive helpers
  data/           Dio client, secure/local storage, DTO models, repository impls
  domain/         entities and repository contracts
  presentation/   providers, screens, dialogs, widgets
  printing/       QR rendering, TSPL generation, printer socket client
```

## API Integration Overview

- Bootstrap and line workflows are backend-authoritative. The frontend reads `lineUiMode`, authorization state, session table data, pending handover data, and current product from the backend, then renders the UI accordingly.
- The main palletizing contract lives behind `/palletizing-line/*`.
- `DeviceSettingsScreen` bypasses Dio and hits `GET /palletizing-line/bootstrap` directly with `HttpClient` to validate the device key.
- Product images are a special case: `ProductTypeImage` loads relative image URLs through `CachedNetworkImage` and attaches a bearer token from secure storage instead of a device key.

See [03_API_INTEGRATION.md](./03_API_INTEGRATION.md).

## State Management Approach

- Pattern: `Provider` + `ChangeNotifier`.
- Main runtime state holder: `PalletizingProvider`.
- Printing state holder: `PrintingProvider`.
- Legacy/unwired auth state holder: `AuthProvider`.
- Per-line isolation is implemented with maps keyed by line number, not with separate provider instances per line.

See [04_STATE_MANAGEMENT.md](./04_STATE_MANAGEMENT.md).

## Documented Modules

- [01_APP_ARCHITECTURE.md](./01_APP_ARCHITECTURE.md)
- [02_APP_WORKFLOWS.md](./02_APP_WORKFLOWS.md)
- [03_API_INTEGRATION.md](./03_API_INTEGRATION.md)
- [04_STATE_MANAGEMENT.md](./04_STATE_MANAGEMENT.md)
- [05_MODELS.md](./05_MODELS.md)

## Screen Index

### Active palletizing flow

- [PalletizingScreen](./screens/PalletizingScreen.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [LineAuthOverlay](./screens/LineAuthOverlay.md)
- [CreatePalletDialog](./screens/CreatePalletDialog.md)
- [ProductSwitchDialog](./screens/ProductSwitchDialog.md)
- [PalletSuccessDialog](./screens/PalletSuccessDialog.md)
- [HandoverCreationDialog](./screens/HandoverCreationDialog.md)
- [LineHandoverCard](./screens/LineHandoverCard.md)
- [FaletScreen](./screens/FaletScreen.md)
- [ConvertFaletToPalletDialog](./screens/ConvertFaletToPalletDialog.md)
- [DisposeFaletDialog](./screens/DisposeFaletDialog.md)
- [SessionTableWidget](./screens/SessionTableWidget.md)
- [SessionDrilldownDialog](./screens/SessionDrilldownDialog.md)
- [ReprintDialog](./screens/ReprintDialog.md)
- [SearchablePickerDialog](./screens/SearchablePickerDialog.md)

### Printing and settings

- [PrinterSelectorDialog](./screens/PrinterSelectorDialog.md)
- [AddPrinterDialog](./screens/AddPrinterDialog.md)
- [SettingsHubScreen](./screens/SettingsHubScreen.md)
- [PrinterSettingsScreen](./screens/PrinterSettingsScreen.md)
- [EditPrinterDialog](./screens/EditPrinterDialog.md)
- [PresetSettingsScreen](./screens/PresetSettingsScreen.md)
- [PresetFormDialog](./screens/PresetFormDialog.md)
- [DeviceSettingsScreen](./screens/DeviceSettingsScreen.md)

### Legacy or currently unwired

- [LoginScreen](./screens/LoginScreen.md)

## Active vs Legacy Surfaces

### Active in the current app entry path

- `DeviceSettingsScreen`
- `PalletizingScreen`
- All palletizing line dialogs and widgets reachable from `PalletizingScreen`
- Printer and preset settings screens reachable from the settings hub

### Present in the repo but not wired into `main.dart`

- `LoginScreen`
- `AuthProvider`
- `AuthRepositoryImpl`
- Legacy `/auth/*` and `/palletizing/*` reference-data endpoints

## Coverage Notes

- This documentation only states behavior provable from the current Flutter code.
- When current code comments mention backend fields not present in current entities, those notes are labeled as `stale comment`.
- When a backend expectation is implied by naming but not fully provable from current frontend code, it is labeled as `unclear from code`.

## Related Screens

- [PalletizingScreen](./screens/PalletizingScreen.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [DeviceSettingsScreen](./screens/DeviceSettingsScreen.md)

## Related Services

- `PalletizingProvider`
- `PrintingProvider`
- `ApiClient`

## Related Backend Concepts

- `LineStateService`
- `LineAuthorizationService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
