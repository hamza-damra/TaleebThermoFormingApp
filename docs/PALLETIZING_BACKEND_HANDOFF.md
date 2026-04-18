# Palletizing Backend Handoff Documentation

This document provides all details needed by the Flutter app AI agent to integrate with the palletizing backend module.

---

## Overview

The palletizing backend module enables factory floor pallet creation with auto-generated QR codes. It integrates with the existing warehouse system - pallets created here can later be scanned and moved by the warehouse app.

**Base URL:** `/api/v1/palletizing`  
**Authentication:** JWT Bearer token  
**Required Role:** `PALLETIZER`

---

## Authentication

### Login Endpoint

```
POST /api/v1/auth/login
Content-Type: application/json
```

**Request:**
```json
{
  "email": "palletizer@example.com",
  "password": "password123"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiJ9...",
    "user": {
      "id": 5,
      "name": "محمد المشغل",
      "email": "palletizer@example.com",
      "role": "PALLETIZER"
    }
  }
}
```

**Usage:** Include token in all subsequent requests:
```
Authorization: Bearer <token>
```

---

## Endpoints

### 1. Get Active Operators

Fetch all active operators for selection dropdown.

```
GET /api/v1/palletizing/operators
Authorization: Bearer <token>
```

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
      "name": "محمود سالم",
      "code": "OP002"
    }
  ]
}
```

---

### 2. Get Active Product Types

Fetch all active product types for selection.

```
GET /api/v1/palletizing/product-types
Authorization: Bearer <token>
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "لنش بوكس / أسود / 500 عبوة",
      "productName": "لنش بوكس",
      "prefix": "0732",
      "color": "أسود",
      "packageQuantity": 500,
      "packageUnit": "CARTON",
      "packageUnitDisplayName": "عبوة"
    },
    {
      "id": 2,
      "name": "صحن دائري / أبيض / 1000 كيس",
      "productName": "صحن دائري",
      "prefix": "0038",
      "color": "أبيض",
      "packageQuantity": 1000,
      "packageUnit": "BAG",
      "packageUnitDisplayName": "كيس"
    }
  ]
}
```

**Important Fields:**
- `prefix`: 4-digit code used in QR generation
- `packageUnit`: Either `CARTON` or `BAG`
- `packageUnitDisplayName`: Arabic display name

---

### 3. Get Active Production Lines

Fetch all active production lines.

```
GET /api/v1/palletizing/production-lines
Authorization: Bearer <token>
```

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

### 4. Create Pallet (Core Endpoint)

Creates a new pallet with auto-generated scanned value.

```
POST /api/v1/palletizing/pallets
Authorization: Bearer <token>
Content-Type: application/json
```

**Request:**
```json
{
  "operatorId": 1,
  "productTypeId": 2,
  "productionLineId": 1,
  "quantity": 20
}
```

**Validation Rules:**
| Field | Rule |
|-------|------|
| `operatorId` | Required, must exist, must be active |
| `productTypeId` | Required, must exist, must be active |
| `productionLineId` | Required, must exist, must be active |
| `quantity` | Required, minimum 1 |

**Response (201 Created):**
```json
{
  "success": true,
  "data": {
    "palletId": 123,
    "scannedValue": "073200000001",
    "qrCodeData": "073200000001",
    "operator": {
      "id": 1,
      "name": "ياسر أحمد"
    },
    "productType": {
      "id": 2,
      "name": "لنش بوكس / أسود / 500 عبوة",
      "productName": "لنش بوكس",
      "prefix": "0732",
      "color": "أسود",
      "packageQuantity": 500,
      "packageUnit": "CARTON"
    },
    "productionLine": {
      "id": 1,
      "name": "خط الإنتاج 1",
      "lineNumber": 1
    },
    "quantity": 20,
    "currentDestination": "PRODUCTION",
    "createdAt": "2026-03-30T07:00:00.000Z",
    "createdAtDisplay": "الأحد 30 مارس 2026 10:00 ص"
  }
}
```

**Critical Response Fields:**
| Field | Description |
|-------|-------------|
| `palletId` | Database ID, use for print logging |
| `scannedValue` | The 12-digit unique code |
| `qrCodeData` | Same as scannedValue, use for QR rendering |
| `currentDestination` | Always `PRODUCTION` for new pallets |

---

### 5. Record Print Attempt

Log print success/failure for audit trail.

```
POST /api/v1/palletizing/pallets/{palletId}/print-attempts
Authorization: Bearer <token>
Content-Type: application/json
```

**Request:**
```json
{
  "printerIdentifier": "PRINTER_01",
  "status": "SUCCESS",
  "failureReason": null
}
```

**Status Values:**
| Status | When to Use |
|--------|-------------|
| `SUCCESS` | Print completed successfully |
| `FAILED` | Print failed (include `failureReason`) |
| `PENDING` | Print queued/in progress |

**Response (201 Created):**
```json
{
  "success": true,
  "data": {
    "id": 45,
    "palleteId": 123,
    "attemptNumber": 1,
    "status": "SUCCESS",
    "createdAt": "2026-03-30T07:00:05.000Z"
  }
}
```

---

### 6. Get Line Summary

Get production statistics for a line.

```
GET /api/v1/palletizing/lines/{lineId}/summary
Authorization: Bearer <token>
```

**Response:**
```json
{
  "success": true,
  "data": {
    "lineId": 1,
    "lineName": "خط الإنتاج 1",
    "lineNumber": 1,
    "todayPalletCount": 42,
    "lastPalletAt": "2026-03-30T06:55:00.000Z",
    "lastPalletAtDisplay": "10:55 ص"
  }
}
```

---

## Scanned Value Format

The `scannedValue` is a 12-digit numeric string:

```
PPPPSSSSSSSS
│    │
│    └── 8-digit serial (zero-padded)
└─────── 4-digit product type prefix
```

**Examples:**
| Prefix | Serial | Scanned Value |
|--------|--------|---------------|
| 0732 | 1 | 073200000001 |
| 0732 | 125 | 073200000125 |
| 0038 | 9999 | 003800009999 |

**Generation Rules:**
- Serial starts at 1 for each product type
- Serials are independent per product type
- Thread-safe under concurrent requests
- Maximum serial: 99,999,999

---

## QR Code Rendering

**Content:** Use `qrCodeData` field directly (same as `scannedValue`)  
**Format:** Plain numeric string, no encoding needed  
**Size:** Recommend minimum 200x200 pixels for reliable scanning

**Label Content Suggestions:**
- QR code with `qrCodeData`
- `scannedValue` as human-readable text
- Product name (`productType.productName`)
- Color (`productType.color`)
- Quantity
- Production line name
- Date/time

---

## Error Handling

### Error Response Format

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message",
    "details": { ... }
  }
}
```

