# SessionTableWidget

## 1. Screen Identity

- Name: `SessionTableWidget`
- File path: `lib/presentation/widgets/session_table_widget.dart`
- Widget type: `StatelessWidget`
- Where it is used: rendered inside `ProductionLineSection` as the visible session summary card for a line

## 2. Purpose

This widget gives the operator a compact per-product summary of the current session and acts as the entry point to the detailed pallet drilldown dialog.

## 3. UI Structure

- tappable card container
- colored header titled `ملخص المناوبة`
- empty state when there are no rows
- table with four columns:
  - product type
  - pallet count
  - completed package count
  - loose balance / `FALET`
- loose-balance rows get orange highlighting and a warning icon

## 4. State Management

- Pure presentational widget
- Receives `line` and `rows` from its parent
- Does not watch a provider directly
- Tap opens `SessionDrilldownDialog`, which performs the detailed fetch

## 5. API Integration

- No direct API call
- Uses already-hydrated session rows from line state / bootstrap
- Tap-through detail flow calls:
  - `GET /palletizing-line/lines/{lineId}/session-production-detail`
- Related workflow doc:
  - [Session Summary and Drilldown](../02_APP_WORKFLOWS.md#12-session-summary-and-drilldown)

## 6. User Actions

- Tap anywhere on the summary card to open `SessionDrilldownDialog`

## 7. Business Rules in UI

- Summary is grouped by product type, not by pallet.
- `loosePackageCount` is always shown; rows with `hasLooseBalance` are visually emphasized.
- Product names are normalized through `ProductType.formatCompactName`.

## 8. Edge Cases

- An empty row list shows a dedicated `لا توجد بيانات إنتاج في هذه المناوبة` state.
- The widget does not defend against malformed row data; it trusts `SessionTableRow`.
- Very long product names can truncate because cell text uses `ellipsis`.

## 9. Dependencies

- `SessionTableRow`
- frontend `ProductionLine`
- `SessionDrilldownDialog`
- `ProductType.formatCompactName`

## 10. Risks / Pitfalls

- This widget is summary-only; changing it does not change the real session source of truth.
- Because drilldown is a separate backend call, summary and drilldown can briefly differ if line state changes between renders.

## 11. AI Agent Notes

- Keep this card fast to scan; operators use it as a dashboard surface before opening detail.
- If you add columns, verify mobile table readability and confirm whether the parent line card still fits.
- When changing summary semantics, review both `LineStateResponse` mapping and `SessionProductionDetail` mapping.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [SessionDrilldownDialog](./SessionDrilldownDialog.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `LineStateService`
- session summary portion of `PalletizingService`
