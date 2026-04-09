# PalletizingScreen

## 1. Screen Identity

- Name: `PalletizingScreen`
- File path: `lib/presentation/screens/palletizing_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: current main operational route after `DeviceKeyWrapper` confirms a saved device key

## 2. Purpose

This is the root production screen for the active app. It loads bootstrap data, renders the two production lines, exposes refresh, and routes users into settings.

## 3. UI Structure

- App bar with title and settings button
- Mobile/tablet: `TabBar` + `TabBarView` for line 1 and line 2
- Larger layouts: dual-pane row with both lines visible
- Loading state: shimmer skeleton via `PalletizingShimmer`
- Error state: centered retry UI
- Loaded state: one or two `ProductionLineSection` widgets

## 4. State Management

- Watches `PalletizingProvider`
- Local widget state:
  - clock string for header
  - tab controller
  - active tab index
- Calls `loadBootstrap()` after first frame

## 5. API Integration

- Indirect API usage only through `PalletizingProvider.loadBootstrap()`
- Relevant endpoint: `GET /palletizing-line/bootstrap`
- Related workflow docs:
  - [Bootstrap flow](../02_APP_WORKFLOWS.md#2-bootstrap-flow)
  - [Refresh and re-sync behavior](../02_APP_WORKFLOWS.md#13-refresh-and-re-sync-behavior)

## 6. User Actions

- Pull to refresh
- Switch between line tabs on smaller layouts
- Open `SettingsHubScreen`
- Retry after bootstrap failure

## 7. Business Rules in UI

- The visible line shell is fixed to exactly two lines.
- Bootstrap must complete before any line screen is usable.
- Error state blocks the rest of the app until retry succeeds.

## 8. Edge Cases

- While bootstrap is `idle` or `loading`, shimmer is shown.
- If bootstrap fails, no partial line rendering is attempted.
- `PalletizingShimmerDualPane` intentionally renders both lines during desktop loading.

## 9. Dependencies

- `PalletizingProvider`
- `ProductionLineSection`
- `SettingsHubScreen`
- `PalletizingShimmer`
- frontend `ProductionLine` enum from `core/constants.dart`

## 10. Risks / Pitfalls

- Two-line assumption is hardcoded in the tab controller and screen layout.
- Refresh replaces all provider state, so downstream dialogs should not assume state stability across a global refresh.
- `SummaryCard` still exists in the repo but is not part of the current loaded UI; the active summary surface is `SessionTableWidget` inside `ProductionLineSection`.

## 11. AI Agent Notes

- Do not break the post-frame bootstrap call unless the entry flow is redesigned.
- Preserve the distinction between loading shimmer, full error screen, and loaded line UI.
- If adding more lines, this screen must be redesigned together with `core/constants.dart` and `PalletizingProvider` consumers.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [SettingsHubScreen](./SettingsHubScreen.md)
- [DeviceSettingsScreen](./DeviceSettingsScreen.md)

## Related Services

- `PalletizingProvider`
- `ApiClient`

## Related Backend Concepts

- `LineStateService`
- bootstrap aggregator behind `/palletizing-line/bootstrap`
