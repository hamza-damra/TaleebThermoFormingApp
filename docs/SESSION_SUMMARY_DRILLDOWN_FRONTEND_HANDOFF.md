# Session Summary Drill-Down & Reprint — Frontend Handoff

## 1. Executive Summary

The factory wants the session summary table on the palletizing app's main line screen to become interactive. Tapping a product row opens a detailed drill-down showing all pallets produced for that product type in the current operator session, with the ability to reprint any pallet label.

**Backend changes were needed and have been implemented.** A new dedicated endpoint returns session pallets grouped by product type with an explicit `serialNumber` field (pallet number without prefix) so the frontend does not need to parse scanned values.

Reprint uses the **existing** print-attempts endpoint — no new reprint endpoint was needed.

---

## 2. New Endpoint — Session Production Detail

### Request

```
GET /api/v1/palletizing-line/lines/{lineId}/session-production-detail
```

**Headers:** `X-Device-Key: <device-api-key>` (same auth as all palletizing endpoints)

**Path parameter:** `lineId` — the production line ID

### Response

```json
{
  "success": true,
  "data": {
    "lineId": 1,
    "authorizationId": 100,
    "groups": [
      {
        "productTypeId": 5,
        "productTypeName": "Red 20kg (100 كرتونة)",
        "productTypePrefix": "0001",
        "completedPalletCount": 3,
        "pallets": [
          {
            "palletId": 42,
            "scannedValue": "000100000042",
            "serialNumber": "00000042",
            "quantity": 100,
            "sourceType": "PRODUCTION_LINE",
            "createdAt": "2026-04-06T08:30:00.000+03:00",
            "createdAtDisplay": "2026-04-06، 08:30 صباحًا"
          },
          {
            "palletId": 38,
            "scannedValue": "000100000038",
            "serialNumber": "00000038",
            "quantity": 100,
            "sourceType": "PRODUCTION_LINE",
            "createdAt": "2026-04-06T08:15:00.000+03:00",
            "createdAtDisplay": "2026-04-06، 08:15 صباحًا"
          },
          {
            "palletId": 35,
            "scannedValue": "000100000035",
            "serialNumber": "00000035",
            "quantity": 95,
            "sourceType": "PRODUCTION_LINE",
            "createdAt": "2026-04-06T08:00:00.000+03:00",
            "createdAtDisplay": "2026-04-06، 08:00 صباحًا"
          }
        ]
      },
      {
        "productTypeId": 6,
        "productTypeName": "Blue 15kg (50 كرتونة)",
        "productTypePrefix": "0002",
        "completedPalletCount": 1,
        "pallets": [
          {
            "palletId": 40,
            "scannedValue": "000200000015",
            "serialNumber": "00000015",
            "quantity": 50,
            "sourceType": "PRODUCTION_LINE",
            "createdAt": "2026-04-06T08:20:00.000+03:00",
            "createdAtDisplay": "2026-04-06، 08:20 صباحًا"
          }
        ]
      }
    ]
  },
  "error": null
}
```

### Response Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `lineId` | Long | Production line ID |
| `authorizationId` | Long | Current active operator authorization session ID |
| `groups` | Array | Product type groups, ordered by most-recent-pallet-first |
| `groups[].productTypeId` | Long | Product type ID |
| `groups[].productTypeName` | String | Product type display name (snapshot from creation time) |
| `groups[].productTypePrefix` | String | 4-digit prefix (e.g. `"0001"`) |
| `groups[].completedPalletCount` | int | Number of pallets in this group |
| `groups[].pallets` | Array | Individual pallets, **newest first** |
| `pallets[].palletId` | Long | Pallet database ID — use this for reprint calls |
| `pallets[].scannedValue` | String | Full 12-digit scanned/printed value (e.g. `"000100000042"`) — needed for label printing |
| `pallets[].serialNumber` | String | 8-digit serial WITHOUT prefix (e.g. `"00000042"`) — **use this for display in the drill-down list** |
| `pallets[].quantity` | Integer | Actual package/carton count in this pallet |
| `pallets[].sourceType` | String | `"PRODUCTION_LINE"` or `"WAREHOUSE_IMPORT"` or `"UNKNOWN"` |
| `pallets[].createdAt` | ISO-8601 | UTC timestamp with Asia/Hebron offset |
| `pallets[].createdAtDisplay` | String | Arabic-formatted display string (e.g. `"2026-04-06، 08:30 صباحًا"`) |

---

## 3. Reprint — Using Existing Endpoint

Reprint uses the **already existing** print-attempts endpoint. No new endpoint was added.

### Request

```
POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts
```

**Headers:** `X-Device-Key: <device-api-key>`

