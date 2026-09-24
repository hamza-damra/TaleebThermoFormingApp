# Frontend Handoff — Palletizing App — Grinding Recommendation at Pallet Creation + Grinding Label Marker

> Backend feature: **Unified Grinding Lifecycle** (Flyway V198–V205). Filename kept as requested by the
> owner (it is the Palletizing App handoff for this feature).

## 1. Executive Summary

- The palletizer can now **recommend a pallet for grinding while registering it** (a defective batch).
  The backend creates the pallet and, in the same transaction, a grinding order waiting for the plant
  manager's approval (`PENDING_APPROVAL`). A reason is mandatory.
- A pallet recommended for grinding is on **grinding hold**: warehouse drivers cannot move it until the
  manager decides.
- **The printed label must show the grinding marker** «(موصى بالجرش)» while the recommendation is pending
  or approved. The label's QR / `scannedValue` never changes; the marker is one extra text line.
- Once grinding has **started or completed**, normal label reprint is refused (`labelReprintAllowed=false`,
  409 `PALLET_BLOCKED_BY_GRINDING`).
- The request/response changes are **additive**; the old app keeps working, but the marker requirement is
  only physically met once this app prints it. Ship this app update with the backend release.

## 2. Affected App

**Palletizing App** (palletizing line devices, device key + line authorization).

Related but separate: the **Operator App** can recommend an *existing* pallet (its own handoff,
`FRONTEND_HANDOFF_OPERATOR_APP_UNIFIED_GRINDING.md`); the **Warehouse App** sees the hold
(`FRONTEND_HANDOFF_WAREHOUSE_APP_UNIFIED_GRINDING.md`); the new **Grinding App** grinds it
(`GRINDING_APP_BACKEND_CONTRACT.md`).

## 3. Business Context

The palletizer sometimes packs a pallet that must not go to the warehouse (wrong print, deformed cups,
contamination). Today there is no way to say so. Now, while registering the pallet, the palletizer ticks
«توصية بالجرش», types why, and the pallet is created and flagged. The label printed on it says
«(موصى بالجرش)» so nobody on the floor moves it by mistake. The plant manager approves or rejects:
- approve → a grinding worker grinds it (Grinding App);
- reject → the hold is lifted and the pallet goes to the warehouse as usual.

The pallet still counts as produced in every production report (gross production is unchanged).

## 4. Backend Contract Changes

### 4.1 `POST /api/v1/palletizing-line/lines/{lineId}/pallets` (changed — additive)

Headers unchanged (`X-Device-Key` + the existing line-authorization flow). New optional body object
`grindingRecommendation`:

