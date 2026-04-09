# LineAuthOverlay

## 1. Screen Identity

- Name: `LineAuthOverlay`
- File path: `lib/presentation/widgets/line_auth_overlay.dart`
- Widget type: `StatefulWidget`
- Where it is used: overlayed inside `ProductionLineSection` during `NEEDS_AUTHORIZATION` and `PENDING_HANDOVER_NEEDS_INCOMING`

## 2. Purpose

This widget blocks line interaction until a 4-digit operator PIN is entered. It is used both for normal line authorization and for incoming-operator authorization during shift handover.

## 3. UI Structure

- darkened full-screen overlay
- centered card with:
  - optional pending-handover summary
  - icon and title
  - PIN `TextField`
  - inline error banner
  - confirm button

## 4. State Management

- Watches `PalletizingProvider`
- Local state:
  - PIN controller
  - focus node
- Reads:
  - `isLineAuthorizing`
  - line auth error
  - `lineUiMode`
  - pending handover summary

## 5. API Integration

- Indirect call through `PalletizingProvider.authorizeLineWithPin()`
- Relevant endpoints:
  - `POST /palletizing-line/lines/{lineId}/authorize-pin`
  - follow-up `GET /state`
- Related workflow:
  - [Line authorization](../02_APP_WORKFLOWS.md#4-line-authorization-pin)

## 6. User Actions

- Type a 4-digit PIN
- Submit from keyboard
- Press confirm button

## 7. Business Rules in UI

- PIN must be exactly 4 digits before API call is attempted.
- Typing clears previous auth error.
- When waiting for incoming operator, the card title and icon change and a pending-handover summary is shown.
- There is no cancel/dismiss path from the overlay.

## 8. Edge Cases

- Invalid PIN length shows snackbar before any provider call.
- API failure clears the PIN field and refocuses the input.
- Success only clears the field; actual overlay removal depends on backend `lineUiMode` after refresh.

## 9. Dependencies

- `PalletizingProvider`
- `LineHandoverInfo`
- frontend `ProductionLine` enum

## 10. Risks / Pitfalls

- Overlay visibility is controlled by parent `ProductionLineSection`, not by the overlay itself.
- If backend state and local assumptions diverge, the overlay may remain visible until the next successful state refresh.
- No separate debounce exists; repeated submissions are prevented by the provider loading flag.

## 11. AI Agent Notes

- Keep the incoming-handover mode wording distinct from normal authorization wording.
- Preserve the 4-digit local validation because the UI relies on fast factory-floor PIN entry.
- If you alter auth behavior, verify `LineAuthorizationState`, `ApiException.displayMessage`, and `ProductionLineSection` routing together.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [LineHandoverCard](./LineHandoverCard.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `LineAuthorizationService`
- `LineStateService`
- `LineHandoverService`
