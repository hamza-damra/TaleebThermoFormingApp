# QR Printing App - Integration Handoff Document

> **Purpose**: This document provides a comprehensive analysis of the QR Label Printer app for integration into the Palletizing app (تطبيق تكوين المشتاح).
> 
> **Target Audience**: AI agents and developers performing the integration.

---

## 1. PROJECT OVERVIEW

### What This App Does
This is a Flutter application for printing QR code labels to thermal printers (specifically XPrinter XP-410B) using TSPL commands over TCP/IP network connection.

### Main User Flow
1. User enters a value (ID/text) in a text field
2. App generates a QR code preview from the value
3. User selects a printer and label preset (size)
4. User specifies number of copies
5. User taps "Print" button
6. App renders QR + text as monochrome bitmap
7. App sends TSPL commands with bitmap to printer via TCP socket
8. Printer prints the label

### Main Technical Purpose
- Generate QR codes from arbitrary text/ID values
- Render labels with QR code + text as monochrome bitmaps
- Communicate with thermal printers via raw TCP sockets using TSPL protocol
- Manage printer configurations and label size presets

---

## 2. ARCHITECTURE SUMMARY

### Folder Structure
```
lib/
├── main.dart                    # App entry point, initializes LocalStorage
├── app.dart                     # MaterialApp with ProviderScope (Riverpod)
├── core/
│   ├── constants/
│   │   ├── app_constants.dart   # DPI, timeouts, defaults
│   │   └── tspl_constants.dart  # TSPL command strings
│   ├── errors/
│   │   └── app_exceptions.dart  # Custom exception classes
│   └── utils/
│       ├── unit_converter.dart  # mm↔dots↔bytes conversion
│       └── validators.dart      # Input validation helpers
├── data/
│   ├── datasources/
│   │   └── local_storage.dart   # Hive initialization & box access
│   └── repositories/
│       ├── preset_repository.dart
│       ├── printer_repository.dart
│       └── settings_repository.dart
├── domain/
│   └── services/
│       ├── print_service.dart      # Orchestrates print jobs
│       └── validation_service.dart # Validates print parameters
├── models/
│   ├── app_settings.dart        # User preferences (Hive model)
│   ├── label_preset.dart        # Label dimensions (Hive model)
│   ├── print_job.dart           # Print job DTO
│   └── printer_config.dart      # Printer settings (Hive model)
├── presentation/
│   ├── providers/               # Riverpod providers
│   │   ├── preset_provider.dart
│   │   ├── print_provider.dart
│   │   ├── printer_provider.dart
│   │   └── settings_provider.dart
│   ├── screens/                 # UI screens
│   │   ├── home_screen.dart
│   │   ├── preset_form_screen.dart
│   │   ├── preset_management_screen.dart
│   │   ├── printer_form_screen.dart
│   │   ├── printer_management_screen.dart
│   │   └── settings_screen.dart
│   └── widgets/                 # Reusable widgets
│       ├── copies_input.dart
│       ├── label_preview.dart
│       ├── preset_dropdown.dart
│       └── printer_dropdown.dart
└── printing/
    ├── label_renderer.dart      # QR + text → monochrome bitmap
    ├── printer_client.dart      # TCP socket communication
    └── tspl_builder.dart        # TSPL command builder
```

### State Management
- **Riverpod** (`flutter_riverpod: ^2.5.1`)
- Uses `StateNotifierProvider` for complex state (printers, presets, print state)
- Uses `StateProvider` for simple state (selected IDs, copies count, input text)
- Uses `Provider` for dependency injection (repositories, services)

### Architecture Style
- **Clean-ish Architecture** with separation:
  - `data/` → repositories and data sources
  - `domain/` → business logic services
  - `presentation/` → UI (screens, widgets, providers)
  - `printing/` → printer-specific logic (could be in domain/)
- **Logic is reasonably separated from UI** - print logic lives in services/printing layer
- **Models are independent** - no Flutter/UI dependencies in model classes

---

## 3. QR GENERATION FLOW

### Where QR Value is Entered
- **File**: `lib/presentation/screens/home_screen.dart`
- **Widget**: `TextFormField` with `_inputController`
- **State**: Value stored in `printInputProvider` (StateProvider<String>)

