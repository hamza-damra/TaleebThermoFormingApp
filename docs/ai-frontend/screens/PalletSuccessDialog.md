# PalletSuccessDialog

## 1. Screen Identity

- Name: `PalletSuccessDialog`
- File path: `lib/presentation/widgets/pallet_success_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: shown after successful pallet creation and after successful FALET-to-pallet conversion

## 2. Purpose

This dialog confirms pallet creation, displays pallet metadata, and runs the immediate label-print flow.

## 3. UI Structure

- status icon area
- product image via `ProductTypeImage` when available
- pallet metadata rows
- active printer info banner
- close button
- print or retry-print action button

## 4. State Management

- Local dialog state:
  - `_isPrinting`
  - `_printSuccess`
  - `_printError`
- Reads `PrintingProvider` for selected printer and print execution
- Reads `PalletizingProvider` only when logging print attempts

## 5. API Integration

- Local socket print through `PrintingProvider.print()`
- After local print attempt:
  - `POST /palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts`
- Related workflow:
  - [Print flow](../02_APP_WORKFLOWS.md#8-print-flow)

## 6. User Actions

- Close dialog
- Start print
- Retry print after a failure
- Open `PrinterSelectorDialog` indirectly when no printer is configured

## 7. Business Rules in UI

- Printing is blocked until a printer exists and one is selected.
- Print success changes the dialog headline and hides the action button.
- Printer info banner only shows when a selected printer exists.
- Printer identifier logged to backend is the selected printer name.

## 8. Edge Cases

- No printers: opens printer selector; if still none, shows local error.
- Print failure: keeps dialog open and shows retry button.
- Print-attempt logging failure does not produce separate UI feedback.

## 9. Dependencies

- `PrintingProvider`
- `PalletizingProvider`
- `PrinterSelectorDialog`
- `ProductTypeImage`
- `PalletCreateResponse`

## 10. Risks / Pitfalls

- This dialog couples local printing and backend logging; changing one path can silently affect the other.
- Product images use bearer-token loading while the palletizing flow uses device-key APIs.
- The dialog assumes the created pallet’s `scannedValue` is the print payload.

## 11. AI Agent Notes

- If you change the printed payload, verify `LabelRenderer`, `PrinterClient`, and backend print-attempt logging together.
- Preserve the current behavior where successful printing is optional; pallet creation itself is already complete before printing starts.

## Related Screens

- [CreatePalletDialog](./CreatePalletDialog.md)
- [PrinterSelectorDialog](./PrinterSelectorDialog.md)
- [ReprintDialog](./ReprintDialog.md)

## Related Services

- `PrintingProvider`
- `PalletizingProvider`

## Related Backend Concepts

- `PalletizingService`
- print-attempt logging endpoint
