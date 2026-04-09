# ReprintDialog

## 1. Screen Identity

- Name: private `_ReprintDialog`
- File path: `lib/presentation/widgets/session_drilldown_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `SessionDrilldownDialog` when the operator presses the print icon for a pallet row

## 2. Purpose

This dialog performs a local label reprint for an already-created pallet and records the print attempt against the backend line API.

## 3. UI Structure

- alert-style dialog with top-left close button
- status icon that changes across idle, printing, success, and failure
- title that flips from `إعادة طباعة الملصق` to `تمت الطباعة بنجاح`
- pallet info card showing product, serial number, quantity, and created date
- optional error banner
- printer info banner, including a quick `اختيار` action when no printer is selected
- action area:
  - print / retry button
  - done button after success

## 4. State Management

- Local state:
  - `_isPrinting`
  - `_printSuccess`
  - `_printError`
- Reads `PrintingProvider` for:
  - printer availability
  - selected printer
  - local print execution
- Reads `PalletizingProvider` only to log the print attempt after printing completes

## 5. API Integration

- No backend call is made before the local print starts
- Local print execution goes through `PrintingProvider.print(scannedValue: pallet.scannedValue, copies: 1)`
- After the print result returns, the dialog logs the attempt through:
  - `POST /palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts`
- Related workflow doc:
  - [Print Flow](../02_APP_WORKFLOWS.md#8-print-flow)

## 6. User Actions

- Open the printer selector if no printer exists or no printer is selected
- Tap `طباعة الملصق`
- Retry after a failed print
- Close the dialog
- Tap `تم` after a successful print

## 7. Business Rules in UI

- Reprint requires a selected printer.
- If there are no saved printers, the dialog first sends the user to `PrinterSelectorDialog`.
- Print copies are hardcoded to `1`.
- Backend print-attempt logging uses the selected printer's name as `printerIdentifier`, or `UNKNOWN` if absent.
- Successful printing changes the dialog into a completion state rather than auto-closing it.

## 8. Edge Cases

- If the selector closes and there are still no printers, the dialog sets `_printError` to `لم يتم إضافة طابعة`.
- If a printer list exists but no printer is selected after the selector closes, printing silently stops without setting a new error.
- `PalletizingProvider.logPrintAttempt()` returns `false` on failure, but the dialog does not surface that failure to the operator.
- A print failure keeps the dialog open and relabels the main action as `إعادة المحاولة`.

## 9. Dependencies

- `PrintingProvider`
- `PalletizingProvider`
- `SessionPalletDetail`
- `SessionProductTypeGroup`
- frontend `ProductionLine`
- `PrinterSelectorDialog`

## 10. Risks / Pitfalls

- Backend print logging is best-effort only; the operator can see local print success even if the log call failed.
- Printer selection and print logging are coupled only by printer name, not a stable printer ID.
- The dialog assumes `scannedValue` is sufficient for label regeneration; if label data requirements expand, this path will need revisiting.

## 11. AI Agent Notes

- Do not move `logPrintAttempt()` ahead of local printing unless backend expectations change.
- If you redesign printing UX, preserve the current fallback path that asks for a printer when needed.
- Review `PrintingProvider.print()`, `PrinterClient`, and label rendering before changing the scanned-value contract.

## Related Screens

- [SessionDrilldownDialog](./SessionDrilldownDialog.md)
- [PrinterSelectorDialog](./PrinterSelectorDialog.md)
- [AddPrinterDialog](./AddPrinterDialog.md)

## Related Services

- `PrintingProvider`
- `PalletizingProvider`

## Related Backend Concepts

- `PalletizingService`
- print-attempt logging for pallet labels
