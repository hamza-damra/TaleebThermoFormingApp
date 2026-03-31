# Palletizing Screen Implementation

## Overview

This document describes the implementation of the palletizing screen (تكوين المشاتيح) for the Taleeb ThermoForming application, following the architecture defined in `AGENTS_ARCHITECTURE_REFERENCE.md`.

---

## What Was Implemented

### 1. Screen Layout
- **Two-column tablet layout** with vertical sections
- **Right section**: خط الإنتاج 1 (Blue - `#1565C0`)
- **Left section**: خط الإنتاج 2 (Green - `#388E3C`)
- RTL (Arabic-first) layout with proper localization

### 2. Components Per Section
Each production line section includes:
- **Header** with line name and color
- **Operator Dropdown** - horizontal layout `[اسم المشغل] [Dropdown]`
- **Product Dropdown** - horizontal layout `[نوع المنتج] [Dropdown]`
- **Summary Card** displaying:
  - عدد المشاتيح المنتجة في هذا الشفت (large count display)
  - اسم المشغل الحالي
  - نوع المنتج الحالي
- **Create Button** - `إنشاء مشتاح جديد الآن` (full width, line-colored)

### 3. Dialog Behavior
On button click, opens a dialog with:
- Editable operator dropdown
- Editable product dropdown
- Quantity stepper `[-] 20 [+]`
- Cancel/Confirm buttons

On confirm:
- Simulates pallet creation
- Increments pallet count
- Updates current operator/product
- Shows mock QR code result

---

## Architecture Adherence

### Folder Structure (Layer-Based)
```
lib/
├── core/
│   ├── constants.dart      # ProductionLine enum with colors/labels
│   ├── di.dart             # ServiceLocator for dependency injection
│   └── theme.dart          # AppTheme with Cairo font
├── data/
│   ├── models/
│   │   ├── operator_model.dart
│   │   └── product_model.dart
│   ├── repositories/
│   │   └── palletizing_repository_impl.dart  # Mock implementation
│   └── seeded/
│       └── seeded_data.dart  # Mock operators and products
├── domain/
│   ├── entities/
│   │   ├── operator.dart
│   │   └── product.dart
│   └── repositories/
│       └── palletizing_repository.dart  # Abstract interface
└── presentation/
    ├── providers/
    │   └── palletizing_provider.dart  # ChangeNotifier state
    ├── screens/
    │   └── palletizing_screen.dart
    └── widgets/
        ├── production_line_section.dart
        ├── summary_card.dart
        └── create_pallet_dialog.dart
```

### Pattern Compliance

| Pattern | Implementation |
|---------|----------------|
| **State Management** | Provider + ChangeNotifier (PalletizingProvider) |
| **Entity** | Pure Dart classes in `domain/entities/` |
| **Model** | Extends Entity, adds `fromJson` in `data/models/` |
| **Repository Interface** | Abstract class in `domain/repositories/` |
| **Repository Implementation** | Implements interface in `data/repositories/` |
| **DI** | ServiceLocator pattern in `core/di.dart` |
| **No UseCases** | Provider calls repository directly |
| **Business Logic** | All in Provider, none in widgets |

---

## Seeded Data Location

**File**: `lib/data/seeded/seeded_data.dart`

```dart
class SeededData {
  static const List<OperatorModel> operators = [
    OperatorModel(id: 1, name: 'أحمد'),
    OperatorModel(id: 2, name: 'محمد'),
    OperatorModel(id: 3, name: 'ياسر'),
    OperatorModel(id: 4, name: 'خالد'),
    OperatorModel(id: 5, name: 'إبراهيم'),
  ];

  static const List<ProductModel> products = [
    ProductModel(id: 1, name: 'صحون 20 سم'),
    ProductModel(id: 2, name: 'صحون 22 سم'),
    ProductModel(id: 3, name: 'صحون 25 سم'),
    ProductModel(id: 4, name: 'علب فلين صغيرة'),
    ProductModel(id: 5, name: 'علب فلين متوسطة'),
    ProductModel(id: 6, name: 'علب فلين كبيرة'),
  ];
}
```

**Important**: Seeded data is NOT hardcoded in widgets. It lives in the data layer and is accessed through the repository.

---

## Future API Integration

When ready to integrate real API:

### Step 1: Add ApiClient
Create `lib/data/datasources/api_client.dart` with Dio configuration.

### Step 2: Update Repository Implementation
Modify `PalletizingRepositoryImpl` to use `ApiClient`:

```dart
class PalletizingRepositoryImpl implements PalletizingRepository {
  final ApiClient _apiClient;
  PalletizingRepositoryImpl(this._apiClient);

  @override
  Future<List<Operator>> getOperators() async {
    final response = await _apiClient.dio.get('/operators');
    final data = response.data['data'] as List<dynamic>;
    return data.map((e) => OperatorModel.fromJson(e)).toList();
  }

  @override
  Future<String> createPallet({...}) async {
    final response = await _apiClient.dio.post('/pallets', data: {...});
    return response.data['data']['qr_code'] as String;
  }
}
```

### Step 3: Update ServiceLocator
Initialize `ApiClient` and pass to repository:

```dart
Future<void> init() async {
  _apiClient = ApiClient();
  _palletizingRepository = PalletizingRepositoryImpl(_apiClient);
}
```

### Step 4: Add Error Handling
Implement `ApiException` and `extractApiException` for Arabic error messages.

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  provider: ^6.1.4
  google_fonts: ^6.2.1
```

---

## Running the App

```bash
flutter pub get
flutter run
```

For tablet testing, use Chrome or an Android tablet emulator.

---

## Version
- **Implementation Date**: 2026-03-29
- **Architecture Reference**: AGENTS_ARCHITECTURE_REFERENCE.md v1.0