### Common Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `OPERATOR_NOT_FOUND` | 404 | Operator ID doesn't exist |
| `OPERATOR_INACTIVE` | 400 | Operator is disabled |
| `PRODUCT_TYPE_NOT_FOUND` | 404 | Product type ID doesn't exist |
| `PRODUCT_TYPE_INACTIVE` | 400 | Product type is disabled |
| `PRODUCTION_LINE_NOT_FOUND` | 404 | Production line ID doesn't exist |
| `PRODUCTION_LINE_INACTIVE` | 400 | Production line is disabled |
| `PALLET_NOT_FOUND` | 404 | Pallet ID doesn't exist (for print logging) |
| `SERIAL_GENERATION_FAILED` | 500 | Serial counter overflow (unlikely) |
| `VALIDATION_ERROR` | 400 | Request validation failed |
| `AUTH_INVALID_CREDENTIALS` | 401 | Login failed |
| `ROLE_NOT_ALLOWED` | 403 | User role cannot use this app |

### Validation Error Details

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Validation failed",
    "details": {
      "operatorId": "Operator ID is required",
      "quantity": "Quantity must be at least 1"
    }
  }
}
```

---

## Pallet Creation Flow

### Step-by-Step Implementation

```
1. User selects operator from dropdown
   └─ GET /api/v1/palletizing/operators

2. User selects product type from dropdown
   └─ GET /api/v1/palletizing/product-types

3. User selects production line from dropdown
   └─ GET /api/v1/palletizing/production-lines

4. User enters quantity (numeric input, min 1)

5. User taps "Create Pallet" button
   └─ POST /api/v1/palletizing/pallets
   └─ Store full response locally

