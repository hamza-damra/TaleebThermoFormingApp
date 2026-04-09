# EditPrinterDialog

## 1. Screen Identity

- Name: private `_EditPrinterDialog`
- File path: `lib/presentation/screens/printer_settings_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `PrinterSettingsScreen` popup menu action `تعديل`

## 2. Purpose

This dialog edits an existing saved printer configuration while preserving the printer's identity and other metadata.

## 3. UI Structure

- modal dialog with edit icon header
- form fields for:
  - printer name
  - IP address
  - port
- cancel and `حفظ التعديلات` actions

## 4. State Management

- Local form state with:
  - `_formKey`
  - `_nameController`
  - `_ipController`
  - `_portController`
- Preloads controller values from the incoming `PrinterConfig`
- Returns an updated entity to the caller; does not save directly

## 5. API Integration

- No backend API calls
- Returns `printer.copyWith(...)` to the caller
- `PrinterSettingsScreen` then persists the result through `PrintingProvider.updatePrinter()`

## 6. User Actions

- Edit printer name
- Edit printer IP
- Edit printer port
- Cancel
- Save changes

## 7. Business Rules in UI

- Name is required.
- IP must pass the dialog's IPv4 regex.
- Port must parse to an integer from `1` to `65535`.
- Save preserves the existing printer `id` and any unchanged fields through `copyWith`.

## 8. Edge Cases

- No test-connection step is available inside the edit flow.
- Validation errors block save but are shown only at the field level.
- The dialog uses number keyboard type for IP input, which may be awkward on some devices.

## 9. Dependencies

- `PrinterConfig`
- `PrintingProvider`
- caller: `PrinterSettingsScreen`

## 10. Risks / Pitfalls

- The dialog assumes `copyWith` preserves fields such as `isDefault`; changing entity semantics can break that assumption.
- If printer identity rules change, returning the same `id` remains critical so updates do not create duplicate records.

## 11. AI Agent Notes

- Keep validation rules aligned with [AddPrinterDialog](./AddPrinterDialog.md).
- If you add new printer fields, update both add and edit dialogs together.
- Review `PrintingProvider.updatePrinter()` if you change how selected-printer updates should behave after editing.

## Related Screens

- [PrinterSettingsScreen](./PrinterSettingsScreen.md)
- [AddPrinterDialog](./AddPrinterDialog.md)
- [PrinterSelectorDialog](./PrinterSelectorDialog.md)

## Related Services

- `PrintingProvider`
- `PrinterRepositoryImpl`

## Related Backend Concepts

- local printer configuration only; no backend dependency