### QR Code Generation Implementation

#### For Preview (UI Display)
- **Package**: `qr_flutter: ^4.1.0`
- **Widget**: `QrImageView` from qr_flutter
- **Files**:
  - `lib/presentation/widgets/label_preview.dart` → `LabelPreview` widget
  - `lib/printing/label_renderer.dart` → `renderPreview()` method

#### For Printing (Bitmap Generation)
- **Package**: `qr: ^3.0.1` (low-level QR generation)
- **File**: `lib/printing/label_renderer.dart`
- **Class**: `LabelRenderer`
- **Method**: `render()` → returns `LabelRenderResult` with monochrome bytes

### QR Generation Code Path (Printing)
```dart
// In label_renderer.dart
final qrCode = QrCode.fromData(
  data: value,
  errorCorrectLevel: QrErrorCorrectLevel.M,
);
final qrImage = QrImage(qrCode);
// Then drawn pixel-by-pixel onto img.Image
```

### Input Format Expected
- **Type**: Any non-empty string
- **Validation**: Optional digit count validation (min/max) via `AppSettings`
- **No special format required** - any text that can be encoded in a QR code

### Reusable QR-Related Code
| Component | File | Reusability |
|-----------|------|-------------|
| `LabelRenderer` | `printing/label_renderer.dart` | ✅ Highly reusable |
| `LabelLayout` | `printing/label_renderer.dart` | ✅ Reusable for layout calculation |
| `LabelPreview` widget | `presentation/widgets/label_preview.dart` | ✅ Reusable for UI preview |
| `QrImageView` usage | Multiple files | ✅ Standard qr_flutter usage |

---

## 4. PRINTING FLOW

### Printer Selection
- **UI**: `PrinterDropdown` widget (`lib/presentation/widgets/printer_dropdown.dart`)
- **State**: `selectedPrinterIdProvider` (StateProvider<String?>)
- **Data**: Loaded from `PrinterRepository` via `printersProvider`

### Printer Storage
- **Storage**: Hive box named `"printers"`
- **Model**: `PrinterConfig` class
- **Repository**: `PrinterRepository` (`lib/data/repositories/printer_repository.dart`)

### Print Job Execution Chain
```
1. User taps Print button (home_screen.dart)
   ↓
2. PrintStateNotifier.print() called (print_provider.dart)
   ↓
3. PrintService.print() executes (print_service.dart)
   ↓
4. ValidationService validates parameters
   ↓
5. PrinterClient instantiated with PrinterConfig
   ↓
6. PrinterClient.print() called (printer_client.dart)
   ↓
7. LabelRenderer.render() generates monochrome bitmap
   ↓
8. TsplBuilder.createLabelPrint() builds TSPL commands
   ↓
9. PrinterClient._sendData() sends via TCP socket
```

### Protocol Used
- **Protocol**: TSPL (TSC Printer Language)
- **Transport**: Raw TCP socket connection
- **Port**: Default 9100 (configurable per printer)
- **Connection**: Direct socket, no driver needed

### Key Printing Files

| File | Purpose |
|------|---------|
| `printing/printer_client.dart` | TCP socket connection, sends data to printer |
| `printing/tspl_builder.dart` | Builds TSPL command sequences |
| `printing/label_renderer.dart` | Renders QR + text to monochrome bitmap |
| `domain/services/print_service.dart` | Orchestrates print workflow |

### Data Structure Sent to Printer
```
TSPL Command Sequence:
SIZE <width> mm,<height> mm
GAP <gap> mm,0 mm
DIRECTION 0
OFFSET 0 mm
SHIFT 0
REFERENCE 0,0
SET PEEL OFF
SET TEAR OFF
SET CUTTER OFF
CLS
BITMAP 0,0,<widthBytes>,<height>,0,<raw monochrome bytes>
PRINT 1,<copies>
```

### Print Logic Reusability
- **`PrinterClient`**: ✅ Fully reusable - no UI dependencies
- **`TsplBuilder`**: ✅ Fully reusable - pure TSPL command building
- **`LabelRenderer`**: ✅ Fully reusable - generates bitmap from value
- **`PrintService`**: ⚠️ Mostly reusable - depends on repositories

---

## 5. PRESETS FLOW