```json
{
  "productTypeId": 12,
  "quantity": 32,
  "expectedPlanItemId": 889,
  "confirmOverproduction": false,
  "grindingRecommendation": { "reason": "طباعة غير واضحة على الكاسات" }
}
```
- Present object = "recommend for grinding". Absent / `null` = normal pallet (exactly today's behaviour).
- `reason`: required when the object is present, trimmed, non-blank, ≤ 500 characters →
  400 `VALIDATION_ERROR` otherwise. Validated **before** a serial number is consumed.
- May be combined with `firstPalletFaletConsumption`.

Response (`CreatePalletResponse`) gains:
```json
{
  "success": true,
  "data": {
    "palletId": 50412,
    "scannedValue": "120000004411",
    "...": "all existing fields unchanged",
    "grindingOrder": {
      "id": 1043, "orderNumber": "GR-001043",
      "status": "PENDING_APPROVAL", "statusLabel": "بانتظار موافقة المدير على توصية الجرش",
      "sourceType": "PALLET", "sourceOrigin": "PALLETIZING_PALLET",
      "creationBasis": "LIVE", "managerApprovalRequired": true, "legacy": false
    },
    "grindingRecommended": true,
    "grindingLabelText": "(موصى بالجرش)",
    "labelReprintAllowed": true
  }
}
```
For a normal pallet: `grindingOrder` absent, `grindingRecommended=false`, `grindingLabelText` absent,
`labelReprintAllowed=true`.

### 4.2 Label payloads — three print paths, same three new fields

| Print path in the app | Endpoint / source | New fields |
|---|---|---|
| Create dialog (`fromCreatedPallet`) | `CreatePalletResponse` above | `grindingRecommended`, `grindingLabelText`, `labelReprintAllowed` |
| Reprint by number (`fromResolvedLabel`) | `GET /api/v1/palletizing-line/pallets/{scannedValue}/label` → `PalletLabelPayload` | same |
| Session drill-down (`fromSessionPallet`) | `GET /api/v1/palletizing-line/lines/{lineId}/session-production-detail` → `SessionPalletDetail` | same + `grindingStatus`, `grindingStatusLabel` |

Marker rule (decided by the backend from the order's current status — never compute it yourself):

| Grinding order status | `grindingRecommended` | `grindingLabelText` | `labelReprintAllowed` |
|---|---|---|---|
| none / `REJECTED` / `CANCELLED` | `false` | absent | `true` |
| `PENDING_APPROVAL` / `READY_FOR_GRINDING` | `true` | `(موصى بالجرش)` | `true` |
| `IN_GRINDING` / `COMPLETED` | `true` or `false`* | absent | **`false`** |

\* Do not print; `labelReprintAllowed=false` is the only field that matters there.

`GET /pallets/{scannedValue}/label` for an `IN_GRINDING` / `COMPLETED` pallet → **409
`PALLET_BLOCKED_BY_GRINDING`** (Arabic in section 10).

### 4.3 Refresh

When an order changes (recommended from the Operator App, approved, rejected, voided), the backend publishes
the existing `palletizing-lines-changed` refresh frame on the Palletizing App line-events SSE stream (reason
`PALLET_GRINDING_CHANGED`, section `PRODUCED_PALLETS`). Treat it like any other refresh frame: re-fetch the
session table / drill-down. No new SSE endpoint.

### 4.4 New / relevant error codes

| Code | HTTP | When | UI |
|---|---:|---|---|
| `VALIDATION_ERROR` | 400 | grinding reason missing / blank / > 500 | inline under the reason field |
| `PALLET_BLOCKED_BY_GRINDING` | 409 | reprint of a pallet whose grinding started or finished | dialog, not recoverable |

## 5. Required Frontend Screens / Dialogs

1. **Create pallet dialog (changed)** — add a switch/checkbox «توصية بالجرش» (default off). When on, show a
   required multi-line field «سبب التوصية بالجرش» (max 500). Button unchanged («تسجيل الطبلية»).
   - Validation: reason required when switched on → «سبب التوصية بالجرش مطلوب.»
   - Success: the normal success + auto-print, plus a notice «تم إرسال توصية الجرش للمدير».
2. **Label layout (changed)** — add ONE extra bottom text line carrying `grindingLabelText` when
   `grindingRecommended == true` and the text is present. The current `LabelLayout` has room for exactly one
   bottom line, so the layout must grow by one line (or move the existing bottom line up); do not replace or
   shrink the QR / scanned value / product / quantity lines. Bold, same font size as the product line.
3. **Reprint (changed)** — if `labelReprintAllowed == false`, disable «إعادة الطباعة» and show
   «الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق.»; on 409 show the same text.
4. **Session drill-down row (changed)** — show a small chip with `grindingStatusLabel` when present.

## 6. Required Models / DTO Changes

- `CreatePalletRequest`: + `grindingRecommendation: { reason: String }?`.
- `CreatePalletResponse`: + `grindingOrder: GrindingOrderSummary?`, `grindingRecommended: bool?`,
  `grindingLabelText: String?`, `labelReprintAllowed: bool?`.
- `PalletLabelPayload`: + `grindingRecommended: bool?`, `grindingLabelText: String?`,
  `labelReprintAllowed: bool?`.
- `SessionPalletDetail`: + the same three + `grindingStatus: String?`, `grindingStatusLabel: String?`.
- New `GrindingOrderSummary { id, orderNumber, status, statusLabel, sourceType, sourceOrigin,
  creationBasis, managerApprovalRequired, legacy }`.
- All new fields nullable: an older backend omits them → treat as "no marker, reprint allowed".
- If the app caches labels for failed prints, persist the new fields in that cache (`toJson`/`fromJson`),
  or a reprinted cached label loses the marker.

## 7. Required Repository / API Client Changes

- `createPallet(lineId, request)` sends `grindingRecommendation` when set.
- Label builders `fromCreatedPallet`, `fromResolvedLabel`, `fromSessionPallet` read the three fields.
- Error map: `PALLET_BLOCKED_BY_GRINDING` → section 10 text.
- Idempotency: unchanged (the create call keeps its existing behaviour).

## 8. Required Provider / State Management Changes

- Create-dialog state: `recommendGrinding: bool`, `grindingReason: String`, reset when the dialog closes.
- Label model: `grindingRecommended`, `grindingLabelText`, `labelReprintAllowed`.
- Session detail refresh on `palletizing-lines-changed` (already wired) picks up hold changes.

## 9. Required UX Flow

- **Happy path:** switch on «توصية بالجرش» → type reason → «تسجيل الطبلية» → pallet created → label prints
  with «(موصى بالجرش)» → notice «تم إرسال توصية الجرش للمدير».
- **Validation failure:** switch on, empty reason → inline error, nothing sent.
- **Network failure:** same as today's pallet creation (the create call's existing retry rules apply).
- **Backend error:** existing create errors unchanged.
- **Reprint later:** PENDING/READY → prints with the marker; after the manager rejects → prints without it;
  IN_GRINDING/COMPLETED → reprint disabled.
- **Cancel:** closing the dialog discards the reason.

## 10. Arabic UI Text

| Situation | Arabic |
|---|---|
| Switch label | توصية بالجرش |
| Reason label | سبب التوصية بالجرش |
| Reason required | سبب التوصية بالجرش مطلوب. |
| Reason too long | يجب ألا يتجاوز السبب 500 حرف. |
| Success notice | تم إرسال توصية الجرش للمدير |
| Label marker (from backend) | (موصى بالجرش) |
| Reprint blocked | الطبلية قيد الجرش أو تم جرشها — لا يمكن إعادة طباعة الملصق. |

## 11. Edge Cases

- **Double tap on create:** unchanged create behaviour (button disabled while in flight).
- **Manager rejects while the dialog is open:** irrelevant to creation; reprint then prints without the marker.
- **Old cached label** (printed before rejection): the next reprint fetches a fresh payload.
- **Pallet voided while PENDING:** the grinding order is cancelled with it (backend); nothing to do.
- **Old backend:** fields absent → no marker, reprint allowed.
- **App resumed:** refresh the session table as today.

## 12. Testing Requirements

- Unit: request serialisation with/without `grindingRecommendation`; label builders for the three paths ×
  marker states; cache round-trip keeps the fields.
- Widget: switch reveals the required reason; validation; reprint disabled when `labelReprintAllowed=false`.
- Printer: the extra line renders without clipping on the real label stock (both printer types in use).
- Manual smoke on a test environment: create a recommended pallet → marker printed; reject on
  `/web/admin/grinding` → reprint has no marker; approve + start in the Grinding App (test env only) →
  reprint refused.
- Regression: normal pallet creation, FALET first pallet, overproduction confirmation, reprint.

## 13. Backend Compatibility Notes

- Requires the backend release with V198–V205. All changes are additive: the old app keeps creating pallets;
  it simply cannot recommend and does not print the marker.
- The marker is a physical-label requirement: until this app ships, a recommended pallet (e.g. from the
  Operator App) reprinted here would lack the marker. Release this app with the backend.
- No feature flag.

## 14. Final Acceptance Criteria

- A pallet can be created with a mandatory grinding reason; the response carries the PENDING order.
- Every label printed from the three paths shows «(موصى بالجرش)» exactly when the backend says so.
- Reprint is impossible once grinding started or finished.
- Normal pallets print exactly as before.
