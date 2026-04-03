# Frontend Handover Required Flow

This document is the exact specification for the Frontend AI Agent to implement the per-line handover UX in the Takween Al-Mashtah (تكوين المشاتيح) app.

---

## CRITICAL UI CHANGES

### REMOVE from the main line card:
- **Remove any visible generic "change operator" / "تغيير المشغل" button** from the main line UI
- The `DELETE /lines/{lineId}/authorization` endpoint exists for admin/emergency only — do NOT expose it as a primary action

### KEEP as the main visible action:
- **"تسليم مناوبة"** button — this is the ONLY way an operator normally leaves a line

---

## API Base URL

All palletizing endpoints are under:
```
/api/v1/palletizing-line
```

Authentication: Device API key via `X-Device-Key` header (not JWT).

---

## Line State & UI Modes

### Get Line State

```
GET /api/v1/palletizing-line/lines/{lineId}/state
```

**Response:**
```json
{
  "success": true,
  "data": {
    "lineId": 1,
    "lineName": "خط 1",
    "lineNumber": 1,
    "authorized": true,
    "lineUiMode": "AUTHORIZED",
    "canInitiateHandover": true,
    "canConfirmHandover": false,
    "canRejectHandover": false,
    "blocked": false,
    "blockedReason": null,
    "pendingHandover": null,
    "authorization": {
      "authorizationId": 100,
      "operatorName": "أحمد",
      "operatorId": 10,
      "lineId": 1,
      "lineName": "خط 1",
      "status": "ACTIVE"
    },
    "sessionTable": [ ... ]
  }
}
```

### UI Modes — The Single Source of Truth

The `lineUiMode` field tells the frontend **exactly** which screen to render:

| `lineUiMode` | Meaning | What to Show |
|---|---|---|
| `NEEDS_AUTHORIZATION` | No active operator | PIN entry overlay — incoming operator must authorize |
| `AUTHORIZED` | Operator working normally | Normal production: operator info, product selector, session table, **"تسليم مناوبة" button** |
| `PENDING_HANDOVER_NEEDS_INCOMING` | Outgoing created handover, line released | "في انتظار المشغل القادم" screen with handover summary card + PIN entry for incoming |
| `PENDING_HANDOVER_REVIEW` | Incoming authorized + pending handover exists | Handover detail card with **تأكيد / رفض** buttons |

### Action Flags

| Flag | When `true` |
|------|------------|
| `canInitiateHandover` | `AUTHORIZED` mode — show "تسليم مناوبة" button |
| `canConfirmHandover` | `PENDING_HANDOVER_REVIEW` mode — show "تأكيد الاستلام" button |
| `canRejectHandover` | `PENDING_HANDOVER_REVIEW` mode — show "رفض التسليم" button |

### `pendingHandover` Summary (when present)

```json
{
  "handoverId": 500,
  "outgoingOperatorName": "أحمد",
  "status": "PENDING",
  "looseBalanceCount": 2,
  "hasIncompletePallet": true,
  "incompletePalletProductTypeName": "أحمر 20 كغ",
  "createdAtDisplay": "الأربعاء ١٥ يناير ٢٠٢٥ ٠٢:٣٠ م",
  "notes": "ملاحظات نهاية الوردية",
  "handoverType": "BOTH"
}
```

`handoverType` values: `NONE`, `INCOMPLETE_PALLET_ONLY`, `LOOSE_BALANCES_ONLY`, `BOTH`.

---

## Outgoing Handover Creation Flow — Step by Step

### Step 1 — Operator presses "تسليم مناوبة"

The button is visible when `canInitiateHandover: true` (i.e., `lineUiMode == "AUTHORIZED"`).

### Step 2 — First handover decision dialog

Show a dialog asking the outgoing operator:

> **هل يوجد مشاتيح ناقصة؟**
> **هل يوجد فالت؟**

The operator answers with one of 4 outcomes:
1. **لا يوجد مشاتيح ناقصة ولا فالت** — clean handover
2. **مشاتيح ناقصة فقط** — incomplete pallet only
3. **فالت فقط** — loose balances only
4. **مشاتيح ناقصة وفالت** — both

### Step 3 — If YES to either, show 3-case selection

If the operator indicated there are pending items, show:

| Option | Arabic Label |
|--------|-------------|
| Incomplete pallet only | مشاتيح ناقصة فقط |
| Loose balances only | فالت فقط |
| Both | مشاتيح ناقصة وفالت |

### Step 4 — Show input form based on selected case

#### Case A: Clean handover (no items)

Just optional notes. Send:
```json
POST /api/v1/palletizing-line/lines/{lineId}/handover

{
  "notes": "ملاحظات اختيارية"
}
```

