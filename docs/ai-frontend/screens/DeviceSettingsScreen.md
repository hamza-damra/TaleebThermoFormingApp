# DeviceSettingsScreen

## 1. Screen Identity

- Name: `DeviceSettingsScreen`
- File path: `lib/presentation/screens/device_settings_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: active runtime surface from `DeviceKeyWrapper` during initial setup, and later from `SettingsHubScreen`

## 2. Purpose

This screen manages the device key used by the palletizing app to authenticate line API calls through the `X-Device-Key` header.

## 3. UI Structure

- two modes:
  - setup mode: no app bar, onboarding-style header, save button labeled `حفظ والمتابعة`
  - normal settings mode: standard `AppBar`
- informational card explaining device-key purpose
- obscured text field for the device key with visibility toggle
- optional saved-key indicator
- inline success/error message banners
- save button
- connection-test button

## 4. State Management

- Pure local state
- Uses `AuthLocalStorage` directly instead of a provider
- Tracks:
  - `_isLoading`
  - `_isTesting`
  - `_hasKey`
  - `_obscureKey`
  - `_errorMessage`
  - `_successMessage`
- Loads an existing key from secure storage in `initState()`

## 5. API Integration

- Save path:
  - no network call
  - writes the key to secure storage via `AuthLocalStorage.saveDeviceKey()`
- Test path:
  - writes the key to secure storage first
  - then calls `GET /palletizing-line/bootstrap` directly using `HttpClient`
  - sets headers:
    - `X-Device-Key`
    - `Accept: application/json`
- Success condition is strict:
  - HTTP `200`
  - response body parses to JSON
  - `data['success'] == true`
- Related workflow docs:
  - [Device Setup and Connection Test](../02_APP_WORKFLOWS.md#1-device-setup-and-connection-test)
  - [Bootstrap Flow](../02_APP_WORKFLOWS.md#2-bootstrap-flow)

## 6. User Actions

- Type or replace the device key
- Toggle key visibility
- Save the key locally
- Test the key against the bootstrap endpoint
- In setup mode, continue into the app after save through `onDeviceKeyConfigured`

## 7. Business Rules in UI

- Empty key is rejected on both save and test.
- Save does not validate the key with the backend.
- Test always stores the key first, then validates it against the backend.
- In setup mode, successful save triggers `onDeviceKeyConfigured`; connection test does not.

## 8. Edge Cases

- A previously saved key is preloaded and marks `_hasKey = true`.
- Non-200 or non-`success: true` bootstrap responses are treated as invalid key / rejected connection.
- Network errors collapse into `فشل الاتصال بالخادم - تحقق من الشبكة والمفتاح`.
- Invalid JSON in the response body is tolerated, but the test then fails unless the success shape is present.

## 9. Dependencies

- `AuthLocalStorage`
- `AppConfig.baseUrl`
- direct `dart:io` `HttpClient`

## 10. Risks / Pitfalls

- Saving a key does not prove it is valid, so setup can continue with an unverified key if the user presses save without testing.
- The connection test persists the entered key before validation, so a bad key can overwrite a previously working one.
- This screen bypasses the shared `ApiClient`, so any future auth-header or base-request changes must be mirrored here manually.

## 11. AI Agent Notes

- Preserve the `X-Device-Key` test path unless device provisioning is redesigned globally.
- If you change the bootstrap response contract, update both this screen and `PalletizingProvider.loadBootstrap()`.
- Before adding stricter setup gating, verify how `DeviceKeyWrapper` should react to saved-but-invalid keys.

## Related Screens

- [PalletizingScreen](./PalletizingScreen.md)
- [SettingsHubScreen](./SettingsHubScreen.md)

## Related Services

- `AuthLocalStorage`
- `ApiClient` (adjacent, not used directly here)

## Related Backend Concepts

- `LineStateService`
- device-key authorization for `/palletizing-line/bootstrap`
