# SessionDrilldownDialog

## 1. Screen Identity

- Name: `SessionDrilldownDialog`
- File path: `lib/presentation/widgets/session_drilldown_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `SessionTableWidget` when the operator taps the session summary card

## 2. Purpose

This dialog loads the full current-session pallet list for one line, groups pallets by product type, and provides the entry point for label reprint actions.

## 3. UI Structure

- modal dialog with colored header and close button
- body states:
  - loading
  - unauthorized auto-dismiss state
  - error state with retry button
  - empty state
  - grouped list state
- grouped list uses `ExpansionTile` cards
- each pallet row shows:
  - pallet serial number
  - package quantity
  - created-at display string
  - print icon button for reprint

## 4. State Management

- Local dialog state:
  - `_detail`
  - `_isLoading`
  - `_errorMessage`
  - `_isLineNotAuthorized`
- Calls `PalletizingProvider.fetchSessionProductionDetail(line.number)` in `initState()`
- Does not keep provider listeners for the loaded detail; it stores the fetched payload in local state
- Reprint is delegated to the private `_ReprintDialog`

## 5. API Integration

- Fetches detail through:
  - `GET /palletizing-line/lines/{lineId}/session-production-detail`
- If the fetch throws `ApiException` with code `LINE_NOT_AUTHORIZED`, the dialog closes itself and shows a snackbar
- Related workflow doc:
  - [Session Summary and Drilldown](../02_APP_WORKFLOWS.md#12-session-summary-and-drilldown)

## 6. User Actions

- Open the dialog from the session summary card
- Retry after an error
- Expand or collapse product groups
- Tap a pallet's print button to open [ReprintDialog](./ReprintDialog.md)
- Close the dialog with the header close action

## 7. Business Rules in UI

- Drilldown is line-scoped and always uses the current line number.
- Session details are fetched on demand rather than reused from the summary widget.
- The first product group starts expanded; others start collapsed.
- Reprint is available per pallet row, not as a batch action.

## 8. Edge Cases

- Unauthorized lines are handled specially: the dialog dismisses itself and shows `لا يوجد مشغل مصرح على هذا الخط`.
- Empty successful responses show `لا توجد طبليات في هذه المناوبة`.
- Non-authorization API errors show the backend display message and expose a retry button.
- Generic exceptions fall back to `فشل في تحميل البيانات`.

## 9. Dependencies

- `PalletizingProvider`
- `SessionProductionDetail`
- `SessionProductTypeGroup`
- `SessionPalletDetail`
- `ProductType.formatCompactName`
- private [ReprintDialog](./ReprintDialog.md)

## 10. Risks / Pitfalls

- The unauthorized auto-dismiss is triggered via a post-frame callback inside build-time flow control; refactoring that logic carelessly can create repeated snackbars or navigation errors.
- Detail data is snapshotted into local state, so it does not live-update if the line changes while the dialog is open.
- Summary rows and drilldown detail come from different payloads and can temporarily disagree after fast backend changes.

## 11. AI Agent Notes

- Preserve the special `LINE_NOT_AUTHORIZED` branch because it is different from generic error handling.
- If you add more pallet metadata here, verify the `SessionProductionDetailModel` already maps it.
- Reprint is intentionally a child dialog, not inline logic in the expansion rows.

## Related Screens

- [SessionTableWidget](./SessionTableWidget.md)
- [ReprintDialog](./ReprintDialog.md)
- [PrinterSelectorDialog](./PrinterSelectorDialog.md)

## Related Services

- `PalletizingProvider`
- `PrintingProvider`

## Related Backend Concepts

- `LineStateService`
- session detail portion of `PalletizingService`
