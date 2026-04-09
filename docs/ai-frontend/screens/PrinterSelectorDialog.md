# PrinterSelectorDialog

## 1. Screen Identity

- Name: `PrinterSelectorDialog`
- File path: `lib/presentation/widgets/printer_selector_dialog.dart`
- Widget type: `StatelessWidget`
- Where it is used: opened from print-related flows, especially `ReprintDialog`, when the app needs the operator to choose or add a printer

## 2. Purpose

This dialog lets the operator pick the active printer quickly without leaving the current flow, while still providing shortcuts to add printers or open full printer settings.

## 3. UI Structure

- modal dialog with title `اختر الطابعة`
- empty state when no printers exist
- printer list when printers are available
- bottom actions:
  - `الإعدادات`
  - `إضافة طابعة`
- small-screen layout stacks those actions vertically

## 4. State Management

- Uses `Consumer<PrintingProvider>`
- Reads:
  - `provider.printers`
  - `provider.selectedPrinter`
- No local mutable state
- Optional `onPrinterSelected` callback lets the caller react after selection

## 5. API Integration

- No backend API calls
- Local persistence and selection go through `PrintingProvider`:
  - `selectPrinter(printer)`
  - `addPrinter(printer)` after `AddPrinterDialog`
- Navigates to `PrinterSettingsScreen` for fuller local management

## 6. User Actions

- Select a listed printer
- Close the dialog
- Open `AddPrinterDialog`
- Open `PrinterSettingsScreen`

## 7. Business Rules in UI

- A tap on a printer immediately selects it and closes the dialog.
- The selected printer is visually highlighted.
- The settings action closes the selector before navigating to the full screen.
- The dialog does not expose delete, edit, or default-setting actions; those live in `PrinterSettingsScreen`.

## 8. Edge Cases

- If no printers are saved, the dialog shows a dedicated empty state but still exposes add/settings actions.
- Adding a printer from this dialog does not automatically close the selector unless the caller or user does so afterward.
- The dialog depends on provider state already being loaded by `PrintingProvider.loadSavedSettings()`.

## 9. Dependencies

- `PrintingProvider`
- `PrinterConfig`
- [AddPrinterDialog](./AddPrinterDialog.md)
- [PrinterSettingsScreen](./PrinterSettingsScreen.md)

## 10. Risks / Pitfalls

- Selection state and default-printer state are not the same concept; this dialog highlights the selected printer only.
- Because the add path uses `AddPrinterDialog`, newly created printers may carry `isDefault: true` without normalizing older defaults.
- Opening full settings closes the current modal first, so callers should not expect to resume inside the selector automatically.

## 11. AI Agent Notes

- Preserve this dialog as the lightweight print-time chooser; avoid overloading it with full CRUD complexity.
- If you change printer-add semantics, verify both this dialog and `PrinterSettingsScreen` stay consistent.
- Review `PrintingProvider.selectPrinter()` persistence behavior before changing selection rules.

## Related Screens

- [ReprintDialog](./ReprintDialog.md)
- [AddPrinterDialog](./AddPrinterDialog.md)
- [PrinterSettingsScreen](./PrinterSettingsScreen.md)

## Related Services

- `PrintingProvider`

## Related Backend Concepts

- local printer configuration only; no backend dependency
