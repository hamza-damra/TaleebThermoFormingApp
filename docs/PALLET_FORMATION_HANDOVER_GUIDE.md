# Pallet Formation Shift Handover - Backend API Guide

This document describes the backend changes and API endpoints for the shift handover feature in the Pallet Formation app.

---

## Overview

The shift handover feature allows operators to hand over incomplete pallets between shifts. When an operator ends their shift with incomplete pallets, they declare a pending handover. The incoming shift operator sees a confirmation prompt and can either:
- **Confirm** the handover (accepts responsibility)
- **Reject** the handover (creates a dispute for admin review)

---

## API Endpoints

All endpoints require **PALLETIZER** role authentication via JWT.

### 1. Get Current Shift

Returns the current shift based on the active schedule profile and Palestine timezone.

```
GET /api/v1/shift-schedule/current-shift
```

**Response:**
```json
{
  "success": true,
  "data": {
    "shiftType": "MORNING",
    "shiftDisplayNameAr": "صباحي",
    "shiftDisplayNameEn": "Morning",
    "profileType": "REGULAR",
    "profileDisplayNameAr": "جدول عادي",
    "profileDisplayNameEn": "Regular Schedule",
    "startTime": "07:00",
    "endTime": "16:00"
  }
}
```

**Shift Types:**
| Value | Arabic | English |
|-------|--------|---------|
| `MORNING` | صباحي | Morning |
| `EVENING` | مسائي | Evening |
| `NIGHT` | ليلي | Night |

**Profile Types:**
| Value | Arabic | English |
|-------|--------|---------|
| `REGULAR` | جدول عادي | Regular Schedule |
| `RAMADAN` | جدول رمضان | Ramadan Schedule |

---

### 2. Create Pending Handover

Called when the outgoing shift operator declares incomplete pallets.

```
POST /api/v1/shift-handover
```

**Request Body:**
```json
{
  "productionLineId": 1,
  "operatorId": 1,
  "items": [
    {
      "productTypeId": 1,
      "quantity": 50,
      "scannedValue": "000112345678",
      "notes": "Optional notes"
    },
    {
      "productTypeId": 2,
      "quantity": 30,
      "scannedValue": null,
      "notes": null
    }
  ]
}
```

**Request Fields:**
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `productionLineId` | Long | Yes | ID of the production line |
| `operatorId` | Long | Yes | ID of the outgoing operator |
| `items` | Array | Yes | At least one item required |
| `items[].productTypeId` | Long | Yes | Product type ID |
| `items[].quantity` | Integer | Yes | Current incomplete quantity (≥1) |
| `items[].scannedValue` | String | No | 12-digit pallet code if exists |
| `items[].notes` | String | No | Optional notes |

**Response (201 Created):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "productionLineId": 1,
    "productionLineName": "خط الإنتاج 1",
    "outgoingOperatorId": 1,
    "outgoingOperatorName": "أحمد محمد",
    "outgoingShiftType": "MORNING",
    "outgoingShiftDisplayNameAr": "صباحي",
    "incomingOperatorId": null,
    "incomingOperatorName": null,
    "incomingShiftType": null,
    "incomingShiftDisplayNameAr": null,
    "status": "PENDING",
    "statusDisplayNameAr": "قيد الانتظار",
    "items": [...],
    "itemCount": 2,
    "totalQuantity": 80,
    "createdAt": "2025-01-15T10:30:00Z",
    "createdAtDisplay": "15/01/2025 12:30"
  }
}
```

**Error Cases:**
- `409 PENDING_HANDOVER_EXISTS` - A pending handover already exists for this production line
- `404 PRODUCTION_LINE_NOT_FOUND` - Production line not found
- `404 OPERATOR_NOT_FOUND` - Operator not found
- `404 PRODUCT_TYPE_NOT_FOUND` - Product type not found

---

### 3. Get Pending Handover for Line

Check if there's a pending handover for a production line. Call this when an operator logs in to show the confirmation dialog if a pending handover exists.

```
GET /api/v1/shift-handover/pending?lineId={productionLineId}
```

**Response (pending exists):**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "productionLineId": 1,
    "productionLineName": "خط الإنتاج 1",
    "outgoingOperatorId": 1,
    "outgoingOperatorName": "أحمد محمد",
    "outgoingShiftType": "MORNING",
    "outgoingShiftDisplayNameAr": "صباحي",
    "status": "PENDING",
    "items": [
      {
        "id": 1,
        "productTypeId": 1,
        "productTypeName": "لنش بوكس أبيض 500",
        "quantity": 50,
        "scannedValue": "000112345678",
        "notes": null
      }
    ],
    "itemCount": 1,
    "totalQuantity": 50,
    "createdAt": "2025-01-15T10:30:00Z",
    "createdAtDisplay": "15/01/2025 12:30"
  }
}
```

**Response (no pending handover):**
```json
{
  "success": true,
  "data": null
}
```

---

### 4. Confirm Handover

