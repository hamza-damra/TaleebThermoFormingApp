# ProductionLineSection

## 1. Screen Identity

- Name: `ProductionLineSection`
- File path: `lib/presentation/widgets/production_line_section.dart`
- Widget type: `StatelessWidget`
- Where it is used: rendered once per visible line inside `PalletizingScreen`

## 2. Purpose

This is the main operational surface for one production line. It is the most important UI orchestration widget in the app: it chooses which line mode to render, launches dialogs, triggers provider actions, and shows most success and error feedback.

## 3. UI Structure

- Normal production layout:
  - top action buttons row: `فالت` and `تسليم مناوبة`
  - form card with authorized operator card and product field
  - pending handover card when a handover exists but the line is still in normal mode
  - session summary via `SessionTableWidget`
  - fixed bottom create-pallet button
- Review layout:
  - orange review header
  - full handover card with confirm/reject actions
- Overlay layer:
  - `LineAuthOverlay` for authorization or incoming-handover PIN entry

## 4. State Management

- Watches `PalletizingProvider`
- Reads line-local provider state by `line.number`
- Primary render switch: `getLineUiMode(line.number)`
- Uses provider getters for:
  - authorization/operator
  - selected product
  - session rows
  - pending handover
  - blocked status
  - create loading

## 5. API Integration

- Indirect API calls through `PalletizingProvider`
- Relevant endpoints:
  - `POST /select-product`
  - `POST /product-switch`
  - `POST /pallets`
  - `POST /handover`
  - `POST /handover/{id}/confirm`
  - `POST /handover/{id}/reject`
  - follow-up `GET /state`
- Related docs:
  - [Workflows](../02_APP_WORKFLOWS.md)
  - [API integration](../03_API_INTEGRATION.md)

## 6. User Actions

- Pick or switch product
- Open FALET screen
- Create handover
- Create pallet
- Confirm handover
- Reject handover
- View session summary drilldown

## 7. Business Rules in UI

- `lineUiMode` is the single source of truth for which layout to render.
- `NEEDS_AUTHORIZATION` and `PENDING_HANDOVER_NEEDS_INCOMING` both show `LineAuthOverlay`.
- FALET button shows only when the line is authorized and not blocked.
- Handover button shows only when backend says `canInitiateHandover`.
- Create button is disabled when the line is blocked or already creating.
- Same-product selection is a no-op.
- First-time product selection requires a confirmation dialog.
- Product switching requires `ProductSwitchDialog` and may submit `loosePackageCount = 0`.

## 8. Edge Cases

- Unknown `lineUiMode` falls through to the normal production layout.
- `blockedReason` can block the line even though the reason text is not shown.
- Review mode waits for a full handover fetch and can temporarily show loading content.
- The widget contains inline dialogs for product confirmation and handover rejection; those flows are not reusable elsewhere.

## 9. Dependencies

- `PalletizingProvider`
- `CreatePalletDialog`
- `ProductSwitchDialog`
- `HandoverCreationDialog`
- `LineAuthOverlay`
- `LineHandoverCard`
- `PalletSuccessDialog`
- `FaletScreen`
- `SessionTableWidget`
- `SearchablePickerDialog`
- `ProductTypeImage`

## 10. Risks / Pitfalls

- This file mixes rendering and business orchestration, so changes can easily break workflows.
- Provider comments mention richer handover detail than the current `LineHandoverInfo` entity exposes; treat those comments as `stale comment`.
- Silent failures in follow-up refresh calls can leave stale UI after an action appears to succeed.

## 11. AI Agent Notes

- Do not replace backend-driven `lineUiMode` routing with local guesses.
- Preserve line isolation by continuing to use `line.number` for every provider call.
- Before modifying handover UI, also inspect `PalletizingProvider` and `LineHandoverCard`.
- Before modifying product UI, also inspect `ProductSwitchDialog`, `CreatePalletDialog`, and `SearchablePickerDialog`.

## Related Screens

- [PalletizingScreen](./PalletizingScreen.md)
- [LineAuthOverlay](./LineAuthOverlay.md)
- [CreatePalletDialog](./CreatePalletDialog.md)
- [FaletScreen](./FaletScreen.md)

## Related Services

- `PalletizingProvider`
- `PalletizingRepositoryImpl`

## Related Backend Concepts

- `LineStateService`
- `PalletizingService`
- `FaletService`
- `LineHandoverService`