### What Presets Mean
Presets define label paper dimensions:
- Width in millimeters
- Height in millimeters
- Margin (padding) in millimeters

### Preset Storage
- **Storage**: Hive box named `"presets"` (custom presets only)
- **Default Presets**: Hardcoded in `DefaultPresets.all` (not stored)
- **Repository**: `PresetRepository`

### Preset Model Structure
```dart
// lib/models/label_preset.dart
class LabelPreset {
  final String id;          // UUID or "default_40x30" for built-ins
  final String name;        // Display name
  final double widthMm;     // Label width
  final double heightMm;    // Label height
  final double marginMm;    // Inner margin (default: 2.0)
  
  // Computed properties
  double get printableWidthMm;  // widthMm - (marginMm * 2)
  double get printableHeightMm; // heightMm - (marginMm * 2)
}
```

### Default Presets (Hardcoded)
```dart
// lib/models/label_preset.dart → DefaultPresets.all
- 40×30mm (margin: 2mm)
- 50×25mm (margin: 2mm)
- 50×30mm (margin: 2mm)
- 60×40mm (margin: 3mm)
- 100×50mm (margin: 4mm)
```

### How Presets Affect Printing
1. `LabelLayout.fromPreset(preset)` calculates dot dimensions
2. Layout determines QR code size and positioning
3. `LabelRenderer` uses layout to create correctly sized bitmap
4. `TsplBuilder` uses preset dimensions for SIZE command

### Reusability for Palletizing App
- **`LabelPreset` model**: ✅ Fully reusable
- **`DefaultPresets`**: ✅ Can be reused or replaced
- **`PresetRepository`**: ✅ Reusable with Hive dependency
- **`LabelLayout`**: ✅ Reusable layout calculation logic

---

## 6. PRINTER MANAGEMENT

### Adding Printers
- **Screen**: `PrinterFormScreen` (`lib/presentation/screens/printer_form_screen.dart`)
- **Flow**: Form → Validate → `PrinterRepository.save()` → Hive storage

### Printer Model Structure
```dart
// lib/models/printer_config.dart
class PrinterConfig {
  final String id;        // UUID
  final String name;      // Display name
  final String ip;        // IP address (e.g., "192.168.1.100")
  final int port;         // TCP port (default: 9100)
  final bool isDefault;   // Default printer flag
  final int timeoutMs;    // Connection timeout (default: 3000)
}
```

### Printer Persistence
- **Storage**: Hive box `"printers"`
- **Operations**: CRUD via `PrinterRepository`
- **ID Generation**: UUID v4 on first save

### Default Printer Concept
- **Supported**: Yes, via `isDefault` field
- **Behavior**: Only one printer can be default
- **Auto-selection**: Default printer selected on app start

### Multiple Printers
- **Supported**: Yes, unlimited printers
- **Selection**: Via dropdown in home screen

### Connection Testing
- **Method**: `PrinterClient.testConnection()`
- **Implementation**: Opens TCP socket, closes immediately
- **Provider**: `printerConnectionTestProvider` (FutureProvider.family)

---

## 7. LOCAL STORAGE / PERSISTENCE

### Storage Technology
- **Package**: `hive: ^2.2.3` + `hive_flutter: ^1.1.0`
- **Code Generation**: `hive_generator` for type adapters

### Initialization
```dart
// lib/data/datasources/local_storage.dart
await Hive.initFlutter();
// Register adapters for models
Hive.registerAdapter(PrinterConfigAdapter());  // typeId: 0
Hive.registerAdapter(LabelPresetAdapter());    // typeId: 1
Hive.registerAdapter(AppSettingsAdapter());    // typeId: 2
// Open boxes
_printersBox = await Hive.openBox<PrinterConfig>('printers');
_presetsBox = await Hive.openBox<LabelPreset>('presets');
_settingsBox = await Hive.openBox<AppSettings>('settings');
```

### Data Persisted
| Box Name | Model | Contents |
|----------|-------|----------|
| `printers` | `PrinterConfig` | User-configured printers |
| `presets` | `LabelPreset` | Custom label presets only |
| `settings` | `AppSettings` | Last printer, preset, copies, digit validation |

