# DisposeFaletDialog

## 1. Screen Identity

- Name: `DisposeFaletDialog`
- File path: `lib/presentation/widgets/dispose_falet_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `FaletScreen` before sending a FALET disposal request

## 2. Purpose

This dialog confirms irreversible FALET disposal and optionally captures the operator's reason for the disposal.

## 3. UI Structure

- warning-themed modal dialog
- emphasized delete icon and red title
- product-and-quantity warning card
- multiline optional reason input
- cancel and `تأكيد الإتلاف` actions

## 4. State Management

- Local dialog state only
- Uses `_reasonController`
- No provider subscription

## 5. API Integration

- No direct API call
- Returns:
  - `null` on cancel
  - trimmed reason string on confirm, including empty string when no reason is entered
- `FaletScreen` converts empty string to `null` and calls:
  - `POST /palletizing-line/lines/{lineId}/falet/dispose`

## 6. User Actions

- Review the FALET item being disposed
- Enter an optional reason
- Cancel the operation
- Confirm disposal

## 7. Business Rules in UI

- The reason is optional.
- The dialog frames disposal as final and destructive but does not require a second typed confirmation.
- Product name and quantity are shown so the operator can verify the target before confirming.

## 8. Edge Cases

- Empty reason is allowed and becomes `null` in the caller.
- No inline validation or length limit is enforced on the optional note.
- Backend rejection is not handled here; it is surfaced by `FaletScreen` after the provider call.

## 9. Dependencies

- `FaletItem`
- `ProductType.formatCompactName`
- caller: `FaletScreen`

## 10. Risks / Pitfalls

- The dialog itself does not lock against accidental double taps; the caller is responsible for API-side handling.
- If disposal starts requiring a mandatory reason, both this dialog and `DisposeFaletRequest` must be updated together.

## 11. AI Agent Notes

- Keep the destructive tone clear; this is one of the few irreversible actions in the palletizing flow.
- If you add validation, make sure `FaletScreen` still handles empty vs null reasons consistently.
- Review backend disposal auditing expectations before changing the reason field.

## Related Screens

- [FaletScreen](./FaletScreen.md)
- [ConvertFaletToPalletDialog](./ConvertFaletToPalletDialog.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `FaletService`
