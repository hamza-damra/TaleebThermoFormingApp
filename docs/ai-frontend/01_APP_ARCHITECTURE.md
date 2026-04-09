# App Architecture

This document describes the current frontend architecture as implemented in the Flutter codebase.

## Runtime Composition

- Entry file: `lib/main.dart`.
- App root: `MyApp`, which registers:
  - `ChangeNotifierProvider<PalletizingProvider>`
  - `ChangeNotifierProvider<PrintingProvider>`
- Initial gate: `DeviceKeyWrapper`.
  - Checks secure storage for a saved device key.
  - If missing, routes to `DeviceSettingsScreen` in setup mode.
  - If present, routes to `PalletizingScreen`.

## Project Structure

### `core/`

- `config.dart`: base URL and network timeouts.
- `di.dart`: lightweight service locator.
- `constants.dart`: frontend-only two-line enum with colors, labels, and line numbers.
- `responsive.dart`: mobile/tablet/desktop breakpoints.
- `theme.dart`: app theme and Arabic typography.
- `exceptions/`: API and printing exception mapping.

### `data/`

- `datasources/api_client.dart`: shared Dio client with auth-header selection logic.
- `datasources/auth_local_storage.dart`: secure storage for device key and legacy auth values.
- `datasources/printing_local_storage.dart`: Hive setup for printers, presets, and printing settings.
- `models/`: DTO parsing from backend responses and Hive model serialization.
- `repositories/`: concrete repository implementations used by providers.

### `domain/`

- `entities/`: app-facing state and data models.
- `repositories/`: abstract repository contracts.

### `presentation/`

- `providers/`: `PalletizingProvider`, `PrintingProvider`, and legacy `AuthProvider`.
- `screens/`: top-level routes and settings screens.
- `widgets/`: dialogs, sections, cards, drilldowns, overlays, and supporting interactive UI.

### `printing/`

- `label_renderer.dart`: QR-only bitmap rendering based on preset size.
- `printer_client.dart`: raw socket print transport.
- `tspl_builder.dart`: TSPL command generation.
- `unit_converter.dart`: mm-to-dots conversion utilities.

## State Management Pattern

- Pattern: `Provider` + `ChangeNotifier`.
- `PalletizingProvider` owns both:
  - global app bootstrap state
  - per-line state maps keyed by `lineNumber`
- `PrintingProvider` owns local printing state and persisted settings.
- `AuthProvider` exists but is not wired into the current runtime tree.

### Important architectural consequence

`ProductionLineSection` is not a pure presentational widget. It contains significant orchestration logic for:

- product selection branching
- product-switch confirmation
- pallet creation dialog handoff
- handover creation, confirm, reject flows
- success and failure snackbars

That logic is spread between the widget and `PalletizingProvider`, so UI and flow control are only partially separated.

## Separation of Concerns

### UI layer

- Screens and widgets render backend-derived line state.
- Dialogs gather user input such as PIN, pallet quantity, loose balance, FALET disposal reason, or handover notes.
- `ProductionLineSection` decides which UI to render from `lineUiMode`.

### State layer

- `PalletizingProvider` hydrates all line data from bootstrap and line-state endpoints.
- Per-line getters expose line-local state to the UI.
- `PrintingProvider` exposes printer/preset selection and print execution state.

### Service/repository layer

- `PalletizingRepositoryImpl` wraps all `/palletizing-line/*` network calls.
- `PrinterRepositoryImpl` and `PresetRepositoryImpl` wrap Hive-backed persistence.
- `ApiClient` centralizes transport behavior and error normalization.

### Model layer

- `data/models/*` transform backend JSON into domain entities.
- The UI mostly consumes domain entities, not raw JSON.

## API Layer Structure

- Main HTTP transport: `Dio`.
- Shared client: `ApiClient`.
- Auth header strategy:
  - `/palletizing-line/*`: `X-Device-Key`, no bearer token.
  - everything else: bearer token when available.