#### Case B: Incomplete pallet only (مشاتيح ناقصة فقط)

Show form with:
- **نوع المنتج** — product type picker (required)
- **الكمية** — quantity (required, must be > 0)
- **قيمة المسح** — scanned value (optional, 12 digits)
- **ملاحظات** — notes (optional)

Send:
```json
{
  "incompletePalletProductTypeId": 5,
  "incompletePalletQuantity": 25,
  "incompletePalletScannedValue": "000100000001",
  "notes": "ملاحظات اختيارية"
}
```

#### Case C: Loose balances only (فالت فقط)

The backend auto-includes all nonzero loose balances from the operator's session. The frontend just needs to set `includeLooseBalances: true`:

```json
{
  "includeLooseBalances": true,
  "notes": "ملاحظات اختيارية"
}
```

**UX suggestion:** Before sending, call `GET /lines/{lineId}/state` and show the `sessionTable` so the operator can review their current loose balances before confirming.

#### Case D: Both (مشاتيح ناقصة وفالت)

Combine pallet fields + `includeLooseBalances`:

```json
{
  "incompletePalletProductTypeId": 5,
  "incompletePalletQuantity": 25,
  "incompletePalletScannedValue": "000100000001",
  "includeLooseBalances": true,
  "notes": "ملاحظات اختيارية"
}
```

### Step 5 — Handover creation result

**Response:**
```json
{
  "success": true,
  "data": {
    "id": 500,
    "lineId": 1,
    "lineName": "خط 1",
    "status": "PENDING",
    "statusDisplayNameAr": "قيد الانتظار",
    "handoverType": "BOTH",
    "outgoingOperatorName": "أحمد",
    "outgoingOperatorId": 10,
    "incompletePallet": {
      "productTypeId": 5,
      "productTypeName": "أحمر 20 كغ",
      "quantity": 25,
      "scannedValue": "000100000001"
    },
    "looseBalances": [
      { "productTypeId": 5, "productTypeName": "أحمر 20 كغ", "loosePackageCount": 7 },
      { "productTypeId": 6, "productTypeName": "أزرق 25 كغ", "loosePackageCount": 3 }
    ],
    "looseBalanceCount": 2,
    "notes": "ملاحظات اختيارية",
    "createdAt": "2025-01-15T12:30:00Z",
    "createdAtDisplay": "الأربعاء ١٥ يناير ٢٠٢٥ ٠٢:٣٠ م"
  }
}
```

**After success:**
- Outgoing operator authorization is **ended** (released)
- Line enters `PENDING_HANDOVER_NEEDS_INCOMING` mode
- Production is **blocked** on this line
- Show "في انتظار المشغل القادم" screen with the handover summary card
- The incoming operator must authorize via PIN first

---

## Incoming Operator Flow

### Step 6 — Incoming operator sees PIN overlay

When `lineUiMode == "PENDING_HANDOVER_NEEDS_INCOMING"`:
- Show the pending handover summary card (from `pendingHandover` in line state)
- Show PIN entry field for the incoming operator
- Do NOT show confirm/reject buttons yet

### Step 7 — Incoming operator enters PIN

```
POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin
Content-Type: application/json

{ "pin": "1234" }
```

After successful authorization:
- Re-fetch line state: `GET /lines/{lineId}/state`
- `lineUiMode` becomes `PENDING_HANDOVER_REVIEW`
- `canConfirmHandover: true` and `canRejectHandover: true`
- Now show the handover detail card with confirm/reject buttons

### Step 8a — Incoming confirms (تأكيد الاستلام)

Only shown when `canConfirmHandover: true`.

```
POST /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}/confirm
```

No request body needed.

**Response:** `LineHandoverResponse` with `status: "CONFIRMED"`.

**After success:**
- Loose balances are **transferred** to the incoming operator's session
- Line mode becomes `AUTHORIZED` — normal production resumes
- Re-fetch line state to update the UI

### Step 8b — Incoming rejects (رفض التسليم)

Only shown when `canRejectHandover: true`.

Show a dialog asking for optional rejection reason:
> **سبب الرفض (اختياري):**

```
POST /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}/reject
Content-Type: application/json

{
  "notes": "الأعداد غير صحيحة - يوجد 5 فالت وليس 3"
}
```

Body is optional. If omitted or `{}`, rejection proceeds without notes.

**Response:** `LineHandoverResponse` with `status: "REJECTED"`.

**After success:**
- **NO items are transferred** to the incoming operator
- Handover is escalated as a dispute for admin review
- Line becomes unblocked — incoming operator can start fresh production
- Show message: **"تم رفض التسليم وسيتم مراجعته من قبل الإدارة"**
- Re-fetch line state → `lineUiMode` becomes `AUTHORIZED`

