# SettingsHubScreen

## 1. Screen Identity

- Name: `SettingsHubScreen`
- File path: `lib/presentation/screens/settings_hub_screen.dart`
- Widget type: `StatelessWidget`
- Where it is used: pushed from `PalletizingScreen` via the settings icon

## 2. Purpose

This screen is the top-level settings hub for the active app. It routes operators or administrators into device-key, printer, and label-preset configuration flows.

## 3. UI Structure

- blue `AppBar` titled `الإعدادات`
- responsive `GridView.count`
- three setting cards:
  - `إعدادات الجهاز`
  - `إعدادات الطابعات`
  - `أحجام الملصقات`
- each card contains icon, title, description, and chevron

## 4. State Management

- No provider usage
- No local mutable state
- Pure navigation surface

## 5. API Integration

- No direct API calls
- Navigation targets may trigger their own storage or local-printing behavior:
  - `DeviceSettingsScreen`
  - `PrinterSettingsScreen`
  - `PresetSettingsScreen`

## 6. User Actions

- Tap the device settings card
- Tap the printer settings card
- Tap the label preset settings card
- Return to the previous screen with back navigation

## 7. Business Rules in UI

- Only three settings modules are exposed in the current runtime.
- Card layout is single-column on mobile and two-column on wider layouts.
- The screen assumes users reach it from an already-running palletizing session; it does not perform its own guard checks.

## 8. Edge Cases

- There is no loading or error state because all content is static.
- In two-column mode, the three-card layout leaves one implicit empty grid cell.

## 9. Dependencies

- `DeviceSettingsScreen`
- `PrinterSettingsScreen`
- `PresetSettingsScreen`
- `ResponsiveHelper`

## 10. Risks / Pitfalls

- This hub is navigation-only, so any future settings module needs manual wiring here.
- There is no role-based gating at this screen level in current code.

## 11. AI Agent Notes

- Keep this screen simple and discoverable; it is the settings root, not a workflow surface.
- If you add new settings routes, verify both mobile and wide-screen card layouts.
- Review `PalletizingScreen` if you change how users enter settings.

## Related Screens

- [PalletizingScreen](./PalletizingScreen.md)
- [DeviceSettingsScreen](./DeviceSettingsScreen.md)
- [PrinterSettingsScreen](./PrinterSettingsScreen.md)
- [PresetSettingsScreen](./PresetSettingsScreen.md)

## Related Services

- `PrintingProvider`
- `AuthLocalStorage`

## Related Backend Concepts

- device-key configuration for `LineStateService`
- local printing configuration
