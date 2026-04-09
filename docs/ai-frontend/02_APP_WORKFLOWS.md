# App Workflows

This file documents the active business workflows implemented by the current Flutter app.

## 1. Device Setup and Connection Test

### Trigger

- `DeviceKeyWrapper` detects no saved device key and shows `DeviceSettingsScreen` in setup mode.
- `SettingsHubScreen` can also open `DeviceSettingsScreen` later for maintenance.

### API

- Direct `HttpClient` call to `GET /palletizing-line/bootstrap` with `X-Device-Key` from the input field.

### State Changes

- On save: device key is written to secure storage.
- On successful test: local screen state marks key as valid and shows success feedback.
- In setup mode only, save success calls the callback that lets `DeviceKeyWrapper` enter the palletizing flow.

### UI Updates

- Setup mode hides the normal app bar and shows onboarding-style header text.
- Save and test buttons show local loading states.
- Success and error messages are inline on the screen.

### Edge Cases

- Empty key: validation error before any request.
- Failed network/server response: inline error message.
- Test success does not prefetch or cache bootstrap data; the actual palletizing bootstrap still happens later in `PalletizingScreen`.

## 2. Bootstrap Flow

### Trigger

- `PalletizingScreen.initState()` calls `PalletizingProvider.loadBootstrap()` after first frame.
- Pull-to-refresh in `PalletizingScreen` calls `loadBootstrap()` again.

### API

- `GET /palletizing-line/bootstrap`
- Additional `GET /palletizing-line/lines/{lineId}/handover/pending` for lines whose bootstrap `lineUiMode` is `PENDING_HANDOVER_REVIEW`

### State Changes

- Global provider state moves: `idle -> loading -> loaded` or `error`.
- Reference lists are hydrated:
  - product types
  - backend production line entities
- Per-line maps are hydrated:
  - authorization state
  - session table
  - pending handover
  - selected product
  - blocked reason
  - UI mode
  - handover permission flags

### UI Updates

- Loading: shimmer skeleton.
- Error: full-screen retry UI.
- Success: line sections render from hydrated state.

### Edge Cases

- If the extra pending-handover fetch fails, bootstrap still succeeds; the provider logs the error and keeps the summary data already received.
- Refresh fully replaces provider state from the backend.

## 3. Line State Rendering

### Trigger

- Every build of `ProductionLineSection`.

### Backend-Authoritative Input

- `lineUiMode` from bootstrap or `GET /lines/{lineId}/state`.

### UI Mode Matrix

| `lineUiMode` | Screen behavior |
| --- | --- |
| `NEEDS_AUTHORIZATION` | show `LineAuthOverlay` PIN gate |
| `AUTHORIZED` | normal production layout |
| `PENDING_HANDOVER_NEEDS_INCOMING` | show `LineAuthOverlay` with pending-handover summary for incoming operator |
| `PENDING_HANDOVER_REVIEW` | hide normal production controls and show dedicated handover review layout |

### State Changes

- None by itself; this is a render-routing workflow.

### UI Updates

- PIN overlay visibility
- handover review layout visibility
- availability of top action buttons
- create button enabled/disabled state

### Edge Cases

- Unknown `lineUiMode` falls through to the normal layout.
- `blockedReason` is stored but not explicitly rendered in the current UI.

## 4. Line Authorization (PIN)

### Trigger

- `LineAuthOverlay` confirm button or PIN submit.

### API

- `POST /palletizing-line/lines/{lineId}/authorize-pin`
- Then `GET /palletizing-line/lines/{lineId}/state`
- If refreshed mode is `PENDING_HANDOVER_REVIEW`, also `GET /palletizing-line/lines/{lineId}/handover/pending`

### State Changes

- Per-line auth state marks `isAuthorizing = true`.
- On success:
  - auth state updated with operator and timestamp
  - line data refreshed from backend
- On failure:
  - auth error saved on that line only

### UI Updates

- Overlay submit button disables while authorizing.
- Inline error banner shows API-derived PIN errors.
- Successful auth clears the PIN field and removes the overlay when the backend mode allows it.

### Edge Cases

- PIN length other than 4 is blocked locally before API call.
- Backend errors such as invalid PIN or locked PIN surface through `ApiException.displayMessage`.
- Authorization result does not optimistically force `AUTHORIZED`; the follow-up line-state fetch decides the real next mode.

## 5. First Product Selection

### Trigger

