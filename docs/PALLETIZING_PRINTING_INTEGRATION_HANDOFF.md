# Palletizing Printing Integration Handoff

> **Document Purpose:** Documents the integration of QR printing functionality into the Palletizing app (تطبيق تكوين المشاتيح), preserving the existing app architecture.

---

## 1. Integration Summary

The QR printing capability has been integrated into the existing Palletizing app by extracting reusable printing logic from the QR Printing app while **preserving the Palletizing app's original architecture**:

- **State Management:** `provider` package with `ChangeNotifier` (unchanged)
- **DI Pattern:** Custom `ServiceLocator` singleton (extended)
- **Architecture:** Clean architecture with `data/`, `domain/`, `presentation/`, `core/` (preserved)

---

## 2. What Was Reused from QR Printing App

### Fully Reused (Logic Only)
| Component | Original Location | New Location | Changes |
|-----------|------------------|--------------|---------|
| `PrinterClient` | `printing/printer_client.dart` | `lib/printing/printer_client.dart` | Minor import path updates |
| `TsplBuilder` | `printing/tspl_builder.dart` | `lib/printing/tspl_builder.dart` | None |
| `LabelRenderer` | `printing/label_renderer.dart` | `lib/printing/label_renderer.dart` | Removed unused imports |
| `UnitConverter` | `core/utils/unit_converter.dart` | `lib/printing/unit_converter.dart` | None |
| TSPL Constants | `core/constants/tspl_constants.dart` | `lib/core/constants/tspl_constants.dart` | None |
| Default Presets | `models/label_preset.dart` | `lib/domain/entities/label_preset.dart` | Integrated into entity |

### Adapted from QR Printing App
| Component | Adaptation |
|-----------|------------|
| `PrinterConfig` model | Converted to domain entity + Hive model with typeId 10 |
| `LabelPreset` model | Converted to domain entity + Hive model with typeId 11 |
| `PrintingSettings` | New Hive model with typeId 12 for persisting selections |
| Storage logic | Adapted to `PrintingLocalStorage` class |
| Repositories | Implemented as `PrinterRepositoryImpl`, `PresetRepositoryImpl` |

### NOT Reused (Intentionally)
| Component | Reason |
|-----------|--------|
| Riverpod providers | Palletizing app uses `provider` package |
| HomeScreen | Manual text input not needed |
| PrinterFormScreen | Replaced with simplified `AddPrinterDialog` |
| PresetFormScreen | Using default presets only |
| Settings screen | Integrated into success dialog flow |
| Digit validation | Not applicable (backend provides scannedValue) |

---

## 3. How State Management Was Preserved

### Original Pattern (Preserved)
```dart
// main.dart - MultiProvider with ChangeNotifier
MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>(...),
    ChangeNotifierProvider<PalletizingProvider>(...),
    ChangeNotifierProvider<PrintingProvider>(...),  // NEW
  ],
)
```

### New PrintingProvider
Created `PrintingProvider` extending `ChangeNotifier` matching the existing pattern:

```dart
class PrintingProvider extends ChangeNotifier {
  // State
  PrintingState _state = PrintingState.idle;
  List<PrinterConfig> _printers = [];
  List<LabelPreset> _presets = [];
  PrinterConfig? _selectedPrinter;
  LabelPreset? _selectedPreset;
  
  // Methods following existing pattern
  Future<void> loadData();
  Future<PrintResult> print({required String scannedValue, int copies = 1});
  Future<bool> testConnection(PrinterConfig printer);
  // ... CRUD operations for printers
}
```

---

## 4. Create-Pallet → Print Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. User selects operator, product type, quantity               │
│  2. User taps "إنشاء مشتاح جديد" (Create New Pallet)            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. PalletizingProvider.createPallet() → Backend API call       │
│  4. Backend returns scannedValue (e.g., "073200000001")         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. PalletSuccessDialog displays:                               │
│     - QR code preview (using qr_flutter)                        │
│     - Pallet details                                            │
│     - Print button                                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ User taps "طباعة" (Print)
┌─────────────────────────────────────────────────────────────────┐
│  6. If no printer → PrinterSelectorDialog                       │
│  7. PrintingProvider.print(scannedValue)                        │
│     a. LabelRenderer generates monochrome bitmap                │
│     b. TsplBuilder creates TSPL commands                        │
│     c. PrinterClient sends via TCP socket                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  8. On success: Show confirmation, log to backend               │
│  9. On failure: Show error with retry option                    │
│     - scannedValue preserved for retry                          │
│     - Dialog stays open                                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Printer/Preset Storage

### Hive Boxes
| Box Name | Model | TypeId | Contents |
|----------|-------|--------|----------|
| `printers` | `PrinterConfigModel` | 10 | User-configured printers |
| `custom_presets` | `LabelPresetModel` | 11 | Custom label presets (if any) |
| `printing_settings` | `PrintingSettingsModel` | 12 | Last printer, preset selection |

### Default Presets (Hardcoded)
```
- 40×30mm (margin: 2mm)
- 50×25mm (margin: 2mm)
- 50×30mm (margin: 2mm) ← DEFAULT
- 60×40mm (margin: 3mm)
- 100×50mm (margin: 4mm)
```

