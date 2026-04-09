# HandoverCreationDialog

## 1. Screen Identity

- Name: `HandoverCreationDialog`
- File path: `lib/presentation/widgets/handover_creation_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `ProductionLineSection` when the operator initiates handover

## 2. Purpose

This dialog collects the outgoing operator’s handover metadata, especially whether the current active product still has FALET cartons.

## 3. UI Structure

- dialog header with swap icon
- optional current-product summary card
- switch for whether FALET exists
- conditional FALET quantity input
- optional notes field
- cancel and confirm actions

## 4. State Management

- Local dialog state only
- Stores:
  - `_hasFalet`
  - FALET quantity controller
  - notes controller
- Returns a `HandoverCreationResult` to the parent widget

## 5. API Integration

- No direct API call from the dialog
- Parent `ProductionLineSection` uses returned values to call:
  - `POST /palletizing-line/lines/{lineId}/handover`

## 6. User Actions

- Toggle whether FALET exists
- Enter FALET quantity for the active product
- Enter optional notes
- Cancel or confirm handover

## 7. Business Rules in UI

- If FALET is declared:
  - current product must exist
  - FALET quantity must be greater than zero
- Only the current active product can be declared as handover FALET from this dialog.
- The dialog cannot be dismissed by tapping outside; `barrierDismissible` is false.

## 8. Edge Cases

- If no current product exists, the FALET-enabled submit path becomes invalid.
- Notes are optional and trimmed before returning.
- The dialog does not show backend-derived pending-handover state; it is only for creation.

## 9. Dependencies

- `ProductType`
- `HandoverCreationResult`
- `ResponsiveHelper`

## 10. Risks / Pitfalls

- This dialog only captures FALET for the current product, not a broader set of shift artifacts.
- If backend handover payload expands, this dialog and its return object must expand together.

## 11. AI Agent Notes

- Preserve the distinction between “current active product” and general FALET inventory.
- If you add more handover data here, also update `PalletizingProvider.createLineHandover()` and [02_APP_WORKFLOWS.md](../02_APP_WORKFLOWS.md#10-handover-creation).

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [LineHandoverCard](./LineHandoverCard.md)
- [FaletScreen](./FaletScreen.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `LineHandoverService`