### Files Managing Persistence
- `lib/data/datasources/local_storage.dart` → Hive init & box access
- `lib/data/repositories/printer_repository.dart` → Printer CRUD
- `lib/data/repositories/preset_repository.dart` → Preset CRUD
- `lib/data/repositories/settings_repository.dart` → Settings access

### Generated Files (Hive Adapters)
- `lib/models/printer_config.g.dart`
- `lib/models/label_preset.g.dart`
- `lib/models/app_settings.g.dart`

---

## 8. REUSABLE COMPONENTS / LOGIC

### Highly Reusable (No Changes Needed)

| Component | Location | Dependencies | Why Reusable |
|-----------|----------|--------------|--------------|
| `PrinterConfig` model | `models/printer_config.dart` | Hive, Equatable | Pure data model |
| `LabelPreset` model | `models/label_preset.dart` | Hive, Equatable | Pure data model |
| `PrintJob` model | `models/print_job.dart` | Equatable | Pure DTO |
| `PrinterClient` | `printing/printer_client.dart` | dart:io, image | No UI deps |
| `TsplBuilder` | `printing/tspl_builder.dart` | None | Pure TSPL logic |
| `LabelRenderer` | `printing/label_renderer.dart` | qr, image, qr_flutter | No UI state deps |
| `UnitConverter` | `core/utils/unit_converter.dart` | None | Pure math |
| `AppConstants` | `core/constants/app_constants.dart` | None | Pure constants |
| `TsplConstants` | `core/constants/tspl_constants.dart` | None | Pure constants |
| `AppException` classes | `core/errors/app_exceptions.dart` | None | Pure exceptions |

### Reusable with Minor Adaptation

| Component | Location | Adaptation Needed |
|-----------|----------|-------------------|
| `PrinterRepository` | `data/repositories/printer_repository.dart` | Already clean, just bring Hive |
| `PresetRepository` | `data/repositories/preset_repository.dart` | Already clean |
| `SettingsRepository` | `data/repositories/settings_repository.dart` | May need different settings |
| `LocalStorage` | `data/datasources/local_storage.dart` | Already clean |
| `PrintService` | `domain/services/print_service.dart` | May need to remove validation |
| `ValidationService` | `domain/services/validation_service.dart` | Keep if validation needed |
| `LabelPreview` widget | `widgets/label_preview.dart` | Reusable for preview UI |

### Reusable Riverpod Providers

| Provider | Location | Notes |
|----------|----------|-------|
| `printerRepositoryProvider` | `printer_provider.dart` | Basic DI |
| `printersProvider` | `printer_provider.dart` | Printer list state |
| `presetRepositoryProvider` | `preset_provider.dart` | Basic DI |
| `presetsProvider` | `preset_provider.dart` | Preset list state |
| `printServiceProvider` | `print_provider.dart` | Print service DI |
| `printStateProvider` | `print_provider.dart` | Print job state |

---

## 9. TIGHT COUPLING / INTEGRATION RISKS

### UI-Bound Logic (Requires Extraction)

| Issue | Location | Risk Level | Solution |
|-------|----------|------------|----------|
| Manual text input | `home_screen.dart` | Medium | Replace with backend value |
| Arabic UI text | Multiple screens | Low | Replace or keep as needed |
| Navigation flow | Screen files | Medium | Will use different navigation |
| Form validation | Form screens | Low | May not need printer/preset forms |

### Hidden Dependencies

| Dependency | Where | Impact |
|------------|-------|--------|
| `LocalStorage.initialize()` | `main.dart` | Must call before using repos |
| Hive adapter registration | `local_storage.dart` | Must register before opening boxes |
| Provider hierarchy | `app.dart` | Need ProviderScope wrapper |

### Hardcoded Values

| Value | Location | Notes |
|-------|----------|-------|
| Printer DPI: 203 | `app_constants.dart` | XPrinter XP-410B specific |
| Default port: 9100 | `app_constants.dart` | Standard thermal printer port |
| Default gap: 2.0mm | `app_constants.dart` | Gap between labels |
| Default timeout: 3000ms | `app_constants.dart` | Connection timeout |

### State Management Coupling

The app uses Riverpod throughout. If palletizing app uses different state management:
- Providers will need to be converted or wrapped
- Consider extracting pure Dart services separate from Riverpod

