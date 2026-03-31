# Shift Handover: Global Flow Changes for Takween Al-Mashtah App

## 1. What changed and why

### Old behavior (INCORRECT)

The shift handover was scoped **per production line**:

- The backend stored `production_line_id` on the handover itself.
- The app had to call `GET /api/v1/shift-handover/pending?lineId=<id>` for each line.
- Two separate PENDING handovers could exist simultaneously (one per line).
- There was no limit on the number of items in a handover.
- Error messages referenced "for production line: X".

### Why it was wrong

The Takween Al-Mashtah app operates **both production lines** within a single workflow. A shift handover is a single event when the outgoing operator hands over all incomplete pallets (from any line) to the incoming shift. Having per-line handovers meant the blocking dialog could miss a line, multiple pending handovers could accumulate, and the app flow was fragmented.

### New behavior (CORRECT)

- **One single global PENDING handover** for the entire Takween Al-Mashtah workflow.
- The handover itself has no production line association. Instead, each **item** in the handover specifies which production line it belongs to.
- At most **2 items** per handover (max 1 per production line).
- The app calls a **parameter-less** `GET /api/v1/shift-handover/pending` to detect the blocking handover after login.
- The backend enforces uniqueness at the DB level (only one PENDING row can exist globally).

---

## 2. Handover structure

A handover may contain:

| Scenario | Items |
|---|---|
| Line 1 only | 1 item with `productionLineId` for line 1 |
| Line 2 only | 1 item with `productionLineId` for line 2 |
| Both lines | 2 items: one for line 1, one for line 2 |

Maximum total items: **2**. Each production line may appear **at most once**.

---

## 3. Changed/new DTO fields

### CreateHandoverRequest (POST body)

**Removed**: `productionLineId` (was at handover level)

**Current shape**:
```json
{
  "operatorId": 1,
  "items": [
    {
      "productionLineId": 1,
      "productTypeId": 5,
      "quantity": 120,
      "scannedValue": "000500000042",
      "notes": "incomplete pallet from line 1"
    },
    {
      "productionLineId": 2,
      "productTypeId": 3,
      "quantity": 80,
      "scannedValue": null,
      "notes": null
    }
  ]
}
```

Each item now includes `productionLineId` (required).

### HandoverItemResponse (in all responses)

**Added fields**:
- `productionLineId` (Long)
- `productionLineName` (String)

Example:
```json
{
  "id": 1,
  "productionLineId": 1,
  "productionLineName": "خط الإنتاج 1",
  "productTypeId": 5,
  "productTypeName": "لنش بوكس - أبيض",
  "quantity": 120,
  "scannedValue": "000500000042",
  "notes": "incomplete pallet from line 1"
}
```

### PendingHandoverResponse

**Removed**: `productionLineId`, `productionLineName` (now per-item)

### HandoverResponse

**Removed**: `productionLineId`, `productionLineName` (now per-item)

---

## 4. Changed endpoints

### `GET /api/v1/shift-handover/pending`

**Before**: Required `?lineId=<id>` query parameter.

**After**: No parameters. Returns the single global pending handover or `null` data.

**Response when pending handover exists**:
```json
{
  "success": true,
  "data": {
    "id": 42,
    "outgoingOperatorId": 1,
    "outgoingOperatorName": "أحمد محمد",
    "outgoingShiftType": "MORNING",
    "outgoingShiftDisplayNameAr": "صباحي",
    "status": "PENDING",
    "items": [
      {
        "id": 101,
        "productionLineId": 1,
        "productionLineName": "خط الإنتاج 1",
        "productTypeId": 5,
        "productTypeName": "لنش بوكس - أبيض",
        "quantity": 120,
        "scannedValue": "000500000042",
        "notes": null
      }
    ],
    "itemCount": 1,
    "totalQuantity": 120,
    "createdAt": "2026-03-30T14:00:00.000+03:00",
    "createdAtDisplay": "٣٠ مارس ٢٠٢٦ ٢:٠٠ م",
    "blocking": true,
    "availableActions": ["CONFIRM", "DISPUTE"],
    "message": "يوجد تسليم مشتاح معلق من الوردية السابقة. يجب تأكيد أو رفض التسليم قبل المتابعة."
  }
}
```

**Response when no pending handover exists**:
```json
{
  "success": true,
  "data": null
}
```

### `POST /api/v1/shift-handover` (create)

Request body no longer includes top-level `productionLineId`. Each item includes its own `productionLineId`.

**Success**: HTTP 201 with `HandoverResponse`.

**Error: pending already exists**: HTTP 409
```json
{
  "success": false,
  "error": {
    "code": "PENDING_HANDOVER_EXISTS",
    "message": "A pending handover already exists"
  }
}
```

**Error: duplicate line**: HTTP 400
```json
{
  "success": false,
  "error": {
    "code": "HANDOVER_DUPLICATE_LINE",
    "message": "Duplicate production line in handover items: 1"
  }
}
```

