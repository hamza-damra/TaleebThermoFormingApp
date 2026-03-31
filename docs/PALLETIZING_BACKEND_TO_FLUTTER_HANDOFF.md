# Palletizing Backend to Flutter Handoff

> **Document Purpose:** This document is written specifically for the AI agent implementing the Flutter palletizing app. It contains all information needed to integrate with the Taleeb backend palletizing module.

---

## 1. Overview of Backend Changes

The backend now supports the palletizing workflow (تطبيق تكوين المشاتيح) with:

- **New role:** `PALLETIZER` - for users who create pallets via the mobile app
- **New entities:** `Operator`, `ProductionLine`, `PalletSerialCounter`, `PalletePrintLog`
- **Extended entity:** `Pallete` - now includes production metadata (operator, line, quantity, etc.)
- **New endpoints:** Under `/api/v1/palletizing/**` - secured for `PALLETIZER` role only
- **New enum:** `SourceType` - distinguishes pallets created via production line vs warehouse import

---

## 2. CRITICAL: Backend Responsibilities

### ✅ Backend IS Responsible For:
| Responsibility | Implementation |
|----------------|----------------|
| Generating unique `scannedValue` | `PalletSerialGenerationService` with pessimistic locking |
| Storing pallet records | `Pallete` entity with production metadata |
| Validating operators, product types, production lines | Service-layer validation |
| Creating initial warehouse status | `PalleteStatus` with `Destination.PRODUCTION` |
| Returning structured data for Flutter | Clean DTOs without QR payloads |
| Storing print audit logs (optional) | `PalletePrintLog` entity |

### ❌ Backend is NOT Responsible For:
| NOT Backend's Job | Flutter Must Handle |
|-------------------|---------------------|
| Generating QR codes | Use `scannedValue` as QR data input |
| Storing QR images | Generate locally, no backend storage |
| Generating QR binary/base64 | Do this client-side |
| Connecting to printers | Direct printer communication in Flutter |
| Sending print commands | TSPL/ZPL generation in Flutter |
| Managing printer presets | Store locally in Flutter |
| Managing printer configurations | Flutter app settings |

---

## 3. Responsibility Split Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                         BACKEND (Spring Boot)                        │
├─────────────────────────────────────────────────────────────────────┤
│  • Authenticate PALLETIZER users                                     │
│  • Provide operators, product types, production lines                │
│  • Generate unique scannedValue (12 digits)                          │
│  • Create pallet record in database                                  │
│  • Set initial status: PRODUCTION                                    │
│  • Return pallet data (including scannedValue)                       │
│  • Optionally log print attempts for audit                           │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ Returns scannedValue
┌─────────────────────────────────────────────────────────────────────┐
│                      FLUTTER PALLETIZING APP                         │
├─────────────────────────────────────────────────────────────────────┤
│  • Use scannedValue as QR code input data                            │
│  • Generate QR code image locally (e.g., qr_flutter package)         │
│  • Preview QR code on screen                                         │
│  • Convert QR to printer-compatible format (TSPL/bitmap)             │
│  • Manage printer connections (Bluetooth/WiFi)                       │
│  • Send print commands to thermal printer                            │
│  • Store printer presets locally                                     │
│  • Optionally report print success/failure to backend                │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Database Schema (V11 Migration)

### New Tables

#### `production_lines`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | BIGINT | PK, AUTO_INCREMENT | |
| `name` | VARCHAR(255) | NOT NULL | Arabic display name |
| `code` | VARCHAR(50) | NOT NULL, UNIQUE | e.g., `LINE_1` |
| `line_number` | INT | NOT NULL | Numeric identifier |
| `is_active` | BOOLEAN | NOT NULL, DEFAULT TRUE | |
| `created_at` | TIMESTAMP(3) | NOT NULL | |
| `updated_at` | TIMESTAMP(3) | NOT NULL | |