### Potential Issues

1. **Hive Type IDs**: If palletizing app already uses Hive with typeId 0, 1, 2, there will be conflicts
2. **Package versions**: Ensure compatible versions of shared packages
3. **Debug mode**: `PrinterClient` has `debugMode = true` by default (saves debug images)

---

## 10. SUGGESTED EXTRACTION PLAN

### Phase 1: Extract Core Printing Module

```
Create a standalone printing module with:
├── models/
│   ├── printer_config.dart
│   ├── label_preset.dart
│   └── print_job.dart
├── printing/
│   ├── printer_client.dart
│   ├── label_renderer.dart
│   └── tspl_builder.dart
├── utils/
│   ├── unit_converter.dart
│   └── app_constants.dart
└── errors/
    └── app_exceptions.dart
```

**No changes needed** - these files have no UI dependencies.

### Phase 2: Extract Storage Layer

```
├── datasources/
│   └── local_storage.dart
└── repositories/
    ├── printer_repository.dart
    └── preset_repository.dart
```

**Consideration**: Change Hive typeIds if conflicts exist in palletizing app.

### Phase 3: Create Print Service Facade

Create a simplified facade for palletizing app:

```dart
class QrPrintingService {
  Future<void> initialize();
  
  List<PrinterConfig> getPrinters();
  List<LabelPreset> getPresets();
  
  Future<void> print({
    required String value,      // From backend scannedValue
    required String printerId,
    required String presetId,
    int copies = 1,
  });
  
  Future<bool> testPrinterConnection(String printerId);
}
```

### Phase 4: Integrate into Palletizing App

1. Copy extracted module to palletizing app
2. Initialize `LocalStorage` in app startup
3. Register Hive adapters (with new typeIds if needed)
4. Create Riverpod providers or adapt to existing state management
5. Wire pallet creation success to QR print flow

### Phase 5: Replace Manual Input

**Current flow (this app)**:
```
User types value → Preview → Print
```

**Target flow (palletizing app)**:
```
Backend returns scannedValue → Auto-generate QR → Show preview → Print
```

---

## 11. INTEGRATION CONTRACT FOR PALLETIZING APP

### Required Inputs

| Input | Type | Source |
|-------|------|--------|
| `scannedValue` | `String` | Backend pallet creation response |
| `printerId` | `String` | User selection or saved default |
| `presetId` | `String` | User selection or saved default |
| `copies` | `int` | User input or default (1) |

### Exposed Methods/Services

```dart
/// Initialize storage (call once at app startup)
Future<void> initializePrintingModule() async {
  await LocalStorage.initialize();
}

/// Get available printers
List<PrinterConfig> getAvailablePrinters() {
  return PrinterRepository().getAll();
}

/// Get available presets
List<LabelPreset> getAvailablePresets() {
  return PresetRepository().getAll();
}

/// Execute print job
Future<PrintResult> printQrLabel({
  required String value,
  required String printerId,
  required String presetId,
  int copies = 1,
}) async {
  final printService = PrintService(...);
  return printService.print(
    value: value,
    printerId: printerId,
    presetId: presetId,
    copies: copies,
  );
}

/// Test printer connection
Future<bool> testPrinter(String printerId) async {
  final printer = PrinterRepository().getById(printerId);
  if (printer == null) return false;
  return PrinterClient(printer).testConnection();
}

/// Generate preview widget
Widget buildQrPreview({
  required String value,
  required LabelPreset preset,
  double maxWidth = 300,
  double maxHeight = 300,
}) {
  return LabelPreview(
    value: value,
    preset: preset,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
}
```

### Expected Output/Result

```dart
class PrintResult {
  final PrintStatus status;  // success, error
  final String? errorMessage;
}
```

### Printer Selection Workflow

1. On first use: Show printer selection dialog/dropdown
2. Save selection to settings: `SettingsRepository.setLastPrinter(id)`
3. On subsequent uses: Auto-select saved printer
4. Allow user to change via settings

### Preset Selection Workflow

1. Show preset selection or use reasonable default (e.g., 50×30mm)
2. Save selection to settings
3. Auto-select saved preset on subsequent uses

### Retry Print Workflow

