# ConvertFaletToPalletDialog

## 1. Screen Identity

- Name: `ConvertFaletToPalletDialog`
- File path: `lib/presentation/widgets/convert_falet_to_pallet_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `FaletScreen` before calling the FALET conversion endpoint

## 2. Purpose

This dialog lets the operator decide whether the existing FALET quantity should be converted as-is or combined with an additional fresh quantity to form a pallet.

## 3. UI Structure

- modal dialog with themed header icon
- product summary card showing compact product name and current FALET quantity
- toggle labeled `إضافة كمية جديدة؟`
- conditional numeric text field for additional fresh quantity
- calculated total quantity display
- inline validation banner
- cancel and confirm buttons

## 4. State Management

- Local dialog state only
- Stores:
  - `_addFresh`
  - `_freshController`
  - `_validationError`
- Computed values:
  - `_freshValue`
  - `_totalQuantity`
- No provider is watched directly here

## 5. API Integration

- No direct API call
- Returns an `int` to the caller:
  - `null` on cancel
  - `0` when converting without added fresh quantity
  - positive integer when extra quantity is supplied
- `FaletScreen` consumes the result and then calls:
  - `POST /palletizing-line/lines/{lineId}/falet/convert-to-pallet`

## 6. User Actions

- Review current FALET product and quantity
- Enable or disable the add-fresh toggle
- Type an additional quantity
- Cancel the operation
- Confirm conversion

## 7. Business Rules in UI

- Additional quantity is optional.
- When `إضافة كمية جديدة؟` is off, confirm returns `0`.
- When the toggle is on, confirm requires a positive integer greater than zero.
- Input is digits-only and centered for fast factory-floor entry.

## 8. Edge Cases

- Toggling the add-fresh switch off clears the entered value and validation error.
- Empty, zero, or non-parsable additional quantity is rejected only when `_addFresh` is true.
- There is no upper-bound validation or package-multiple validation in the dialog itself.

## 9. Dependencies

- `FaletItem`
- `ProductType.formatCompactName`
- caller: `FaletScreen`

## 10. Risks / Pitfalls

- The dialog calculates only UI totals; the backend remains authoritative for whether the conversion is valid.
- Because the result type is an `int`, introducing fractional quantities would require contract changes across UI and backend.

## 11. AI Agent Notes

- Preserve the current return contract because `FaletScreen` assumes `null` means cancel and `0` means no extra fresh quantity.
- If you add more inputs, keep the confirm flow fast; this dialog is part of an operational leftover-handling workflow.
- Recheck `FaletConvertToPalletRequest` before changing quantity semantics.

## Related Screens

- [FaletScreen](./FaletScreen.md)
- [PalletSuccessDialog](./PalletSuccessDialog.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `FaletService`
- `PalletizingService`