#### `operators`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | BIGINT | PK, AUTO_INCREMENT | |
| `name` | VARCHAR(255) | NOT NULL | Operator's name (Arabic) |
| `code` | VARCHAR(50) | NOT NULL, UNIQUE | Unique identifier code |
| `is_active` | BOOLEAN | NOT NULL, DEFAULT TRUE | |
| `created_at` | TIMESTAMP(3) | NOT NULL | |
| `updated_at` | TIMESTAMP(3) | NOT NULL | |

#### `pallet_serial_counters`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | BIGINT | PK, AUTO_INCREMENT | |
| `product_type_id` | BIGINT | NOT NULL, UNIQUE, FK | One counter per product type |
| `last_serial` | BIGINT | NOT NULL, DEFAULT 0 | Last used serial number |
| `created_at` | TIMESTAMP(3) | NOT NULL | |
| `updated_at` | TIMESTAMP(3) | NOT NULL | |

#### `pallete_print_logs`
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | BIGINT | PK, AUTO_INCREMENT | |
| `pallete_id` | BIGINT | NOT NULL, FK | |
| `requested_by_user_id` | BIGINT | NOT NULL, FK | |
| `printer_identifier` | VARCHAR(100) | NULL | Optional printer name/MAC |
| `attempt_number` | INT | NOT NULL | 1, 2, 3... for retries |
| `status` | VARCHAR(20) | NOT NULL | SUCCESS, FAILED, PENDING |
| `failure_reason` | TEXT | NULL | Error message if failed |
| `printed_at` | TIMESTAMP(3) | NULL | When print completed |
| `created_at` | TIMESTAMP(3) | NOT NULL | |

### Extended `palletes` Table (New Columns)
| Column | Type | Description |
|--------|------|-------------|
| `product_type_id` | BIGINT, FK | Links to product_types |
| `operator_id` | BIGINT, FK | Links to operators |
| `production_line_id` | BIGINT, FK | Links to production_lines |
| `created_by_user_id` | BIGINT, FK | The PALLETIZER user who created it |
| `quantity` | INT | Number of items in pallet |
| `source_type` | VARCHAR(30) | PRODUCTION_LINE, WAREHOUSE_IMPORT, UNKNOWN |
| `operator_name_snapshot` | VARCHAR(255) | Denormalized name at creation time |
| `product_type_name_snapshot` | VARCHAR(500) | Denormalized name at creation time |
| `production_line_name_snapshot` | VARCHAR(255) | Denormalized name at creation time |

---

## 5. Enums and Roles

### Role Enum
```java
public enum Role {
    DRIVER,
    OFFICER,
    MONITORING,
    ADMIN,
    PALLETIZER  // ← New role for palletizing app users
}
```

### SourceType Enum
```java
public enum SourceType {
    PRODUCTION_LINE,   // Created via palletizing app
    WAREHOUSE_IMPORT,  // Scanned directly into warehouse
    UNKNOWN            // Legacy/unspecified
}
```

### PrintStatus Enum
```java
public enum PrintStatus {
    SUCCESS,
    FAILED,
    PENDING
}
```

### Destination Enum (Existing)
```java
public enum Destination {
    WAREHOUSE_1,
    WAREHOUSE_2,
    TRANSIT,
    DIRECT_OUT,
    OUT,
    RECYCLE,
    REPRODUCTION,
    PRODUCTION   // ← Initial status for newly created pallets
}
```

### PackageUnit Enum (for product types)
```java
public enum PackageUnit {
    // Values depend on existing implementation
    // Check actual enum for display names
}
```

---

## 6. API Endpoints

### Base URL
```
/api/v1/palletizing
```

### Authentication
All endpoints require:
- **Header:** `Authorization: Bearer <JWT_TOKEN>`
- **Role:** `PALLETIZER`

### 6.1 Login (Use existing auth endpoint)

**Endpoint:** `POST /api/v1/auth/login`

