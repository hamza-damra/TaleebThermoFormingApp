# PresetFormDialog

## 1. Screen Identity

- Name: private `_PresetFormDialog`
- File path: `lib/presentation/screens/preset_settings_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: opened from `PresetSettingsScreen` for both add and edit flows

## 2. Purpose

This dialog captures the printable size metadata for a label preset: name, width, height, and margin in millimeters.

## 3. UI Structure

- modal dialog with measurement icon header
- title that changes between add and edit usage
- form fields for:
  - preset name
  - width in mm
  - height in mm
  - margin in mm
- cancel and save actions

## 4. State Management

- Local form state:
  - `_formKey`
  - `_nameController`
  - `_widthController`
  - `_heightController`
  - `_marginController`
- Controllers preload values when editing an existing preset
- Returns a `LabelPreset` to the caller; does not save directly

## 5. API Integration

- No backend API calls
- Returns a `LabelPreset` to the caller
- `PresetSettingsScreen` then persists it through:
  - `PrintingProvider.addPreset()`
  - `PrintingProvider.updatePreset()`

## 6. User Actions

- Enter or edit preset name
- Enter width, height, and margin values
- Cancel
- Save the preset

## 7. Business Rules in UI

- Name is required.
- Width must be a positive number.
- Height must be a positive number.
- Margin must be a non-negative number.
- New presets return with empty `id`; repository code assigns the UUID later.
- Edited presets preserve their existing `id`.

## 8. Edge Cases

- Numeric fields accept decimal keyboard input because dimensions are parsed as `double`.
- Field-level validation blocks save, but there is no live preview of the label output.
- The dialog itself does not prevent editing default presets; that guard lives in `PresetSettingsScreen` and `PresetRepositoryImpl`.

## 9. Dependencies

- `LabelPreset`
- `PrintingProvider`
- caller: `PresetSettingsScreen`

## 10. Risks / Pitfalls

- Millimeter semantics are implicit in field labels only; changing units would affect rendering expectations across the printing stack.
- The dialog trusts repository code to generate IDs for new presets.
- Any change here must stay aligned with `LabelRenderer` and local preset serialization.

## 11. AI Agent Notes

- Preserve the mm-based contract unless label rendering is updated at the same time.
- If you add more label layout fields, update both the preset entity and its Hive model mapping.
- Keep validation rules synchronized with the actual capabilities of the renderer and printer output.

## Related Screens

- [PresetSettingsScreen](./PresetSettingsScreen.md)

## Related Services

- `PrintingProvider`
- `PresetRepositoryImpl`

## Related Backend Concepts

- local label-preset configuration only; no backend dependency