1. On print failure, show error with "Retry" button
2. Retry calls same `printQrLabel()` with same parameters
3. No special retry logic needed - just call again

### Target Integration Flow

```dart
// After successful pallet creation
void onPalletCreated(String scannedValue) async {
  // 1. Get saved printer and preset
  final settings = SettingsRepository().get();
  final printerId = settings.lastPrinterId ?? await showPrinterSelector();
  final presetId = settings.lastPresetId ?? 'default_50x30';
  
  // 2. Show preview (optional)
  showQrPreview(scannedValue, presetId);
  
  // 3. Print
  final result = await printQrLabel(
    value: scannedValue,
    printerId: printerId,
    presetId: presetId,
    copies: 1,
  );
  
  // 4. Handle result
  if (result.status == PrintStatus.success) {
    showSuccess('تم الطباعة بنجاح');
  } else {
    showErrorWithRetry(result.errorMessage, () => onPalletCreated(scannedValue));
  }
}
```

---

## 12. PACKAGE / DEPENDENCY INVENTORY

### QR Code Generation
| Package | Version | Purpose |
|---------|---------|---------|
| `qr_flutter` | ^4.1.0 | QR code widget for preview |
| `qr` | ^3.0.1 | Low-level QR generation for bitmap |

### Printing / Image
| Package | Version | Purpose |
|---------|---------|---------|
| `image` | ^4.1.7 | Bitmap creation and manipulation |
| (dart:io) | built-in | TCP socket communication |

### Storage
| Package | Version | Purpose |
|---------|---------|---------|
| `hive` | ^2.2.3 | Local NoSQL database |
| `hive_flutter` | ^1.1.0 | Flutter integration for Hive |
| `hive_generator` | ^2.0.1 | Code generation for Hive adapters |

### State Management
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | ^2.5.1 | State management |

### Utilities
| Package | Version | Purpose |
|---------|---------|---------|
| `uuid` | ^4.3.3 | Generate unique IDs |
| `equatable` | ^2.0.5 | Value equality for models |
| `path_provider` | ^2.1.2 | Get app directory for debug exports |

---

## 13. FILE-BY-FILE IMPORTANT MAP

### Critical Files for Integration

```
lib/
├── main.dart
│   → App entry point
│   → MUST call LocalStorage.initialize() before anything else
│
├── data/datasources/local_storage.dart
│   → Hive initialization and box access
│   → MUST be initialized first
│   → Contains typeId registration (0, 1, 2)
│
├── models/
│   ├── printer_config.dart → Printer model (Hive typeId: 0)
│   ├── label_preset.dart   → Preset model (Hive typeId: 1)
│   ├── app_settings.dart   → Settings model (Hive typeId: 2)
│   └── print_job.dart      → Print job DTO (not persisted)
│
├── printing/
│   ├── printer_client.dart → TCP socket printing
│   │   → PrinterClient.print(job, preset) → sends to printer
│   │   → PrinterClient.testConnection() → tests connectivity
│   │
│   ├── label_renderer.dart → QR + text → monochrome bitmap
│   │   → LabelRenderer.render(value, preset) → returns bitmap bytes
│   │   → LabelLayout.fromPreset() → calculates dimensions
│   │
│   └── tspl_builder.dart → Builds TSPL command sequences
│       → TsplBuilder.createLabelPrint() → full print command
│
├── domain/services/print_service.dart
│   → PrintService.print() → orchestrates full print workflow
│   → Validates, renders, sends, saves settings
│
├── data/repositories/
│   ├── printer_repository.dart → Printer CRUD
│   ├── preset_repository.dart  → Preset CRUD + defaults
│   └── settings_repository.dart → Settings persistence
│
├── core/
│   ├── constants/app_constants.dart → DPI, defaults, limits
│   ├── constants/tspl_constants.dart → TSPL command strings
│   ├── utils/unit_converter.dart → mm↔dots↔bytes math
│   └── errors/app_exceptions.dart → Custom exceptions
│
└── presentation/widgets/label_preview.dart
    → LabelPreview widget for QR preview UI
```

### Files NOT Needed for Integration