### Initialization
```dart
// In ServiceLocator.init()
await PrintingLocalStorage.initialize();  // Hive init + adapter registration
_printerRepository = PrinterRepositoryImpl();
_presetRepository = PresetRepositoryImpl();
```

---

## 6. New Files Created

### Core Layer
```
lib/core/constants/
├── printing_constants.dart    # DPI, timeouts, defaults
└── tspl_constants.dart        # TSPL command strings

lib/core/exceptions/
└── printing_exception.dart    # Printing-specific errors
```

### Data Layer
```
lib/data/datasources/
└── printing_local_storage.dart    # Hive initialization

lib/data/models/
├── printer_config_model.dart      # Hive model (typeId: 10)
├── printer_config_model.g.dart    # Generated
├── label_preset_model.dart        # Hive model (typeId: 11)
├── label_preset_model.g.dart      # Generated
├── printing_settings_model.dart   # Hive model (typeId: 12)
└── printing_settings_model.g.dart # Generated

lib/data/repositories/
├── printer_repository_impl.dart
└── preset_repository_impl.dart
```

### Domain Layer
```
lib/domain/entities/
├── printer_config.dart
├── label_preset.dart
└── print_job.dart

lib/domain/repositories/
├── printer_repository.dart
└── preset_repository.dart
```

### Printing Core
```
lib/printing/
├── printer_client.dart      # TCP socket communication
├── tspl_builder.dart        # TSPL command builder
├── label_renderer.dart      # QR → monochrome bitmap
└── unit_converter.dart      # mm↔dots conversion
```

### Presentation Layer
```
lib/presentation/providers/
└── printing_provider.dart       # ChangeNotifier-based state

lib/presentation/widgets/
└── printer_selector_dialog.dart # Printer selection + add printer
```

---

## 7. Modified Files

| File | Changes |
|------|---------|
| `pubspec.yaml` | Added: `qr`, `image`, `hive`, `hive_flutter`, `uuid`, `equatable`, `path_provider`, `hive_generator`, `build_runner` |
| `lib/core/di.dart` | Added printing repositories and `createPrintingProvider()` |
| `lib/main.dart` | Added `PrintingProvider` to `MultiProvider` |
| `lib/presentation/widgets/pallet_success_dialog.dart` | Converted to StatefulWidget with integrated print flow |
| `lib/presentation/widgets/production_line_section.dart` | Simplified dialog call (removed callbacks) |

---

## 8. Technical Behaviors Preserved

| Behavior | Implementation |
|----------|----------------|
| TSPL command sequence | `TsplBuilder.createLabelPrint()` - exact order preserved |
| Monochrome conversion | `LabelRenderer._convertToMonochrome()` - 0=black, 1=white |
| DPI = 203 | `PrintingConstants.printerDpi` for XPrinter XP-410B |
| Bitmap width alignment | Multiples of 8 dots via `UnitConverter.alignToBytes()` |
| Socket pattern | Connect → send → flush → destroy |
| QR error correction | `QrErrorCorrectLevel.M` (medium) |
| Default port | 9100 (standard thermal printer port) |
| Connection timeout | 3000ms |

---

## 9. Error Handling

### Print Errors (Arabic messages)
| Error | Message |
|-------|---------|
| No printer selected | لم يتم اختيار طابعة |
| No preset selected | لم يتم اختيار حجم الملصق |
| Connection failed | فشل الاتصال بالطابعة |
| Connection timeout | انتهت مهلة الاتصال بالطابعة |
| Send failed | فشل إرسال البيانات للطابعة |
| Render failed | فشل في إنشاء صورة الباركود |

### Error Flow
1. Print fails → Error displayed in dialog with red container
2. "إعادة المحاولة" (Retry) button appears
3. `scannedValue` preserved for retry
4. Dialog remains open until success or user closes

---

## 10. Remaining TODOs

| Priority | Item |
|----------|------|
| Low | Preset selection UI (currently uses default 50×30mm) |
| Low | Printer management screen for editing/deleting printers |
| Low | Print history tracking |
| Low | Offline print queue |

---

## 11. Testing Checklist

```
□ Run: flutter pub get
□ Run: dart run build_runner build --delete-conflicting-outputs
□ Add a printer via the dialog (IP + port)
□ Test printer connection
□ Create a pallet
□ Print the QR code
□ Verify print output on thermal printer
□ Test retry on connection failure
□ Verify settings persistence (printer selection saved)
```

---

## 12. Dependencies Added

```yaml
dependencies:
  qr: ^3.0.1              # Low-level QR for bitmap generation
  image: ^4.1.7           # Bitmap manipulation
  hive: ^2.2.3            # Local storage
  hive_flutter: ^1.1.0    # Flutter Hive integration
  uuid: ^4.3.3            # ID generation
  equatable: ^2.0.5       # Value equality
  path_provider: ^2.1.2   # App directories

dev_dependencies:
  hive_generator: ^2.0.1  # Hive adapter generation
  build_runner: ^2.4.8    # Code generation
```

---

*Document generated: March 30, 2026*
*Integration preserves original Palletizing app architecture*