6. On success, render QR code label
   └─ Use response.qrCodeData for QR
   └─ Display all relevant info

7. Trigger local print
   └─ Use device-specific print API
   └─ Bluetooth/USB printer integration

8. Log print result
   └─ POST /api/v1/palletizing/pallets/{palletId}/print-attempts
   └─ status: SUCCESS or FAILED
```

---

## Print Retry Flow

If print fails after pallet creation:

```
1. Pallet is ALREADY CREATED (scannedValue exists)
   └─ Do NOT call create endpoint again!

2. Store failed pallet locally
   └─ Save palletId and full response

3. Retry print using stored data
   └─ Re-render QR from stored qrCodeData
   └─ Attempt print again

4. Log each retry attempt
   └─ POST /api/v1/palletizing/pallets/{palletId}/print-attempts
   └─ attemptNumber auto-increments
```

**Important:** The `scannedValue` is permanent once created. Never create a duplicate pallet for the same physical item.

---

## Offline Considerations

**Recommended Approach:**
1. Cache operators, product types, and lines on app start
2. Allow selection from cached data
3. Queue pallet creation requests if offline
4. Sync when connection restored
5. Handle conflicts (unlikely but possible)

**Critical:** Serial generation happens server-side only. Offline pallet creation is NOT possible without server connection.

---

## Data Caching Recommendations

| Data | Cache Duration | Refresh Trigger |
|------|----------------|-----------------|
| Operators | App session | Pull-to-refresh |
| Product Types | App session | Pull-to-refresh |
| Production Lines | App session | Pull-to-refresh |
| Created Pallets | Until printed | User action |

---

## Security Notes

- JWT tokens expire (check `exp` claim)
- Refresh token flow may be needed for long sessions
- PALLETIZER role has limited access:
  - ✅ Palletizing endpoints
  - ✅ App updates endpoint
  - ✅ User info (`/me`)
  - ❌ Warehouse movements
  - ❌ Admin endpoints
  - ❌ Dashboard

---

## Testing Checklist

- [ ] Login with PALLETIZER role
- [ ] Fetch and display operators
- [ ] Fetch and display product types
- [ ] Fetch and display production lines
- [ ] Create pallet with valid data
- [ ] Render QR code from response
- [ ] Print label successfully
- [ ] Log print success
- [ ] Handle print failure
- [ ] Retry print from stored data
- [ ] Log print retry
- [ ] Handle validation errors gracefully
- [ ] Handle network errors
- [ ] Handle session expiry

---

## Sample Implementation (Pseudocode)

```dart
// Create pallet and print
Future<void> createAndPrint() async {
  try {
    // 1. Create pallet
    final response = await api.post('/palletizing/pallets', {
      'operatorId': selectedOperator.id,
      'productTypeId': selectedProductType.id,
      'productionLineId': selectedLine.id,
      'quantity': quantity,
    });
    
    final pallet = response.data;
    
    // 2. Render QR
    final qrImage = QrCode.generate(pallet.qrCodeData);
    
    // 3. Print label
    final printSuccess = await printer.print(buildLabel(pallet, qrImage));
    
    // 4. Log result
    await api.post('/palletizing/pallets/${pallet.palletId}/print-attempts', {
      'printerIdentifier': printer.id,
      'status': printSuccess ? 'SUCCESS' : 'FAILED',
      'failureReason': printSuccess ? null : printer.lastError,
    });
    
    if (printSuccess) {
      showSuccess('تم إنشاء وطباعة المشتاح بنجاح');
    } else {
      // Store for retry
      savePendingPrint(pallet);
      showError('فشلت الطباعة - يمكنك إعادة المحاولة');
    }
    
  } on ApiError catch (e) {
    showError(e.message);
  }
}
```

---

## Warehouse Integration

Pallets created here integrate with the warehouse system:

1. **Initial State:** `PRODUCTION` destination
2. **First Warehouse Scan:** Transitions to warehouse destination
3. **Normal Flow:** Same as any other pallet

The warehouse app will see these pallets with `PRODUCTION` as their current location until moved.

---

## Contact / Support

For backend issues or questions:
- Check error codes and messages
- Verify JWT token validity
- Ensure correct role (PALLETIZER)
- Check request format matches documentation

---

*Document Version: 1.0*  
*Last Updated: March 2026*