```
- presentation/screens/*.dart → UI specific to this app
- presentation/providers/*.dart → Can recreate for different state mgmt
- presentation/widgets/printer_dropdown.dart → UI specific
- presentation/widgets/preset_dropdown.dart → UI specific
- presentation/widgets/copies_input.dart → UI specific
- core/utils/validators.dart → Optional validation
- domain/services/validation_service.dart → Optional validation
```

---

## 14. WHAT MUST BE PRESERVED DURING INTEGRATION

### Critical Behaviors

1. **TSPL Command Sequence**: The exact order in `TsplBuilder.createLabelPrint()` must be preserved - includes state reset commands that prevent print drift

2. **Monochrome Conversion**: `LabelRenderer._convertToMonochrome()` uses specific bit encoding (0=black, 1=white for TSPL BITMAP command)

3. **DPI Calculations**: `UnitConverter` uses 203 DPI - must match actual printer

4. **QR Error Correction**: Using `QrErrorCorrectLevel.M` (medium) for reliability

5. **Bitmap Width Alignment**: Width must be byte-aligned (multiples of 8 dots)

6. **Socket Connection Pattern**: Connect → send → flush → close (no persistent connection)

7. **Default Printer Logic**: `PrinterRepository.getDefault()` returns first if none marked default

8. **Default Presets Merging**: `PresetRepository.getAll()` returns defaults + custom

### Configuration Values to Preserve

| Value | Location | Reason |
|-------|----------|--------|
| DPI = 203 | `AppConstants` | Printer-specific |
| Port = 9100 | `AppConstants` | Printer standard |
| Timeout = 3000ms | `AppConstants` | Reasonable default |
| Gap = 2.0mm | `AppConstants` | Label paper gap |
| Direction = 0 | `TsplConstants` | Print orientation |

---

## 15. WHAT SHOULD PROBABLY CHANGE DURING INTEGRATION

### Remove / Replace

| Current | Change To |
|---------|-----------|
| Manual text input field | Backend-provided `scannedValue` |
| Home screen as entry point | Triggered after pallet creation |
| Printer/preset management screens | May keep or simplify |
| Settings screen | Integrate into palletizing app settings |
| Arabic localization | Keep or change based on requirements |

### Simplify

| Current | Suggestion |
|---------|------------|
| Full form validation | Only validate scannedValue non-empty |
| Digit count validation | Remove unless needed |
| Copy count input | Default to 1 or make configurable |

### Integrate

| Feature | Integration Approach |
|---------|---------------------|
| Printer selection | Add to palletizing app settings |
| Preset selection | Add to palletizing app settings or hardcode |
| Print trigger | Call after successful pallet creation API |
| Error handling | Use palletizing app's error UI patterns |

### New Features to Consider

1. **Auto-print toggle**: Print immediately after pallet creation
2. **Batch printing**: Print multiple pallets in sequence
3. **Print history**: Track what was printed when
4. **Offline queue**: Queue prints if printer unavailable

---

## APPENDIX: Quick Start Integration Checklist

```
□ Copy these files to palletizing app:
  □ models/printer_config.dart (change typeId if conflict)
  □ models/label_preset.dart (change typeId if conflict)
  □ models/print_job.dart
  □ printing/printer_client.dart
  □ printing/label_renderer.dart
  □ printing/tspl_builder.dart
  □ core/constants/app_constants.dart
  □ core/constants/tspl_constants.dart
  □ core/utils/unit_converter.dart
  □ core/errors/app_exceptions.dart
  □ data/datasources/local_storage.dart
  □ data/repositories/printer_repository.dart
  □ data/repositories/preset_repository.dart

□ Add dependencies to pubspec.yaml:
  □ hive: ^2.2.3
  □ hive_flutter: ^1.1.0
  □ qr_flutter: ^4.1.0
  □ qr: ^3.0.1
  □ image: ^4.1.7
  □ uuid: ^4.3.3
  □ equatable: ^2.0.5

□ Add dev dependencies:
  □ hive_generator: ^2.0.1
  □ build_runner: ^2.4.8

□ Run: flutter pub run build_runner build

□ Initialize in main.dart:
  □ await LocalStorage.initialize();

□ Create print service wrapper

□ Wire to pallet creation flow

□ Test with actual printer
```

---

*Document generated for integration handoff. Based on actual codebase analysis.*
