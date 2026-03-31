# Taleeb ThermoForming - Palletizing App

A Flutter-based industrial palletizing application for **Taleeb ThermoForming**, designed to manage pallet formation, operator workflows, shift handovers, and direct QR label printing on the factory floor.

## Features

- **Operator Palletizing Workflow** - Create and manage pallets per production line with operator assignment, product type selection, and quantity tracking.
- **Shift Handover System** - Structured shift handover flow between outgoing and incoming operators, with pending handover blocking, confirmation, and dispute/rejection support.
- **QR Code Label Printing** - Direct Bluetooth/network thermal printer integration using TSPL commands, with customizable label presets and live QR rendering.
- **PIN-Based Login** - Lightweight mobile authentication designed for factory floor use.
- **Multi-Production Line Support** - Manage multiple production lines simultaneously with per-line operator and product type state.
- **Responsive UI** - Arabic RTL interface with adaptive layouts for mobile and tablet devices.
- **Offline-Ready Storage** - Local settings and printer configurations persisted via Hive and Flutter Secure Storage.

## Architecture

The project follows **Clean Architecture** with clear separation of concerns:

```
lib/
  core/           # Configuration, DI, theme, constants, exceptions
  data/           # API client, local storage, models, repository implementations
  domain/         # Entities and abstract repository contracts
  presentation/   # Providers (state management), screens, widgets
  printing/       # TSPL label rendering, printer client, unit conversion
```

- **State Management**: Provider (ChangeNotifier)
- **Networking**: Dio with JWT Bearer authentication
- **Local Storage**: Hive (printer configs, presets), Flutter Secure Storage (auth tokens)
- **Printing**: Custom TSPL builder for thermal label printers

## Supported Platforms

| Platform | Status    |
| -------- | --------- |
| Android  | Supported |
| iOS      | Supported |
| Web      | Supported |
| Windows  | Supported |
| Linux    | Supported |
| macOS    | Supported |

## Prerequisites

- Flutter SDK `>=3.10.8`
- Dart SDK (bundled with Flutter)
- A running backend API instance (configured in `lib/core/config.dart`)

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/hamza-damra/TaleebThermoFormingApp.git
   cd TaleebThermoFormingApp
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Generate Hive adapters** (if models change)

   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

## Key Dependencies

| Package                  | Purpose                              |
| ------------------------ | ------------------------------------ |
| `provider`               | State management                     |
| `dio`                    | HTTP client                          |
| `flutter_secure_storage` | Secure token storage                 |
| `hive` / `hive_flutter`  | Local NoSQL storage                  |
| `qr_flutter` / `qr`      | QR code generation                   |
| `image`                  | Image processing for label rendering |
| `google_fonts`           | Cairo font for Arabic typography     |
| `uuid`                   | Unique identifier generation         |

## Documentation

Detailed technical documentation is available in the [`docs/`](docs/) directory covering backend integration, handover flows, printing setup, and architectural references.

## License

This project is proprietary software for Taleeb ThermoForming. All rights reserved.
