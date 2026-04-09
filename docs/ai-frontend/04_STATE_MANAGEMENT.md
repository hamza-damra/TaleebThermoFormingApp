# State Management

This app uses `Provider` with `ChangeNotifier`-based state objects.

## Provider Graph

- `PalletizingProvider`
  - registered at app root
  - active in the current runtime
- `PrintingProvider`
  - registered at app root
  - active in the current runtime
- `AuthProvider`
  - exists in the repo
  - not registered in `main.dart`
  - legacy/unwired in the current flow

## PalletizingProvider: Global vs Line-Scoped State

### Global state

| Field | Meaning |
| --- | --- |
| `_state` | global bootstrap lifecycle: idle/loading/loaded/error |
| `_errorMessage` | global bootstrap failure message |
| `_productTypes` | product type reference list from bootstrap |
| `_productionLines` | backend production line entity list from bootstrap |

### Line-scoped state maps

All of the following are keyed by `lineNumber`.

| Map | Meaning |
| --- | --- |
| `_lineAuthorizations` | line PIN auth state, operator, timestamp, auth error |
| `_sessionTables` | compact session summary rows shown on line card |
| `_selectedProductTypes` | backend-authoritative current product for each line |
| `_lastPalletResponses` | last created pallet response per line |
| `_pendingHandovers` | pending handover info or review detail |
| `_blockedReasons` | backend-provided block reason string |
| `_lineCreating` | create-pallet loading flag |
| `_lineErrors` | last line-level action error string |
| `_lineSwitchingProduct` | product select/switch loading flag |
| `_lineUiModes` | backend UI mode string driving screen routing |
| `_canInitiateHandovers` | backend permission for outgoing handover creation |
| `_canConfirmHandovers` | backend permission flag, currently not consumed in UI |
| `_canRejectHandovers` | backend permission flag, currently not consumed in UI |
| `_faletItems` | fetched FALET list for that line |
| `_faletItemsLoading` | FALET screen loading flag |
| `_hasOpenFalet` | backend flag for open FALET existence |
| `_openFaletCount` | backend count of open FALET items |

## How Two Lines Stay Isolated

- UI shell is hardcoded to line 1 and line 2 by the frontend `ProductionLine` enum.
- All runtime business state uses `lineNumber` as the key.
- Every line action resolves the backend `lineId` through:
  - bootstrap production line entities
  - or previously stored authorization state as fallback
- A pallet, handover, FALET list, or session summary update only mutates the maps for the targeted line.

### Practical consequence

The app has one provider instance for all lines, but line-local state is still isolated because all mutable business fields are partitioned by `lineNumber`.

## State Flow Across the App

### Bootstrap

- `loadBootstrap()` clears global error, sets global loading, fetches reference lists, then hydrates every per-line map from backend line data.

### Authorization

- `authorizeLineWithPin()` updates one line’s auth state to authorizing, then merges the backend auth result with a follow-up line-state refresh.

### Product selection / switching

- Product operations only touch one line’s switching flag and line-local error.
- Successful responses directly hydrate the line from server-returned line-state payloads.

### Pallet creation

- Line-local create flag toggles during request.
- Success stores the last pallet response, updates selected product, refreshes line state, and later the UI opens print flow.

### Handover

- Create/confirm/reject mutate only the pending handover entry for the line, then refresh the line.

### FALET

- FALET list state is line-local.
- Convert/dispose trigger both FALET refresh and line-state refresh.

## Line Blocking Rules

`isLineBlocked(lineNumber)` returns true when any of the following is true:

- `lineUiMode == PENDING_HANDOVER_NEEDS_INCOMING`
- line is not authorized
- a pending handover exists and is still pending
- backend provided a non-null `blockedReason`

### UI effects of blocked state

- Create-pallet button is disabled.
- FALET button is hidden because `showOpenItems` requires the line not to be blocked.

### Caveat

- `blockedReason` affects blocking behavior, but the reason string itself is not rendered in the current UI.

## PrintingProvider

### Global state only

`PrintingProvider` is not line-scoped. It keeps:

- `_state`
- `_errorMessage`
- `_printers`
- `_presets`
- `_selectedPrinter`
- `_selectedPreset`
- `_lastPrintedValue`

### Persistence

- Loads printers and presets from Hive-backed repositories.
- Loads `lastPrinterId` and `lastPresetId` from `PrintingLocalStorage`.
- Falls back to default printer and default preset when needed.

### Print execution

- `print()` validates local printer/preset selection.
- Performs raw socket printing through `PrinterClient`.
- Returns `PrintResult`; caller decides whether to log to backend.

## Legacy AuthProvider

- Tracks auth lifecycle for `LoginScreen`.
- Supports email/password and PIN login through `AuthRepository`.
- Not wired into current runtime tree.

### Current status

- Treat as legacy or future-adjacent, not part of the active palletizing line flow.

## Session Handling

- There is no separate frontend session object for palletizing.
- The frontend treats backend line authorization plus session summary/detail endpoints as the effective session context.
- `sessionTable` is the line-local summary surface.
- `session-production-detail` is the detailed drilldown surface.

## Unused or Lightly Used State

The following provider data exists but has limited or no direct UI consumption in current code:

- `getBlockedReason()`
- `canConfirmHandover()`
- `canRejectHandover()`
- `hasOpenFalet()`
- `getOpenFaletCount()`
- `getLastPalletResponse()`

These may reflect backend contracts that are broader than the currently rendered UI.

## Rebuild Triggers

- Most widgets use `context.watch<PalletizingProvider>()` or `Consumer<PrintingProvider>()`.
- Any `notifyListeners()` on a provider can rebuild all listeners, even if only one line map changed.
- There is no selector-based optimization in the current code.

## Risks and Pitfalls

- `ProductionLineSection` mixes rendering with action orchestration, so line-flow behavior is split across widget code and provider methods.
- Silent refresh failures can leave stale line data after otherwise successful operations.
- Two-line support is hardcoded at UI shell level even though backend production lines are fetched dynamically.

## Related Screens

- [PalletizingScreen](./screens/PalletizingScreen.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [PrinterSettingsScreen](./screens/PrinterSettingsScreen.md)
- [LoginScreen](./screens/LoginScreen.md)

## Related Services

- `PalletizingProvider`
- `PrintingProvider`
- `AuthProvider`

## Related Backend Concepts

- `LineStateService`
- `LineAuthorizationService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