- User taps the product field in `ProductionLineSection` when the line has no selected product.

### API

- `POST /palletizing-line/lines/{lineId}/select-product`

### State Changes

- Provider sets `_lineSwitchingProduct[line] = true`.
- On success, the returned `BootstrapLineState` rehydrates the line maps.
- On `PRODUCT_ALREADY_SELECTED`, provider refreshes current line state from backend.

### UI Updates

- Searchable product picker opens.
- Product confirmation dialog appears before submission.
- On success, product field updates to the backend-authoritative selected product.

### Edge Cases

- Selecting the same product as already selected does nothing.
- Product confirmation dialog can be canceled before any API call.
- If the backend says another device already selected a product, local optimistic choice is discarded and backend state wins.

## 6. Product Switching and Loose Balance Recording

### Trigger

- User taps the product field and chooses a different product while one is already active.

### API

- `POST /palletizing-line/lines/{lineId}/product-switch`

### State Changes

- Provider sets per-line switching flag.
- Request carries:
  - previous product type id
  - new product type id
  - `loosePackageCount`
- On success, returned line state rehydrates line maps.
- On stale-state errors (`CURRENT_PRODUCT_MISMATCH`, `NO_CURRENT_PRODUCT`), provider refreshes the line from backend.

### UI Updates

- `ProductSwitchDialog` asks whether leftover cartons exist from the previous product.
- If user says no, request sends `loosePackageCount = 0`.
- If success, session table and selected product update from backend state.

### Edge Cases

- Loose count must be greater than zero when the user says leftovers exist.
- Same-product selection is ignored with no API call.
- The current app has no dedicated success toast for product switch; errors are shown through snackbars.

## 7. Pallet Creation

### Trigger

- User taps `إنشاء طبلية جديدة` in `ProductionLineSection`.

### API

- `POST /palletizing-line/lines/{lineId}/pallets`
- Then `GET /palletizing-line/lines/{lineId}/state`

### State Changes

- Per-line creating flag becomes true.
- On success:
  - `lastPalletResponses[line]` stores the new pallet
  - selected product is aligned with the pallet response
  - line state is refreshed from backend
- On failure:
  - line error is saved

### UI Updates

- Create button disables and shows a spinner while the request is running.
- Success opens `PalletSuccessDialog`.
- Errors show snackbars.

### Edge Cases

- Create button is disabled if the line is blocked or already creating.
- Quantity must be greater than zero inside `CreatePalletDialog`.
- The dialog does not enforce package-quantity multiples; it accepts any positive integer.

## 8. Print Flow

### Trigger

- User presses `طباعة الملصق` in `PalletSuccessDialog`.
- User presses reprint in `_ReprintDialog` from `SessionDrilldownDialog`.

### API

- No backend API for the actual print payload.
- After print attempt finishes, frontend logs:
  - `POST /palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts`

### State Changes

- `PrintingProvider` moves to `printing`, then `success` or `error`.
- `PalletizingProvider.logPrintAttempt()` reports result back to backend.

### UI Updates

- If no printers exist, `PrinterSelectorDialog` is shown first.
- Printing dialogs show local progress, success icon, or error banner.
- Success dialog changes title from pallet-created to printed-successfully.

### Edge Cases

- Missing printer or preset blocks local print before socket work begins.
- Log-print-attempt failure is swallowed and only returns false; the UI does not surface a separate logging error.
- Printer identifier sent to backend is printer name, not printer ID or IP.

## 9. FALET Screen and Actions

### Trigger

- User taps `فالت` from `ProductionLineSection`.

### API

- On screen open or refresh: `GET /palletizing-line/lines/{lineId}/falet`
- Convert: `POST /palletizing-line/lines/{lineId}/falet/convert-to-pallet`
- Dispose: `POST /palletizing-line/lines/{lineId}/falet/dispose`
- After convert/dispose: provider also refreshes line state

### State Changes

- Per-line FALET loading flag toggles during fetch.
- FALET result is stored in `_faletItems[line]`.
- Convert/dispose both re-fetch FALET data and refresh line state in parallel.

### UI Updates

- Empty state when no open FALET items exist.
- Each FALET card exposes:
  - convert to pallet
  - dispose
- Convert success opens `PalletSuccessDialog` with the created pallet.

### Edge Cases

- FALET button itself is hidden while the line is blocked.
- Convert dialog allows zero additional fresh quantity when no extra cartons are added.
- Dispose reason is optional.

