# API Contract: Handover Review Endpoints

## Overview

This document defines the backend API contract for the handover review flow. It clarifies the two different DTO shapes, their intended use, and nullability rules.

---

## Endpoints

### 1. Create Handover

```
POST /api/v1/palletizing-line/lines/{lineId}/handover
```

**Request Body**: `LineHandoverRequest`

```json
{
  "incompletePalletProductTypeId": 5, // optional
  "incompletePalletQuantity": 25, // required if productTypeId is set, must be > 0
  "looseBalances": [
    // optional
    { "productTypeId": 6, "loosePackageCount": 4 }
  ],
  "notes": "End of shift" // optional
}
```

**Response**: `ApiResponse<LineHandoverResponse>` (HTTP 201)

---

### 2. Get Pending Handover (Full Detail)

```
GET /api/v1/palletizing-line/lines/{lineId}/handover/pending
```

**Response**: `ApiResponse<LineHandoverResponse>`

Returns full handover detail if a PENDING handover exists for the line.
Returns `ApiResponse` with `data: null` if no pending handover exists.

**This is the endpoint the review screen MUST call after refresh to restore full detail.**

---

### 3. Confirm Handover

```
POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm
```

**Response**: `ApiResponse<LineHandoverResponse>` (HTTP 200)

Requires active authorization on the line (incoming operator must be PIN-authorized).

---

### 4. Reject Handover

```
POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject
```

**Request Body** (optional): `LineHandoverRejectRequest`

```json
{
  "notes": "Counts do not match" // optional
}
```

**Response**: `ApiResponse<LineHandoverResponse>` (HTTP 200)

---

### 5. Get Line State (Condensed Summary)

```
GET /api/v1/palletizing-line/lines/{lineId}/state
```

**Response**: `ApiResponse<LineStateResponse>`

Contains `pendingHandover` as a condensed `LineHandoverSummary` (not full detail).
Use this for determining `lineUiMode` and whether to show the review screen, but NOT for populating the review screen content.

---

### 6. Bootstrap (All Lines)

```
GET /api/v1/palletizing-line/bootstrap
```

**Response**: `ApiResponse<BootstrapResponse>`

Contains `lines[]` — each with `LineStateResponse` (same condensed summary).

---

## LineHandoverResponse (Full Detail DTO)

```
{
  "id": Long,
  "lineId": Long,
  "lineName": String,
  "status": "PENDING" | "CONFIRMED" | "REJECTED" | "RESOLVED",
  "statusDisplayNameAr": String,
  "outgoingOperatorName": String,
  "outgoingOperatorId": Long,
  "incomingOperatorName": String?,           // omitted if null (before confirm/reject)
  "incomingOperatorId": Long?,               // omitted if null
  "incompletePallet": {                      // omitted if null (no incomplete pallet)
    "productTypeId": Long,
    "productTypeName": String,
    "quantity": Integer
  },
  "looseBalances": [                         // always present, may be empty []
    {
      "productTypeId": Long,
      "productTypeName": String,
      "loosePackageCount": int
    }
  ],
  "looseBalanceCount": int,                  // always present, may be 0
  "handoverType": "NONE" | "INCOMPLETE_PALLET_ONLY" | "LOOSE_BALANCES_ONLY" | "BOTH",
  "notes": String?,                          // omitted if null
  "createdAt": ISO-8601 Instant,
  "createdAtDisplay": String,
  "confirmedAt": Instant?,                   // omitted if null
  "confirmedAtDisplay": String?,             // omitted if null
  "rejectedAt": Instant?,                    // omitted if null
  "rejectedAtDisplay": String?,              // omitted if null
  "rejectionNotes": String?,                 // omitted if null
  "resolutionNotes": String?,                // omitted if null
  "resolvedByUserName": String?,             // omitted if null
  "resolvedAt": Instant?,                    // omitted if null
  "resolvedAtDisplay": String?               // omitted if null
}
```

---

## LineHandoverSummary (Condensed — inside LineStateResponse)

```
{
  "handoverId": Long,
  "outgoingOperatorName": String,
  "status": "PENDING",
  "looseBalanceCount": int,                  // count only; no item details
  "hasIncompletePallet": boolean,
  "incompletePalletProductTypeName": String?, // omitted if no incomplete pallet
  "handoverType": "NONE" | "INCOMPLETE_PALLET_ONLY" | "LOOSE_BALANCES_ONLY" | "BOTH",
  "createdAtDisplay": String,
  "notes": String?                           // omitted if null
}
```

---

## Consistency Between Initial Response and Refresh Response

| Aspect            | POST /handover (create) | GET /handover/pending (refresh) |
| ----------------- | ----------------------- | ------------------------------- |
| DTO Shape         | `LineHandoverResponse`  | `LineHandoverResponse`          |
| Loose Balances    | Full list               | Full list (identical)           |
| Incomplete Pallet | Full object             | Full object (identical)         |
| Handover Type     | Computed                | Computed (identical logic)      |
| Data Source       | Freshly saved entity    | DB query with EntityGraph       |
| Mapping Function  | `toResponse()`          | `toResponse()` (same method)    |

**The two responses are produced by the exact same `toResponse()` method.** There is zero difference in shape or content between the initial creation response and the refresh fetch response.

---

## lineUiMode Values

| Mode                              | Meaning                                                  | Frontend Action                                                          |
| --------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `NEEDS_AUTHORIZATION`             | No operator on line                                      | Show PIN entry                                                           |
| `AUTHORIZED`                      | Operator active, no pending handover                     | Normal production screen                                                 |
| `PENDING_HANDOVER_NEEDS_INCOMING` | Handover created, outgoing released, no incoming yet     | Show PIN entry for incoming operator, then review                        |
| `PENDING_HANDOVER_REVIEW`         | Incoming operator authorized AND pending handover exists | Show review screen — **must call GET /handover/pending for full detail** |