**Body:**
```json
{
  "status": "SUCCESS",
  "printerIdentifier": "PRINTER-01"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | String enum | **Yes** | `SUCCESS`, `FAILED`, or `PENDING` |
| `printerIdentifier` | String | No | Optional printer name/ID for audit |
| `failureReason` | String | No | Optional failure reason if status is `FAILED` |

### Response

```json
{
  "success": true,
  "data": {
    "id": 15,
    "palleteId": 42,
    "attemptNumber": 2,
    "status": "SUCCESS",
    "createdAt": "2026-04-06T09:00:00.000+03:00"
  }
}
```

**Key points:**
- The `palletId` in the URL comes from `pallets[].palletId` in the drill-down response
- The endpoint supports unlimited print attempts per pallet — each attempt increments `attemptNumber`
- The endpoint validates that the pallet belongs to the specified line
- The endpoint requires an active authorization on the line (same session guard as pallet creation)
- For the actual label content, use `scannedValue` from the drill-down response (the full 12-digit value that gets encoded in the barcode/QR)

---

## 4. Session Scoping Rules

**"Current session" = the active `LineOperatorAuthorization` for the line.**

- When an operator enters their PIN on a line, a new `LineOperatorAuthorization` is created with status `ACTIVE`
- All pallets created during that authorization are linked to it via `line_authorization_id`
- When the operator releases the line or a handover completes, the authorization is deactivated
- The drill-down endpoint **only returns pallets from the current ACTIVE authorization** — no historical sessions leak through
- If no active authorization exists, the endpoint returns HTTP 403 with error code `LINE_NOT_AUTHORIZED`

**Frontend must only call this endpoint when the line is authorized** (i.e., `lineUiMode` is `AUTHORIZED` or `PENDING_HANDOVER_REVIEW`).

---

## 5. Sorting & Grouping

- **Groups** are ordered by the most recently created pallet in each group (the product type that had the newest pallet appears first)
- **Pallets within each group** are ordered **newest first** (`createdAt DESC`)
- This means the most recently produced pallet across all types will be the first item in the first group

---

## 6. Frontend UI Implementation Notes

### Trigger
- When the operator taps the session summary table (or a specific product row), open a large popup / overlay / full-screen dialog
- Call `GET /lines/{lineId}/session-production-detail` to load the data

### Drill-Down Layout
- Show product type groups as expandable sections or tabs
- Each product type header shows: **product type name** + **pallet count** (`completedPalletCount`)
- Under each group, show a list of pallets with:
  - **Display the `serialNumber` field** (e.g. `00000042`) — NOT the full `scannedValue` — because the product prefix is already known from the group header
  - Show `quantity` (e.g. "100 كرتونة")
  - Show `createdAtDisplay` (e.g. "2026-04-06، 08:30 صباحًا")
  - Show a **reprint button** (🖨️ or "إعادة طباعة")

### Reprint Flow
1. Operator taps reprint button on a pallet row
2. App sends the label to the printer using `scannedValue` as the barcode/QR content
3. App calls `POST /lines/{lineId}/pallets/{palletId}/print-attempts` with the result status
4. Show success/failure feedback to the operator

### Loading State
- Show a spinner/skeleton while the drill-down data loads
- The response is lightweight (only current session pallets) so it should be fast

### Empty State
- If `groups` is empty, show a message like "لا توجد طبليات في هذه المناوبة" (No pallets in this session)
- This can happen if the operator just authorized and hasn't produced anything yet

### Error States
- **403 / `LINE_NOT_AUTHORIZED`**: Line has no active authorization — dismiss the dialog and show the PIN screen
- **Network error**: Show retry option
- **404 / `PRODUCTION_LINE_NOT_FOUND`**: Should not happen in normal flow — show generic error

### Refresh Behavior
- The drill-down is loaded **on-demand** when the operator opens it — no need for SSE/live updates inside the popup
- When the operator closes the popup and reopens it, fetch fresh data
- The existing session summary table on the main screen already updates via SSE (`line-state-changed` events) — the drill-down is a separate on-demand view

---

## 7. Backward Compatibility

- **No breaking changes** to existing endpoints
- The existing `GET /lines/{lineId}/session-table` endpoint continues to work as before (aggregated counts)
- The existing `GET /lines/{lineId}/state` endpoint is unchanged
- The new endpoint is purely additive

---

## 8. Backend Files Changed

| File | Change |
|------|--------|
| `palletizing/dto/SessionPalletDetail.java` | **New** — Individual pallet detail DTO |
| `palletizing/dto/SessionProductionDetailResponse.java` | **New** — Grouped response DTO with `ProductTypeGroup` inner class |
| `domain/repository/PalleteRepository.java` | Added `findByLineAuthorizationIdOrderByCreatedAtDesc()` query |
| `palletizing/LineSessionTableService.java` | Added `getSessionProductionDetail(lineId)` method + `toSessionPalletDetail()` helper; added `LineAuthorizationService`, `ArabicDateTimeFormatter`, `ScannedValueParser` dependencies |
| `palletizing/PalletizingLineController.java` | Added `GET /lines/{lineId}/session-production-detail` endpoint; added `LineSessionTableService` dependency |
| `test/.../SessionProductionDetailServiceTest.java` | **New** — 7 unit tests covering grouping, ordering, serial extraction, empty states, authorization check, snapshot usage |

---

## 9. No Migration Needed

No database schema changes were made. The new endpoint queries existing tables (`palletes`, `line_operator_authorizations`) using existing columns and indexes (`idx_palletes_line_authorization_id`).