## 10. Handover Creation

### Trigger

- User taps `تسليم مناوبة` from `ProductionLineSection`.

### API

- `POST /palletizing-line/lines/{lineId}/handover`
- Then `GET /palletizing-line/lines/{lineId}/state`

### State Changes

- Provider stores the returned pending handover.
- Follow-up line-state refresh updates `lineUiMode`.
- The outgoing operator is released according to provider comments and the expected next mode is `PENDING_HANDOVER_NEEDS_INCOMING`.

### UI Updates

- `HandoverCreationDialog` can include:
  - current active product info
  - optional declaration that FALET exists for the active product
  - optional handover notes
- Success shows snackbar and transitions the line into incoming-operator wait mode.

### Edge Cases

- If FALET is declared, current product must exist and quantity must be greater than zero.
- The dialog is only offered when backend says `canInitiateHandover = true`.

## 11. Handover Review, Confirm, and Reject

### Trigger

- Incoming operator authorizes the line while backend mode is `PENDING_HANDOVER_NEEDS_INCOMING`.
- Line then renders `PENDING_HANDOVER_REVIEW`.
- User confirms or rejects from `LineHandoverCard`.

### API

- After incoming PIN: `POST /authorize-pin`, then `GET /state`, then `GET /handover/pending`
- Confirm: `POST /palletizing-line/lines/{lineId}/handover/{handoverId}/confirm`
- Reject: `POST /palletizing-line/lines/{lineId}/handover/{handoverId}/reject`
- After confirm/reject: `GET /state`

### State Changes

- Pending handover is replaced with full detail when available.
- Confirm/reject clear `_pendingHandovers[line]`, then refresh line state.

### UI Updates

- In review mode, normal production controls are hidden.
- The dedicated review layout shows one `LineHandoverCard` with action buttons.
- Reject flow opens an inline rejection-notes dialog inside `ProductionLineSection`.

### Edge Cases

- `getLineHandover()` returns `null` on error, so the review screen can temporarily show a loading indicator or summary-only state.
- `canConfirmHandover` and `canRejectHandover` exist in provider state but are not currently used to gate the action buttons; the screen relies on being in review mode.

## 12. Session Summary and Drilldown

### Trigger

- User taps `SessionTableWidget`.

### API

- `GET /palletizing-line/lines/{lineId}/session-production-detail`

### State Changes

- Dialog-local state stores loading/error/detail.

### UI Updates

- Summary card on the line screen shows grouped session rows from bootstrap/line-state data.
- Drilldown dialog shows grouped product sections with pallet-level detail and reprint action.

### Edge Cases

- If backend returns `LINE_NOT_AUTHORIZED`, the dialog auto-closes and shows a snackbar.
- Empty detail shows an empty-state message instead of groups.

## 13. Refresh and Re-Sync Behavior

### Trigger

- Pull-to-refresh on `PalletizingScreen`
- Provider-internal refresh after selected actions
- Stale-state recovery after product selection/switch errors

### API

- Full refresh: `GET /palletizing-line/bootstrap`
- Line refresh: `GET /palletizing-line/lines/{lineId}/state`

### State Changes

- Full refresh rebuilds all line maps.
- Line refresh replaces one line’s state in place.

### UI Updates

- Pull-to-refresh uses the same loading model as bootstrap.
- Some action flows silently recover from stale backend state.

### Edge Cases

- `_refreshLineStateFromBackend()` catches failures silently, so follow-up refresh problems can leave stale UI without a user-visible error.

## 14. Error Scenarios

### Common Handling

- Backend/business errors are mapped through `ApiException.displayMessage`.
- Most action-level errors show snackbars.

### Important Cases

- Invalid or locked operator PIN.
- Line not authorized for session drilldown.
- Product already selected on another device.
- Current product mismatch during switch.
- Pending handover already exists.
- Line blocked by pending handover.
- Network timeout or server unreachable.
- Printer connection failure.

## Related Screens

- [LineAuthOverlay](./screens/LineAuthOverlay.md)
- [ProductionLineSection](./screens/ProductionLineSection.md)
- [FaletScreen](./screens/FaletScreen.md)
- [SessionDrilldownDialog](./screens/SessionDrilldownDialog.md)

## Related Services

- `PalletizingProvider`
- `PrintingProvider`
- `PalletizingRepositoryImpl`

## Related Backend Concepts

- `LineAuthorizationService`
- `LineStateService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
