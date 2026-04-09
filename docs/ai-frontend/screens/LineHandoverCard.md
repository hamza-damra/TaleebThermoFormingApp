# LineHandoverCard

## 1. Screen Identity

- Name: `LineHandoverCard`
- File path: `lib/presentation/widgets/line_handover_card.dart`
- Widget type: `StatelessWidget`
- Where it is used: inside `ProductionLineSection` for pending-handover display and dedicated review mode

## 2. Purpose

This card renders handover details for a single line. In normal production it acts as an informational pending-handover card; in review mode it also exposes confirm and reject actions.

## 3. UI Structure

- orange gradient header
- information section with outgoing operator, created time, and notes
- optional FALET items section
- optional action buttons:
  - confirm handover
  - reject handover

## 4. State Management

- Stateless
- Receives all content and callbacks from parent
- `showResolveActions` determines whether action buttons are visible

## 5. API Integration

- No direct API call in this widget
- Parent callbacks usually lead to:
  - `POST /handover/{id}/confirm`
  - `POST /handover/{id}/reject`
- Related workflow:
  - [Handover review, confirm, and reject](../02_APP_WORKFLOWS.md#11-handover-review-confirm-and-reject)

## 6. User Actions

- Confirm handover when actions are enabled
- Reject handover when actions are enabled

## 7. Business Rules in UI

- Action buttons appear only when `showResolveActions` is true.
- FALET items are listed with compact product names and `(نشط)` marker when `lastActiveProduct` is true.
- Card can be used read-only or actionable depending on line mode.

## 8. Edge Cases

- If no FALET items exist, the FALET section is omitted.
- `isResolving` disables both action buttons when set by parent.
- Current entity only exposes `faletItems`; richer handover details mentioned in older comments are `stale comment` relative to this widget’s actual inputs.

## 9. Dependencies

- `LineHandoverInfo`
- `HandoverFaletItem`
- `ProductType.formatCompactName()`
- frontend `ProductionLine` enum

## 10. Risks / Pitfalls

- UI wording for confirm/reject is business-specific and should be changed carefully.
- If the backend adds new review fields, this card may not render them until the entity and widget are expanded together.

## 11. AI Agent Notes

- Preserve the split between informational pending state and actionable review state.
- Before modifying this card, also inspect `ProductionLineSection`, `LineAuthOverlay`, and `PalletizingProvider.getLineHandover()`.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [LineAuthOverlay](./LineAuthOverlay.md)
- [HandoverCreationDialog](./HandoverCreationDialog.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `LineHandoverService`