**Error: too many items (>2)**: HTTP 400 (Jakarta validation)
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "A handover may contain at most 2 items (one per production line)"
  }
}
```

### `POST /api/v1/shift-handover/{id}/confirm`

No changes. Request body:
```json
{
  "incomingOperatorId": 2
}
```

Response: `HandoverResponse` with `status: "CONFIRMED"`.

### `POST /api/v1/shift-handover/{id}/reject`

No changes. Request body:
```json
{
  "incomingOperatorId": 2
}
```

Response: `HandoverResponse` with `status: "DISPUTED"`.

### `GET /api/v1/shift-handover/pending-list`

Still available for backward compatibility. Returns a list (at most 1 item under the global constraint).

---

## 5. Blocking handover flow (app-side)

### After login / app startup

1. Call `GET /api/v1/shift-handover/pending`.
2. If `data` is `null` -> no blocking handover. Proceed to normal workflow.
3. If `data` is not null and `blocking == true` -> show blocking dialog. **Do not allow the user to continue normal workflow.**

### Blocking dialog content

Display:
- Outgoing operator name and shift type
- For each item: production line name, product type name, quantity, scanned value (if present), notes (if present)
- Two action buttons: **Confirm** and **Dispute**

### On Confirm

- Call `POST /api/v1/shift-handover/{id}/confirm` with `{ "incomingOperatorId": <current operator ID> }`.
- On success: dismiss dialog, proceed to normal workflow.
- On error (409 HANDOVER_ALREADY_RESOLVED): dismiss dialog, proceed (another session already handled it).

### On Dispute

- Call `POST /api/v1/shift-handover/{id}/reject` with `{ "incomingOperatorId": <current operator ID> }`.
- On success: dismiss dialog, proceed to normal workflow. The admin will review later.
- On error (409 HANDOVER_ALREADY_RESOLVED): dismiss dialog, proceed.

---

## 6. Creating a handover (end of shift)

### Validation rules the app should enforce locally (UI)

- At least 1 item, at most 2 items.
- Each item must have a production line selected.
- No two items may have the same production line.
- Each item must have a product type and quantity >= 1.

### Backend validation

The backend will reject:
- Empty items list
- More than 2 items (HTTP 400, `VALIDATION_ERROR`)
- Duplicate `productionLineId` across items (HTTP 400, `HANDOVER_DUPLICATE_LINE`)
- Missing or invalid `productionLineId`, `productTypeId`, `quantity` (HTTP 400, `VALIDATION_ERROR`)
- A second PENDING handover when one already exists (HTTP 409, `PENDING_HANDOVER_EXISTS`)

---

## 7. Handover lifecycle

```
PENDING ──> CONFIRMED   (incoming shift confirms)
PENDING ──> DISPUTED    (incoming shift disputes)
DISPUTED ──> RESOLVED   (admin resolves via web portal)
```

Once a handover is CONFIRMED or DISPUTED, it is no longer PENDING and will not be returned by `GET /pending`.

---

## 8. Edge cases

| Case | Expected behavior |
|---|---|
| App calls `GET /pending` and another session just confirmed it | `data: null` - proceed normally |
| Two sessions try to confirm simultaneously | First succeeds, second gets 409 `HANDOVER_ALREADY_RESOLVED` - dismiss and proceed |
| User tries to create handover while one is pending | 409 `PENDING_HANDOVER_EXISTS` - show error |
| User submits 3+ items | 400 validation error - show error |
| User submits two items both for line 1 | 400 `HANDOVER_DUPLICATE_LINE` - show error |
| Network error on confirm/reject | Show retry option, do not dismiss blocking dialog |

---

## 9. Compatibility / migration notes

- The `GET /pending?lineId=X` endpoint **no longer accepts the lineId parameter**. Calls with `?lineId=X` will be ignored (the parameter is simply not read). However, the app should remove the `lineId` parameter from the call.
- The `GET /pending-list` endpoint still works and returns a list (0 or 1 items).
- Response DTOs no longer include top-level `productionLineId` / `productionLineName`. If the app reads these, it must be updated to read them from each item instead.
- `CreateHandoverRequest` no longer accepts top-level `productionLineId`. It must be removed from the request body. Each item's `productionLineId` is now required.

---

## 10. Recommended app-side test scenarios

1. **No pending handover**: Call `GET /pending`, receive `data: null`, verify no blocking dialog is shown.
2. **Pending handover with 1 item (line 1)**: Verify blocking dialog shows 1 item with line 1 info.
3. **Pending handover with 2 items (line 1 + line 2)**: Verify blocking dialog shows both items with correct line info.
4. **Confirm handover**: Tap confirm, verify `POST /{id}/confirm` is called, dialog dismissed, normal flow resumes.
5. **Dispute handover**: Tap dispute, verify `POST /{id}/reject` is called, dialog dismissed, normal flow resumes.
6. **Create handover with 1 item**: Submit, verify success.
7. **Create handover with 2 items (different lines)**: Submit, verify success.
8. **Create handover with duplicate line**: Submit, verify error is shown.
9. **Create handover with 3 items**: Verify validation prevents submission (local + backend).
10. **Concurrent resolution**: Confirm a handover that was already confirmed by another session, verify 409 is handled gracefully.
11. **Network error**: Simulate network failure on confirm/reject, verify blocking dialog stays and retry is possible.

---

## Instructions for Frontend App AI Agent

You are updating the **Takween Al-Mashtah** (تكوين المشاتيح) Flutter app to work with the refactored global shift handover backend.

### What you must update

#### 1. API client / repository layer

- **Remove** the `lineId` query parameter from the `GET /api/v1/shift-handover/pending` call. The endpoint is now parameter-less.
- **Update** `CreateHandoverRequest` model: remove the top-level `productionLineId` field. Keep `operatorId` and `items`.
- **Update** `HandoverItemRequest` model: add `productionLineId` (required Long/int).
- **Update** `HandoverItemResponse` model: add `productionLineId` (Long) and `productionLineName` (String).
- **Update** `PendingHandoverResponse` model: remove `productionLineId` and `productionLineName` fields.
- **Update** `HandoverResponse` model: remove `productionLineId` and `productionLineName` fields.
- Add handling for new error codes: `HANDOVER_DUPLICATE_LINE`, `HANDOVER_TOO_MANY_ITEMS`.

#### 2. Blocking handover check (after login / app init)

- After successful login and operator selection, call `GET /api/v1/shift-handover/pending` (no parameters).
- If `data != null` and `blocking == true`:
  - Show a **full-screen blocking dialog** that cannot be dismissed.
  - Display the outgoing operator name, shift type, and each item's production line name, product type name, quantity, and notes.
  - Show two buttons: "تأكيد" (Confirm) and "رفض" (Dispute).
- If `data == null`: proceed to normal workflow.

#### 3. Blocking dialog actions

- **Confirm**: Call `POST /api/v1/shift-handover/{id}/confirm` with `{ "incomingOperatorId": <current operator ID> }`.
  - On success (200): dismiss dialog, proceed to normal workflow.
  - On 409 (already resolved): dismiss dialog, proceed.
  - On network error: show error toast, keep dialog open, allow retry.

- **Dispute**: Call `POST /api/v1/shift-handover/{id}/reject` with `{ "incomingOperatorId": <current operator ID> }`.
  - On success (200): dismiss dialog, proceed to normal workflow.
  - On 409 (already resolved): dismiss dialog, proceed.
  - On network error: show error toast, keep dialog open, allow retry.

#### 4. Create handover screen (end of shift)

- Remove the handover-level production line selector (if it exists).
- Each item in the items list must have its own production line dropdown/selector.
- Enforce in the UI:
  - At least 1 item, at most 2 items.
  - No two items may select the same production line.
  - When 1 item exists, the "add item" button is visible. When 2 items exist, hide it.
  - Each item requires: production line, product type, quantity (>= 1).
- On submit, build the request as:
  ```json
  {
    "operatorId": <selected operator>,
    "items": [
      { "productionLineId": 1, "productTypeId": 5, "quantity": 120 },
      { "productionLineId": 2, "productTypeId": 3, "quantity": 80 }
    ]
  }
  ```
- Handle errors:
  - 409 `PENDING_HANDOVER_EXISTS`: show "يوجد تسليم معلق بالفعل" message.
  - 400 `HANDOVER_DUPLICATE_LINE`: show "لا يمكن إضافة أكثر من عنصر لنفس خط الإنتاج".
  - 400 validation errors: show field-level errors.

#### 5. State management / ViewModel

- Update the handover state/ViewModel to remove line-level pending checks.
- The pending handover state is now a single nullable object, not a per-line map.
- After confirming or disputing, clear the pending handover state and allow normal workflow.

#### 6. Preserve existing architecture

- Follow the existing app's architecture patterns (Clean Architecture / BLoC / Provider / Riverpod - whatever is currently used).
- Do not introduce new state management libraries or architectural changes.
- Keep Arabic UI strings consistent with the existing app style.
- Keep error handling consistent with the existing patterns.

#### 7. Loading / error / success states

- Show a loading indicator while fetching the pending handover.
- Show a loading indicator on the confirm/dispute buttons while the action is in progress.
- Disable both buttons while an action is in progress to prevent double submission.
- Show success feedback (toast/snackbar) after successful confirm or dispute.
- Show error feedback with retry option on network failure.

#### 8. What should happen after confirm/reject

- The blocking dialog is dismissed.
- The app proceeds to the normal palletizing workflow.
- No additional API call to re-check pending is needed (the action response already confirms the status change).

#### 9. Manual test scenarios to verify

1. Login with no pending handover -> no blocking dialog, normal flow.
2. Login with pending handover (1 item, line 1) -> blocking dialog with 1 item showing line 1.
3. Login with pending handover (2 items, line 1 + 2) -> blocking dialog with 2 items.
4. Tap confirm -> dialog dismissed, normal flow resumes.
5. Tap dispute -> dialog dismissed, normal flow resumes.
6. Create handover with 1 item -> success.
7. Create handover with 2 items (different lines) -> success.
8. Try to add a third item -> UI prevents it.
9. Try to select same line for 2 items -> UI prevents or backend rejects.
10. Create handover while one is pending -> error shown.
11. Kill app during blocking dialog, reopen -> blocking dialog reappears.
12. Two devices confirm simultaneously -> first succeeds, second gets 409 and proceeds.
