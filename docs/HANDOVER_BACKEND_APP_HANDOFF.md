# Shift Handover Backend Fix — App Handoff Document

**Date:** 2026-03-31
**Target app:** تكوين المشاتيح (Palletizing App)
**Backend version:** Post-fix (see changes below)

---

## Root Cause

The backend only exposed `GET /api/v1/shift-handover/pending?lineId=X`, which **requires** the caller to already know which production line has a pending handover. When the incoming shift user logged in, the app had no way to discover pending handovers across all production lines — so nothing appeared.

The handover **creation** (`POST /api/v1/shift-handover`) was working correctly. The data was persisted with `PENDING` status. The bug was entirely on the **retrieval** side: there was no endpoint to list all pending handovers without specifying a line ID.

---

## What Changed on the Backend

### New Endpoint: `GET /api/v1/shift-handover/pending-list`

Returns **all** pending handovers across all production lines. Returns an empty list (`[]`) when no pending handovers exist — never `null`.

**Authentication:** Bearer JWT with `PALLETIZER` role (same security rules as all `/api/v1/shift-handover/**` endpoints).

**Request:**
```
GET /api/v1/shift-handover/pending-list
Authorization: Bearer <token>
```

**Response (200 OK) — with pending handovers:**
```json
{
  "success": true,
  "data": [
    {
      "id": 42,
      "productionLineId": 1,
      "productionLineName": "خط الإنتاج 1",
      "outgoingOperatorId": 5,
      "outgoingOperatorName": "أحمد محمد",
      "outgoingShiftType": "MORNING",
      "outgoingShiftDisplayNameAr": "صباحي",
      "status": "PENDING",
      "items": [
        {
          "id": 101,
          "productTypeId": 3,
          "productTypeName": "لنش بوكس أبيض",
          "quantity": 50,
          "scannedValue": "003200000045",
          "notes": null
        }
      ],
      "itemCount": 1,
      "totalQuantity": 50,
      "createdAt": "2026-03-31T10:00:00.000Z",
      "createdAtDisplay": "الثلاثاء 31/03 01:00 م"
    }
  ]
}
```

**Response (200 OK) — no pending handovers:**
```json
{
  "success": true,
  "data": []
}
```

### Existing Endpoints (unchanged)

| Endpoint | Purpose | Change |
|---|---|---|
| `POST /api/v1/shift-handover` | Create pending handover | No change |
| `GET /api/v1/shift-handover/pending?lineId=X` | Check pending for one line | No change |
| `POST /api/v1/shift-handover/{id}/confirm` | Confirm handover | No change |
| `POST /api/v1/shift-handover/{id}/reject` | Reject handover (dispute) | No change |
| `GET /api/v1/shift-handover/{id}` | Get handover details | No change |

---

## Old vs New Response Behavior

| Scenario | Old behavior | New behavior |
|---|---|---|
| Incoming shift checks for pending handovers | No endpoint to discover all pending handovers. Must call `/pending?lineId=X` per line. | Call `/pending-list` once to get all pending handovers. |
| No pending handovers exist | `/pending?lineId=X` returns `{"success": true}` (no `data` field due to `@JsonInclude(NON_NULL)`) | `/pending-list` returns `{"success": true, "data": []}` (always has `data` field with empty list) |
| Multiple lines with pending handovers | Would require N separate calls (one per line) | Single call returns all of them |

---

## DTO Shape: `PendingHandoverResponse`

This is the same DTO used by both `/pending` and `/pending-list`. No new fields were added.

```
PendingHandoverResponse:
  id: Long
  productionLineId: Long
  productionLineName: String
  outgoingOperatorId: Long
  outgoingOperatorName: String
  outgoingShiftType: "MORNING" | "EVENING" | "NIGHT"
  outgoingShiftDisplayNameAr: String
  status: "PENDING"
  items: List<HandoverItemResponse>
  itemCount: int
  totalQuantity: int
  createdAt: ISO-8601 Instant
  createdAtDisplay: String (Arabic formatted)

HandoverItemResponse:
  id: Long
  productTypeId: Long
  productTypeName: String
  quantity: int
  scannedValue: String (nullable, 12-digit)
  notes: String (nullable)
```

---

## App Flow — Required Changes

### After Login (New)

Immediately after login (or after the app initializes with the JWT), call:

```
GET /api/v1/shift-handover/pending-list
```

- If `data` is an empty list → proceed to normal palletizing flow.
- If `data` has one or more items → show the handover dialog to the user.

### Handover Dialog Flow

For each pending handover in the list:

1. Display the handover info:
   - Production line name (`productionLineName`)
   - Outgoing operator name (`outgoingOperatorName`)
   - Outgoing shift name (`outgoingShiftDisplayNameAr`)
   - List of incomplete pallets (from `items`), showing product type name and quantity for each
   - Total items (`itemCount`) and total quantity (`totalQuantity`)

2. User chooses **Confirm** or **Reject**:
   - **Confirm:** `POST /api/v1/shift-handover/{id}/confirm` with body:
     ```json
     { "incomingOperatorId": <selected-operator-id> }
     ```
   - **Reject:** `POST /api/v1/shift-handover/{id}/reject` with body:
     ```json
     { "incomingOperatorId": <selected-operator-id> }
     ```

3. After confirming/rejecting, the handover is no longer PENDING and won't appear in subsequent `/pending-list` calls.

### When Selecting a Production Line (Optional)

The existing per-line endpoint still works for in-flow checks:

```
GET /api/v1/shift-handover/pending?lineId=X
```

Note: when no pending handover exists for that line, the response is `{"success": true}` with no `data` field (null omitted). The app should treat a missing `data` field the same as `data: null`.

---

## Edge Cases the App Should Handle

1. **Multiple pending handovers** — The list can contain more than one handover (different production lines). Process each one.

2. **Handover already resolved** — If the user takes too long and another user confirms/rejects the handover, calling `/confirm` or `/reject` will return a `409 Conflict` error with code `HANDOVER_ALREADY_RESOLVED`. The app should handle this gracefully (e.g., refresh the pending list).

3. **Empty list after login** — This is the normal case when there are no pending handovers. Don't show any handover dialog.

4. **Network retry** — The `/pending-list` endpoint is safe to retry (GET, read-only). If the first call fails, retry before proceeding.

5. **Operator selection** — Both confirm and reject require `incomingOperatorId`. The app must select an operator before calling confirm/reject. Use `GET /api/v1/palletizing/operators` to get the list.

---

## Testing Notes

- **Create handover with account A** (outgoing shift) → logout → **login with account B** (incoming shift) → call `/pending-list` → should see the handover.
- **Create handovers on multiple lines** → `/pending-list` returns all of them.
- **Create handover, then confirm it** → subsequent `/pending-list` returns empty.
- **Create handover, then reject it** → subsequent `/pending-list` returns empty (it becomes DISPUTED).
- **No handovers created** → `/pending-list` returns `{"success": true, "data": []}`.

---

## Summary of Backend Files Changed

| File | Change |
|---|---|
| `ShiftHandoverRepository.java` | Added `findByStatusOrderByCreatedAtDesc(HandoverStatus)` with `@EntityGraph` |
| `ShiftHandoverService.java` | Added `getAllPendingHandovers()` method |
| `ShiftHandoverController.java` | Added `GET /pending-list` endpoint |
| `ShiftHandoverServiceTest.java` | Added 7 new unit tests for the new method and for `getPendingHandoverForLine` |