Called when the incoming shift operator accepts the handover.

```
POST /api/v1/shift-handover/{id}/confirm
```

**Request Body:**
```json
{
  "incomingOperatorId": 2
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "status": "CONFIRMED",
    "statusDisplayNameAr": "مؤكد",
    "incomingOperatorId": 2,
    "incomingOperatorName": "محمد علي",
    "incomingShiftType": "EVENING",
    "incomingShiftDisplayNameAr": "مسائي",
    "confirmedAt": "2025-01-15T14:05:00Z",
    "confirmedAtDisplay": "15/01/2025 16:05",
    ...
  }
}
```

**Error Cases:**
- `404 HANDOVER_NOT_FOUND` - Handover not found
- `409 HANDOVER_ALREADY_RESOLVED` - Handover already confirmed or disputed
- `404 OPERATOR_NOT_FOUND` - Incoming operator not found

---

### 5. Reject Handover

Called when the incoming shift operator disputes the handover. Creates a dispute record for admin investigation.

```
POST /api/v1/shift-handover/{id}/reject
```

**Request Body:**
```json
{
  "incomingOperatorId": 2
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 1,
    "status": "DISPUTED",
    "statusDisplayNameAr": "متنازع عليه",
    "incomingOperatorId": 2,
    "incomingOperatorName": "محمد علي",
    "incomingShiftType": "EVENING",
    "incomingShiftDisplayNameAr": "مسائي",
    "disputedAt": "2025-01-15T14:05:00Z",
    "disputedAtDisplay": "15/01/2025 16:05",
    ...
  }
}
```

---

### 6. Get Handover Details

Get full details of a specific handover.

```
GET /api/v1/shift-handover/{id}
```

---

## Handover Status Flow

```
PENDING ──┬──> CONFIRMED (accepted by incoming shift)
          │
          └──> DISPUTED (rejected by incoming shift) ──> RESOLVED (admin resolved)
```

**Status Values:**
| Value | Arabic | Description |
|-------|--------|-------------|
| `PENDING` | قيد الانتظار | Waiting for incoming shift to respond |
| `CONFIRMED` | مؤكد | Accepted by incoming shift |
| `DISPUTED` | متنازع عليه | Rejected, pending admin investigation |
| `RESOLVED` | تم الحل | Admin marked dispute as resolved |

---

## App Implementation Flow

### End of Shift (Outgoing Operator)

1. User taps "End Shift" button
2. App shows list of incomplete pallets (quantities not reaching package target)
3. If incomplete pallets exist:
   - Show confirmation dialog: "You have X incomplete pallets. Handover to next shift?"
   - User confirms → Call `POST /api/v1/shift-handover`
   - Show success message
4. If no incomplete pallets, end shift normally

### Start of Shift (Incoming Operator)

1. After operator selection and production line selection
2. Call `GET /api/v1/shift-handover/pending?lineId={lineId}`
3. If pending handover exists (`data` is not null):
   - Show modal with handover details:
     - Outgoing operator name
     - Shift type
     - List of items with quantities
     - Total quantity
   - Two buttons: "تأكيد الاستلام" (Confirm) / "رفض" (Reject)
   - **Confirm**: Call `POST /api/v1/shift-handover/{id}/confirm`
   - **Reject**: Call `POST /api/v1/shift-handover/{id}/reject`
4. If no pending handover, proceed normally

### Display Current Shift

Call `GET /api/v1/shift-schedule/current-shift` to display current shift name in the app header or status bar.

---

## Error Handling

All error responses follow the standard format:

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message"
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `PENDING_HANDOVER_EXISTS` | 409 | A pending handover already exists for this line |
| `HANDOVER_NOT_FOUND` | 404 | Handover ID not found |
| `HANDOVER_ALREADY_RESOLVED` | 409 | Handover already confirmed/disputed |
| `NO_PENDING_HANDOVER` | 404 | No pending handover for this line |
| `SHIFT_PROFILE_NOT_FOUND` | 404 | No active schedule profile |
| `OPERATOR_NOT_FOUND` | 404 | Operator ID not found |
| `PRODUCTION_LINE_NOT_FOUND` | 404 | Production line ID not found |
| `PRODUCT_TYPE_NOT_FOUND` | 404 | Product type ID not found |

---

## Admin Panel

Admins can:
1. **Manage Shift Schedules** (`/web/admin/shift-schedules`)
   - View Regular and Ramadan profiles
   - Edit shift start/end times
   - Activate/deactivate profiles

2. **View Handover Disputes** (`/web/admin/handover-disputes`)
   - See list of disputed handovers
   - View dispute details (operators, shift types, items)
   - Mark disputes as resolved with optional notes

---

## Notes

- All times are in **Palestine timezone (Asia/Hebron)**
- Timestamps in responses are UTC (`createdAt`) with display versions in local format (`createdAtDisplay`)
- Only one pending handover per production line at a time
- Once a handover is confirmed or rejected, it cannot be changed
- Disputes are visible to admin until resolved