**Request:**
```json
{
  "email": "palletizer@taleeb.ps",
  "password": "password123"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 5,
      "name": "محمد العامل",
      "email": "palletizer@taleeb.ps",
      "role": "PALLETIZER"
    }
  }
}
```

---

### 6.2 Get Active Operators

**Endpoint:** `GET /api/v1/palletizing/operators`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "ياسر أحمد",
      "code": "OP001"
    },
    {
      "id": 2,
      "name": "محمد علي",
      "code": "OP002"
    }
  ]
}
```

---

### 6.3 Get Active Product Types

**Endpoint:** `GET /api/v1/palletizing/product-types`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "لنش بوكس أسود 750 مل",
      "productName": "لنش بوكس",
      "prefix": "0732",
      "color": "أسود",
      "packageQuantity": 200,
      "packageUnit": "PIECE",
      "packageUnitDisplayName": "قطعة"
    },
    {
      "id": 2,
      "name": "صحن دائري أبيض",
      "productName": "صحن دائري",
      "prefix": "0038",
      "color": "أبيض",
      "packageQuantity": 500,
      "packageUnit": "PIECE",
      "packageUnitDisplayName": "قطعة"
    }
  ]
}
```

---

### 6.4 Get Active Production Lines

**Endpoint:** `GET /api/v1/palletizing/production-lines`

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "خط الإنتاج 1",
      "code": "LINE_1",
      "lineNumber": 1
    },
    {
      "id": 2,
      "name": "خط الإنتاج 2",
      "code": "LINE_2",
      "lineNumber": 2
    }
  ]
}
```

---

### 6.5 Create Pallet (MAIN ENDPOINT)

**Endpoint:** `POST /api/v1/palletizing/pallets`

**Request:**
```json
{
  "operatorId": 1,
  "productTypeId": 2,
  "productionLineId": 1,
  "quantity": 200
}
```

**Validation Rules:**
| Field | Rule |
|-------|------|
| `operatorId` | Required, must exist, must be active |
| `productTypeId` | Required, must exist, must be active |
| `productionLineId` | Required, must exist, must be active |
| `quantity` | Required, must be >= 1 |

**Success Response (201 Created):**
```json
{
  "success": true,
  "data": {
    "palletId": 12345,
    "scannedValue": "003800000001",
    "operator": {
      "id": 1,
      "name": "ياسر أحمد"
    },
    "productType": {
      "id": 2,
      "name": "صحن دائري أبيض",
      "productName": "صحن دائري",
      "prefix": "0038",
      "color": "أبيض",
      "packageQuantity": 500,
      "packageUnit": "PIECE"
    },
    "productionLine": {
      "id": 1,
      "name": "خط الإنتاج 1",
      "lineNumber": 1
    },
    "quantity": 200,
    "currentDestination": "PRODUCTION",
    "createdAt": "2026-03-30T10:15:30.123+03:00",
    "createdAtDisplay": "٣٠ مارس ٢٠٢٦ - ١٠:١٥ ص"
  }
}
```

---

### 6.6 Record Print Attempt (Optional Audit)

**Endpoint:** `POST /api/v1/palletizing/pallets/{id}/print-attempts`

**Request:**
```json
{
  "printerIdentifier": "PRINTER_01",
  "status": "SUCCESS",
  "failureReason": null
}
```

Or for failed print:
```json
{
  "printerIdentifier": "PRINTER_01",
  "status": "FAILED",
  "failureReason": "Connection timeout"
}
```

**Response (201 Created):**
```json
{
  "success": true,
  "data": {
    "id": 789,
    "palleteId": 12345,
    "attemptNumber": 1,
    "status": "SUCCESS",
    "createdAt": "2026-03-30T10:15:45.000+03:00"
  }
}
```

---

### 6.7 Get Line Summary

**Endpoint:** `GET /api/v1/palletizing/lines/{lineId}/summary`

**Response:**
```json
{
  "success": true,
  "data": {
    "lineId": 1,
    "lineName": "خط الإنتاج 1",
    "lineNumber": 1,
    "todayPalletCount": 47,
    "lastPalletAt": "2026-03-30T10:15:30.123+03:00",
    "lastPalletAtDisplay": "١٠:١٥ ص"
  }
}
```

---

## 7. Scanned Value Generation Logic

### Format
```
PPPPSSSSSSSS
│   └──────── 8-digit serial number (zero-padded)
└──────────── 4-digit product type prefix
Total: exactly 12 numeric digits
```

### Examples
| Prefix | Serial | Scanned Value |
|--------|--------|---------------|
| `0732` | 1 | `073200000001` |
| `0732` | 125 | `073200000125` |
| `0038` | 99999999 | `003899999999` |

### Key Rules
1. **Serial is per product type** - each product type has its own counter
2. **Thread-safe** - uses `SELECT ... FOR UPDATE` pessimistic locking
3. **No separators** - no dots, dashes, or spaces
4. **Always 12 digits** - prefix (4) + serial (8)
5. **Max serial** - 99,999,999 per product type before overflow error

---

## 8. Validation Rules for Flutter

### Before Creating Pallet
1. **Operator must be selected** - cannot be null
2. **Product type must be selected** - cannot be null
3. **Production line must be selected** - cannot be null
4. **Quantity must be >= 1**

### Handle Inactive Entities
The backend validates that operator, product type, and production line are all active. If any becomes inactive between fetch and submit, you'll get an error. Consider:
- Refreshing lists periodically
- Handling `OPERATOR_INACTIVE`, `PRODUCT_TYPE_INACTIVE`, `PRODUCTION_LINE_INACTIVE` errors gracefully

---

## 9. What Flutter Does After Create-Pallet Success

1. **Extract `scannedValue`** from response
2. **Generate QR code locally** using `scannedValue` as the data
   ```dart
   // Example with qr_flutter package
   QrImage(
     data: response.scannedValue, // "073200000001"
     version: QrVersions.auto,
     size: 200.0,
   )
   ```
3. **Display QR preview** on screen with pallet info
4. **Convert QR to printer format** (if printing immediately)
5. **Send to printer** via Bluetooth/WiFi
6. **Optionally log print attempt** via `/print-attempts` endpoint
7. **Show success confirmation** to operator

---

## 10. QR Code Input

**Use `scannedValue` directly as QR data:**

```dart
// Response from backend
final createResponse = await api.createPallet(request);

