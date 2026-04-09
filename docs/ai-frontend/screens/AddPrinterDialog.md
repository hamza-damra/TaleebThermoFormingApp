# AddPrinterDialog

## 1. Screen Identity

- Name: `AddPrinterDialog`
- File path: `lib/presentation/widgets/printer_selector_dialog.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `PrinterSelectorDialog` and `PrinterSettingsScreen` when a new printer configuration is added

## 2. Purpose

This dialog captures a printer's local network configuration, optionally tests the connection, and returns a `PrinterConfig` for persistence.

## 3. UI Structure

- modal form dialog with printer icon header
- fields for:
  - printer name
  - IP address
  - port
- optional connection-test result banner
- action row with cancel and save
- separate text button for `اختبار الاتصال بالطابعة`

## 4. State Management

- Local state:
  - `_formKey`
  - `_nameController`
  - `_ipController`
  - `_portController`
  - `_isTesting`
  - `_testResult`
- Uses `PrintingProvider.testConnection()` for live connectivity checks
- Does not save directly; it returns a `PrinterConfig` to the caller

## 5. API Integration

- No backend API integration
- Local printer test goes through `PrintingProvider.testConnection(printer)`
- Save path returns a `PrinterConfig` that the caller persists via `PrintingProvider.addPrinter()`

## 6. User Actions

- Enter printer name, IP, and port
- Run a connection test
- Cancel
- Save the printer configuration

## 7. Business Rules in UI

- Name is required.
- IP must match the dialog's IPv4 regex.
- Port is required and must be between `1` and `65535`.
- The default port is prefilled as `9100`.
- Save does not require a successful connection test first.
- The returned printer is created with `isDefault: true`.

## 8. Edge Cases

- While a test is running, the save button area is temporarily replaced by a progress indicator.
- Test failures are shown as a banner but do not block saving.
- The dialog returns a printer with empty `id`; repository code assigns the UUID later.

## 9. Dependencies

- `PrintingProvider`
- `PrinterConfig`
- callers:
  - `PrinterSelectorDialog`
  - `PrinterSettingsScreen`

## 10. Risks / Pitfalls

- The dialog always returns `isDefault: true`, but `PrintingProvider.addPrinter()` does not normalize previous defaults, so multiple printers can become default-flagged in storage.
- `keyboardType: TextInputType.number` is used for IP input even though IP addresses contain dots; actual entry depends on the device keyboard behavior.
- Save and test use the same form values, so changing validation rules must keep both paths aligned.

## 11. AI Agent Notes

- If you change how default printers are assigned, update this dialog together with `PrinterRepositoryImpl` and `PrintingProvider`.
- Consider the factory environment here: fast manual entry matters more than rich networking diagnostics.
- Preserve the contract that saving returns a config and lets the caller decide when to persist it.

## Related Screens

- [PrinterSelectorDialog](./PrinterSelectorDialog.md)
- [PrinterSettingsScreen](./PrinterSettingsScreen.md)
- [EditPrinterDialog](./EditPrinterDialog.md)

## Related Services

- `PrintingProvider`
- `PrinterRepositoryImpl`

## Related Backend Concepts

- local printer configuration only; no backend dependency