---

## Get Pending Handover Full Details

For the review screen, fetch full details:

```
GET /api/v1/palletizing-line/lines/{lineId}/handover/pending
```

**Response:** Full `LineHandoverResponse` (or `null` data if no pending handover).

---

## Handover Response Fields Reference

| Field | Type | Description |
|-------|------|-------------|
| `id` | Long | Handover ID |
| `lineId` | Long | Production line ID |
| `lineName` | String | Production line name |
| `status` | String | `PENDING`, `CONFIRMED`, `REJECTED`, `RESOLVED` |
| `statusDisplayNameAr` | String | Arabic status name |
| `handoverType` | String | `NONE`, `INCOMPLETE_PALLET_ONLY`, `LOOSE_BALANCES_ONLY`, `BOTH` |
| `outgoingOperatorName` | String | Outgoing operator name snapshot |
| `outgoingOperatorId` | Long | Outgoing operator ID |
| `incomingOperatorName` | String | Incoming operator name (null if pending) |
| `incomingOperatorId` | Long | Incoming operator ID (null if pending) |
| `incompletePallet` | Object | `{ productTypeId, productTypeName, quantity, scannedValue }` or null |
| `looseBalances` | Array | `[{ productTypeId, productTypeName, loosePackageCount }]` |
| `looseBalanceCount` | int | Number of loose balance entries |
| `notes` | String | Outgoing operator's notes |
| `rejectionNotes` | String | Incoming operator's rejection reason |
| `resolutionNotes` | String | Admin's resolution notes |
| `resolvedByUserName` | String | Admin who resolved |
| `createdAt` / `createdAtDisplay` | ISO-8601 / String | Creation timestamp |
| `confirmedAt` / `confirmedAtDisplay` | ISO-8601 / String | Confirmation timestamp |
| `rejectedAt` / `rejectedAtDisplay` | ISO-8601 / String | Rejection timestamp |
| `resolvedAt` / `resolvedAtDisplay` | ISO-8601 / String | Resolution timestamp |

**Note:** `@JsonInclude(NON_NULL)` — null fields are omitted from JSON.

---

## Error Codes

| Code | HTTP | Meaning |
|------|------|---------|
| `PENDING_LINE_HANDOVER_EXISTS` | 409 | A pending handover already exists for this line |
| `LINE_HANDOVER_NOT_FOUND` | 404 | Handover ID not found |
| `LINE_HANDOVER_ALREADY_RESOLVED` | 409 | Handover already confirmed or rejected |
| `LINE_NOT_AUTHORIZED` | 403 | No active operator on this line (PIN auth required first) |
| `LINE_BLOCKED_BY_PENDING_HANDOVER` | 409 | Production blocked by pending handover |
| `VALIDATION_ERROR` | 400 | Incomplete pallet fields inconsistent (e.g., quantity without product type) |
| `PALLET_LINE_MISMATCH` | 400 | Handover does not belong to this line |

---

## Arabic UI Text Reference

| Context | Arabic Text |
|---------|-------------|
| Initiate handover button | تسليم مناوبة |
| First dialog question 1 | هل يوجد مشاتيح ناقصة؟ |
| First dialog question 2 | هل يوجد فالت؟ |
| Case: incomplete pallet only | مشاتيح ناقصة فقط |
| Case: loose balances only | فالت فقط |
| Case: both | مشاتيح ناقصة وفالت |
| Product type label | نوع المنتج |
| Quantity label | الكمية |
| Scanned value label | قيمة المسح |
| Pending state label | قيد الانتظار |
| Confirmed state label | مؤكد |
| Rejected state label | مرفوض |
| Resolved state label | تم الحل |
| Waiting for incoming | في انتظار المشغل القادم |
| Confirm button | تأكيد الاستلام |
| Reject button | رفض التسليم |
| Reject reason prompt | سبب الرفض (اختياري) |
| After rejection message | تم رفض التسليم وسيتم مراجعته من قبل الإدارة |
| Loose balances header | أرصدة المواد الفرطة |
| Incomplete pallet header | مشتاح ناقص |
| Notes label | ملاحظات |

---

## What Must NOT Exist in the UI

1. **No visible "تغيير المشغل" / "change operator" button** as a primary action on the main line card
2. **No confirm/reject buttons** before the incoming operator has authorized via PIN
3. **No transfer of items on reject** — the UI must clearly show rejection = dispute
4. **No processing of handover before incoming authorization**
5. **No ambiguity between incomplete pallet and loose balances** — they are separate sections