// QR code data is simply the scannedValue
final qrData = createResponse.scannedValue; // e.g., "073200000001"

// Generate QR code with this data
final qrCode = QrPainter(
  data: qrData,
  version: QrVersions.auto,
);
```

**Do NOT:**
- Add prefixes or suffixes to the scanned value
- Encode as JSON or other format
- Add URLs or metadata

**The QR code data = `scannedValue` exactly as returned**

---

## 11. Print Audit Endpoint Details

### Purpose
Optional audit logging. Backend does NOT participate in actual printing.

### When to Call
- After successful print: `status: "SUCCESS"`
- After failed print: `status: "FAILED"` with `failureReason`
- For pending/queued: `status: "PENDING"` (optional)

### Retry Tracking
- `attemptNumber` auto-increments per pallet
- First print = attempt 1, retry = attempt 2, etc.

### Not Required
This endpoint is **optional**. Flutter app can skip it if print audit logging is not needed.

---

## 12. Error Codes Flutter Must Handle

### Authentication Errors
| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `AUTH_INVALID_CREDENTIALS` | 401 | Wrong email/password |
| `USER_DISABLED` | 403 | Account is disabled |
| `ROLE_NOT_ALLOWED` | 403 | User is not PALLETIZER/DRIVER/OFFICER |

### Validation Errors
| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `VALIDATION_ERROR` | 400 | Request body validation failed |
| `OPERATOR_NOT_FOUND` | 404 | Operator ID doesn't exist |
| `OPERATOR_INACTIVE` | 400 | Operator exists but inactive |
| `PRODUCT_TYPE_NOT_FOUND` | 404 | Product type ID doesn't exist |
| `PRODUCT_TYPE_INACTIVE` | 400 | Product type exists but inactive |
| `PRODUCTION_LINE_NOT_FOUND` | 404 | Production line ID doesn't exist |
| `PRODUCTION_LINE_INACTIVE` | 400 | Production line exists but inactive |
| `PALLET_NOT_FOUND` | 404 | Pallet ID doesn't exist (for print-attempts) |

### System Errors
| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `SERIAL_GENERATION_FAILED` | 500 | Serial counter overflow or DB error |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

### Error Response Format
```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "OPERATOR_INACTIVE",
    "message": "Operator is inactive: ياسر أحمد",
    "details": null
  }
}
```

---

## 13. Migration / Compatibility Notes

### Timezone Handling
- **Backend stores:** UTC
- **API returns:** ISO-8601 with Asia/Hebron offset (e.g., `+03:00` or `+02:00` depending on DST)
- **Display fields:** Arabic-formatted strings provided (e.g., `createdAtDisplay`)

### Existing Warehouse Integration
- Pallets created via palletizing app get `sourceType: PRODUCTION_LINE`
- Initial status is `Destination.PRODUCTION`
- These pallets can later move through the warehouse flow (WH1, WH2, OUT, etc.)
- The warehouse app (DRIVER/OFFICER roles) can scan and move these pallets

### JWT Token
- Same token format as warehouse app
- Include in all requests: `Authorization: Bearer <token>`
- Token contains: user ID, email, role

### App Updates
- PALLETIZER role can access `/api/v1/app-updates/**` endpoint
- Use this for in-app update checks (same as warehouse app)

---

## 14. Quick Integration Checklist

```
□ Implement login with PALLETIZER credentials
□ Store JWT token securely
□ Fetch and cache operators list
□ Fetch and cache product types list
□ Fetch and cache production lines list
□ Build pallet creation form with validations
□ Call POST /pallets with form data
□ Extract scannedValue from response
□ Generate QR code locally using scannedValue
□ Display QR preview with pallet details
□ Implement printer discovery/connection (Bluetooth/WiFi)
□ Convert QR to printer format (TSPL/ZPL)
□ Send print command to printer
□ (Optional) Log print attempt via /print-attempts
□ Handle all error codes gracefully
□ Implement offline handling if needed
□ Add line summary display (GET /lines/{id}/summary)
```

---

## 15. Sample Flutter Integration Code

```dart
// Example service class structure

class PalletizingService {
  final ApiClient _api;
  
  Future<List<Operator>> getOperators() async {
    final response = await _api.get('/api/v1/palletizing/operators');
    return (response['data'] as List)
        .map((json) => Operator.fromJson(json))
        .toList();
  }
  
  Future<List<ProductType>> getProductTypes() async {
    final response = await _api.get('/api/v1/palletizing/product-types');
    return (response['data'] as List)
        .map((json) => ProductType.fromJson(json))
        .toList();
  }
  
  Future<List<ProductionLine>> getProductionLines() async {
    final response = await _api.get('/api/v1/palletizing/production-lines');
    return (response['data'] as List)
        .map((json) => ProductionLine.fromJson(json))
        .toList();
  }
  
  Future<CreatePalletResponse> createPallet({
    required int operatorId,
    required int productTypeId,
    required int productionLineId,
    required int quantity,
  }) async {
    final response = await _api.post('/api/v1/palletizing/pallets', body: {
      'operatorId': operatorId,
      'productTypeId': productTypeId,
      'productionLineId': productionLineId,
      'quantity': quantity,
    });
    return CreatePalletResponse.fromJson(response['data']);
  }
  
  // After getting response, generate QR:
  // final qrData = response.scannedValue; // "073200000001"
}
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-30  
**Backend Version:** Spring Boot 4.0.3 / Java 17
