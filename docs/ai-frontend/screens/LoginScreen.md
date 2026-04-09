# LoginScreen

## 1. Screen Identity

- Name: `LoginScreen`
- File path: `lib/presentation/screens/login_screen.dart`
- Widget type: `StatefulWidget`
- Where it is used: present in the repository but not wired into the current `main.dart` entry flow

## 2. Purpose

This is the legacy PIN-based operator login screen built on `AuthProvider` and the bearer-token `/auth/pin-login` flow.

## 3. UI Structure

- gradient hero background
- logo / title header `تكوين طبليات`
- centered login card
- four one-digit PIN input boxes
- inline error banner
- `دخول` button with loading state

## 4. State Management

- Local state:
  - four digit controllers
  - four focus nodes
  - `_isSubmitting`
- Uses `Consumer<AuthProvider>` for:
  - `errorMessage`
  - `isLoading`
- Calls `AuthProvider.pinLogin(employeeCode: code)`

## 5. API Integration

- Indirect call through `AuthProvider` to:
  - `POST /auth/pin-login`
- `AuthRepositoryImpl` then:
  - validates the returned user role against `PALLETIZER`, `DRIVER`, or `OFFICER`
  - stores bearer token and user info in secure storage
- This surface is legacy relative to the current device-key-first runtime

## 6. User Actions

- Enter each PIN digit
- Backspace across fields
- Auto-submit after entering the fourth digit
- Tap the login button manually

## 7. Business Rules in UI

- PIN length is exactly four digits.
- Each box accepts digits only and one character max.
- Focus auto-advances after each entered digit.
- Failed login clears the PIN and returns focus to the first field.
- Login is blocked when fewer than four digits are present or while submission is already in progress.

## 8. Edge Cases

- Success handling is `unclear from code` inside this screen because it does not navigate on its own; it appears to expect a higher-level auth flow to react to provider state.
- Because `_isSubmitting` is only reset on failure, a successful login would leave the local submitting flag true if the screen stayed mounted.
- Pasting multiple characters into one box is normalized to the last entered character.
- This screen will fail if used without an `AuthProvider` above it in the widget tree.

## 9. Dependencies

- `AuthProvider`
- `AuthRepositoryImpl`
- `AppTheme`
- legacy auth models and secure storage

## 10. Risks / Pitfalls

- `AuthProvider` is not registered in the current `main.dart`, so this screen is not safe to re-enable without restoring provider wiring.
- The screen uses the legacy bearer-token auth stack, which is separate from the active device-key palletizing flow.
- The local `_isSubmitting` flag is asymmetrical across success and failure paths.

## 11. AI Agent Notes

- Treat this screen as legacy/unwired unless the app intentionally reintroduces login-based entry.
- If you revive it, verify navigation, provider registration, and interaction with `DeviceKeyWrapper`.
- Review `AuthProvider`, `AuthRepositoryImpl`, and secure-storage usage before changing the PIN auth contract.

## Related Screens

- [DeviceSettingsScreen](./DeviceSettingsScreen.md)
- [PalletizingScreen](./PalletizingScreen.md)

## Related Services

- `AuthProvider`
- `AuthRepositoryImpl`
- `AuthLocalStorage`

## Related Backend Concepts

- legacy `LineAuthorizationService`-adjacent auth flow
- `/auth/pin-login`
