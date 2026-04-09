# CreatePalletDialog

## 1. Screen Identity

- Name: `CreatePalletDialog`
- File path: `lib/presentation/widgets/create_pallet_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `ProductionLineSection` when the create button is pressed

## 2. Purpose

This dialog gathers the minimal input required to create a pallet on the current line: product type and quantity.

## 3. UI Structure

- alert dialog title with line label
- product picker field
- quantity stepper with manual numeric input
- cancel and confirm actions

## 4. State Management

- Local dialog state only
- Stores:
  - selected product type
  - quantity
  - quantity controller
- Initializes from the line’s current selected product when available

## 5. API Integration

- No direct API call from this dialog
- Returns a map to `ProductionLineSection`, which then calls:
  - `POST /palletizing-line/lines/{lineId}/pallets`

## 6. User Actions

- Open searchable product picker
- Increase quantity
- Decrease quantity
- Type quantity manually
- Cancel or confirm

## 7. Business Rules in UI

- Confirm is enabled only when:
  - a product is selected
  - quantity is greater than zero
- If initialized with a product, quantity defaults to that product’s `packageQuantity`.
- If there is no initial product, quantity defaults to `20`.
- The dialog no longer asks for operator selection; operator identity is line-scoped and backend-driven.

## 8. Edge Cases

- Manual input accepts any non-negative integer while typing, but confirm still requires `> 0`.
- There is no UI validation for package-size multiples or upper bounds.
- `SearchableProductDropdown` exists elsewhere in the repo but is not used here; active flow uses `SearchablePickerDialog`.

## 9. Dependencies

- `SearchablePickerDialog`
- `ProductType`
- frontend `ProductionLine` enum

## 10. Risks / Pitfalls

- Quantity typing updates `_quantity` directly without extra sanitization beyond integer parsing.
- Business validation is split: this dialog handles only local positivity rules, while backend enforces the real create-pallet contract.

## 11. AI Agent Notes

- Keep this dialog lightweight; it is optimized for fast operator input.
- If adding new pallet fields, verify that `PalletizingProvider.createPallet()` and `PalletCreateResponse` still match the backend contract.
- Do not reintroduce operator picking without rethinking the line-authorization model.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [SearchablePickerDialog](./SearchablePickerDialog.md)
- [PalletSuccessDialog](./PalletSuccessDialog.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `PalletizingService`