- Direct transport exception:
  - `DeviceSettingsScreen` uses `HttpClient` directly for bootstrap validation.

### Notable coupling

- `ProductTypeImage` builds a full URL from `AppConfig.baseUrl` and authenticates image requests with a bearer token from secure storage.
- This differs from the device-key model used by the main palletizing APIs.
- If the backend expects device-key access for image endpoints, the current image loader could become inconsistent. The exact backend expectation is `unclear from code`.

## Navigation System

- Top-level routing uses `MaterialApp(home: ...)` without named routes.
- Navigation style is imperative:
  - `Navigator.push(MaterialPageRoute(...))`
  - `showDialog(...)`
  - `showModalBottomSheet(...)`
- `PalletizingScreen` does not navigate between lines; it uses:
  - `TabBar` + `TabBarView` on smaller layouts
  - side-by-side panes on larger layouts

## Loading States Handling

- Initial palletizing load:
  - `PalletizingScreen` shows shimmer skeletons while bootstrap is loading.
- Global bootstrap error:
  - full-screen error with retry button.
- Per-line operation loading:
  - creating pallet: create button disabled + spinner
  - line PIN authorization: overlay button disabled + spinner
  - product selection/switch: provider flag exists, but there is no dedicated inline loading UI beyond rebuild timing
  - FALET fetch: centered spinner when screen opens with no cached data
  - session drilldown: modal loading state
  - printing: dialog-local loading state

## Error Handling Strategy

- Network and backend errors are normalized into `ApiException`.
- Arabic display messages are derived from `ApiException.displayMessage`.
- UI error delivery patterns:
  - global full-screen error for failed bootstrap
  - per-dialog or per-screen snackbars for most business actions
  - inline error banner inside `LineAuthOverlay`
  - local dialog error banners for print failures

### Important caveat

`_refreshLineStateFromBackend()` catches and logs errors silently. Some follow-up refresh failures can leave partially updated UI state without surfacing a visible error.

## Responsive Layout Strategy

- Breakpoints:
  - mobile `< 600`
  - tablet `< 1200`
  - desktop `>= 1200`
- `PalletizingScreen` behavior:
  - mobile/tablet: one line visible at a time through tabs
  - desktop: both lines visible together
- Most dialogs resize width and spacing using `ResponsiveHelper`.

## Offline and Edge Behavior

### Persisted locally

- Device key
- Legacy auth token/user info
- Printer configs
- Custom label presets
- Last selected printer/preset

### Not persisted locally

- Bootstrap palletizing data
- Line session tables
- Pending handovers
- FALET lists
- Current line authorization state

### Practical meaning

- The app is not offline-capable for palletizing workflows.
- It only keeps device/printing setup locally.
- User-facing retry is mostly manual:
  - pull-to-refresh
  - retry button
  - rerun action from dialog/screen

## Hardcoded Constraints

- Frontend line rendering is hardcoded to two lines through the `ProductionLine` enum and a `TabController(length: 2)`.
- Backend line entities are still fetched from bootstrap, but the visible line shells are fixed to line 1 and line 2.
- If the backend adds more lines, the current frontend will not automatically expose them.

## Legacy and Inactive Architecture

- `LoginScreen` and `AuthProvider` still exist.
- `AuthRepositoryImpl` still supports `/auth/login` and `/auth/pin-login`.
- `main.dart` does not register `AuthProvider` or route to `LoginScreen`.
- These pieces should be treated as legacy or adjacent, not part of the active palletizing runtime.

## Related Screens

- [PalletizingScreen](./screens/PalletizingScreen.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [DeviceSettingsScreen](./screens/DeviceSettingsScreen.md)
- [SettingsHubScreen](./screens/SettingsHubScreen.md)

## Related Services

- `ApiClient`
- `PalletizingRepositoryImpl`
- `PalletizingProvider`
- `PrintingProvider`

## Related Backend Concepts

- `LineStateService`
- `LineAuthorizationService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
