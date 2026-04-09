# ProductSwitchDialog

## 1. Screen Identity

- Name: `ProductSwitchDialog`
- File path: `lib/presentation/widgets/product_switch_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `ProductionLineSection` when the operator selects a different product from the current one

## 2. Purpose

This dialog collects leftover-carton information before switching the active product on a line.

## 3. UI Structure

- dialog with switch icon and title
- before/after product text
- question about leftover cartons from the previous product
- two-option toggle (`no leftovers` / `yes leftovers`)
- conditional loose-count input
- cancel and confirm actions

## 4. State Management

- Local dialog state only
- Stores:
  - whether leftovers exist
  - loose-count controller
  - validation error

## 5. API Integration

- No direct API call from the dialog
- Returns:
  - `null` when cancelled
  - `0` when no leftovers exist
  - positive loose count when leftovers exist
- Parent `ProductionLineSection` then calls:
  - `POST /palletizing-line/lines/{lineId}/product-switch`

## 6. User Actions

- Confirm there are no leftovers
- Confirm there are leftovers
- Enter loose count
- Cancel or confirm switch

## 7. Business Rules in UI

- No-leftover path returns `0`.
- Leftover path requires a positive integer.
- Dialog is only used for actual product changes; same-product picks never open it.

## 8. Edge Cases

- Empty or non-positive loose count blocks confirmation when leftovers are declared.
- The dialog does not validate against backend stock or historical session data; it only enforces numeric positivity.

## 9. Dependencies

- `ProductType`
- `ResponsiveHelper`

## 10. Risks / Pitfalls

- The dialog captures only loose cartons, not richer product-switch metadata.
- If backend semantics for `loosePackageCount` change, this dialog will need to change with the endpoint contract.

## 11. AI Agent Notes

- Preserve the `0` return path because the provider explicitly sends `looseCount: 0` when no leftovers exist.
- If you add fields here, also update `ProductionLineSection._handleProductSelection()` and the product-switch endpoint docs.

## Related Screens

- [ProductionLineSection](./ProductionLineSection.md)
- [FaletScreen](./FaletScreen.md)

## Related Services

- `PalletizingProvider`

## Related Backend Concepts

- `PalletizingService`
