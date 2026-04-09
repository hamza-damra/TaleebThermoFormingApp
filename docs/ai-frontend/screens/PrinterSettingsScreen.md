# PrinterSettingsScreen

## 1. Screen Identity

- Name: `PrinterSettingsScreen`
- File path: `lib/presentation/screens/printer_settings_screen.dart`
- Widget type: `StatelessWidget`
- Where it is used: pushed from `SettingsHubScreen` and reachable from `PrinterSelectorDialog`

## 2. Purpose

This screen is the full printer-management surface for local label printing. It exposes add, select, set-default, edit, test, and delete actions for saved printers.

## 3. UI Structure

- blue `AppBar` titled `إعدادات الطابعات`
- `Consumer<PrintingProvider>` body
- section header with `إضافة طابعة` button
- empty state when there are no printers
- list of printer cards
- each card shows:
  - printer icon
  - printer name
  - optional `افتراضي` badge
  - IP and port
  - selected checkmark
  - popup menu for actions
- inline/private dialogs handled inside this screen:
  - delete confirmation dialog
  - connection-test loading dialog
  - connection-test result dialog

## 4. State Management

- Watches `PrintingProvider`
- Reads:
  - `printers`
  - `selectedPrinter`
- Mutates provider state via:
  - `addPrinter`
  - `selectPrinter`
  - `setDefaultPrinter`
  - `updatePrinter`
  - `deletePrinter`
  - `testConnection`
- Opens [EditPrinterDialog](./EditPrinterDialog.md) for edits and [AddPrinterDialog](./AddPrinterDialog.md) for creation

## 5. API Integration

- No backend API calls
- All operations target local persistence and network printer connectivity through `PrintingProvider`
- Test connection is a direct local network check through `PrinterClient`, surfaced here as dialogs

## 6. User Actions

- Add a printer
- Tap a card to select a printer
- Use popup menu actions:
  - `اختيار`
  - `تعيين كافتراضي`
  - `تعديل`
  - `اختبار الاتصال`
  - `حذف`

## 7. Business Rules in UI

- The `تعيين كافتراضي` action is hidden when the printer is already marked default.
- Card tap selects a printer even if it is not default.
- Selection and default are represented separately in the UI.
- Delete requires explicit confirmation.
- Connection testing is informational only; it does not change saved printer data.

## 8. Edge Cases

- Empty storage shows a dedicated `لا توجد طابعات مضافة` state.
- If the selected printer is deleted, `PrintingProvider.deletePrinter()` falls back to the repository default printer.
- Test connection only returns success/failure; it does not expose transport details.
- The loading dialog for printer test is `barrierDismissible: false` until the test completes.

## 9. Dependencies

- `PrintingProvider`
- `PrinterConfig`
- [AddPrinterDialog](./AddPrinterDialog.md)
- [EditPrinterDialog](./EditPrinterDialog.md)

## 10. Risks / Pitfalls

- `setDefaultPrinter()` updates stored default flags but does not automatically select that printer, so default status and active selection can diverge.
- New printers created through `AddPrinterDialog` carry `isDefault: true`, and `addPrinter()` does not normalize prior defaults, so multiple printers can be marked default in storage.
- The inline test and delete dialogs are private to this screen; moving their logic out requires preserving the current UX sequence.

## 11. AI Agent Notes

- Preserve the distinction between `selectedPrinter` and `isDefault`.
- If you fix default-normalization behavior, update `AddPrinterDialog`, `PrintingProvider`, and `PrinterRepositoryImpl` together.
- Before changing delete behavior, confirm how fallback printer selection should work for reprint flows.

## Related Screens

- [SettingsHubScreen](./SettingsHubScreen.md)
- [PrinterSelectorDialog](./PrinterSelectorDialog.md)
- [AddPrinterDialog](./AddPrinterDialog.md)
- [EditPrinterDialog](./EditPrinterDialog.md)

## Related Services

- `PrintingProvider`
- `PrinterRepositoryImpl`

## Related Backend Concepts

- local printer configuration only; no backend dependency
