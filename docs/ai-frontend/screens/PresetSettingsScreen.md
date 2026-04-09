# PresetSettingsScreen

## 1. Screen Identity

- Name: `PresetSettingsScreen`
- File path: `lib/presentation/screens/preset_settings_screen.dart`
- Widget type: `StatelessWidget`
- Where it is used: pushed from `SettingsHubScreen`

## 2. Purpose

This screen manages the label-size presets used by the printing subsystem and lets the operator choose the active preset for future labels.

## 3. UI Structure

- blue `AppBar` titled `أحجام الملصقات`
- `Consumer<PrintingProvider>` body
- section header with `إضافة حجم` button
- empty state when no presets are available
- wrap of selectable preset chips
- chip long-press bottom sheet for custom presets only
- inline/private confirmation dialog for preset deletion

## 4. State Management

- Watches `PrintingProvider`
- Reads:
  - `presets`
  - `selectedPreset`
- Mutates provider state via:
  - `selectPreset`
  - `addPreset`
  - `updatePreset`
  - `deletePreset`
- Opens [PresetFormDialog](./PresetFormDialog.md) for create and edit

## 5. API Integration

- No backend API calls
- All preset operations are local persistence through `PrintingProvider` and `PresetRepositoryImpl`

## 6. User Actions

- Add a new preset
- Tap a preset chip to select it
- Long-press a custom preset to:
  - edit it
  - delete it

## 7. Business Rules in UI

- A preset is considered custom only when `!preset.id.startsWith('default_')`.
- Default presets cannot be edited or deleted from the UI because only custom presets get long-press actions.
- Selected preset is highlighted immediately.
- Add and edit share the same form dialog.

## 8. Edge Cases

- Empty state is possible only if provider data fails to include defaults; under normal code paths defaults are always present.
- If the selected preset is deleted, `PrintingProvider.deletePreset()` falls back to `DefaultPresets.preset50x30`.
- Long-press affordance is not visually spelled out beyond the edit icon on custom chips.

## 9. Dependencies

- `PrintingProvider`
- `LabelPreset`
- [PresetFormDialog](./PresetFormDialog.md)

## 10. Risks / Pitfalls

- New presets are added but not auto-selected.
- Default-presets immutability depends both on UI gating and repository enforcement; changing only one side is unsafe.
- Chip selection and editability are different concepts; selected default presets remain immutable.

## 11. AI Agent Notes

- Preserve the `default_` ID convention unless the entire preset persistence layer is redesigned.
- If you add preset preview rendering, verify it stays consistent with `LabelRenderer`.
- Keep edit/delete flows custom-only unless backend or product requirements explicitly change.

## Related Screens

- [SettingsHubScreen](./SettingsHubScreen.md)
- [PresetFormDialog](./PresetFormDialog.md)

## Related Services

- `PrintingProvider`
- `PresetRepositoryImpl`

## Related Backend Concepts

- local label-preset configuration only; no backend dependency
