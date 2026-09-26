# Frontend Handoff — Palletizing App: move pallet from PRODUCTION to TRANSIT («الرصيف»)

Backend version: Flyway **V210** (`V210__palletizer_production_to_transit_move.sql`).
Branch: `claude/exciting-rubin-oko624`.

## 1. Executive summary

The Palletizing App gets **one new capability**: moving a pallet from the production line
(`PRODUCTION`, «خط الإنتاج») to the dock (`TRANSIT`, «الرصيف»). It is a single central **Scan**
action — QR scan or typed 12-digit number — with **no line picker**, no source/destination picker and
no product field.

At the same time the backend now **enforces** three rules the app must surface:

1. **Continuation** — a second pallet of the **same product** cannot be registered on the line while
   an earlier one of that product (same shift-line) is still at PRODUCTION
   (`PREVIOUS_PALLET_STILL_AT_PRODUCTION`).
2. **Logout** — the palletizer cannot log out while the line still has pallets at PRODUCTION
   (`PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS`).
3. The operator cannot end the shift / hand over the line while pallets are at PRODUCTION (Operator
   App handoff).

A driver's ordinary Warehouse App scan PRODUCTION → TRANSIT satisfies every rule exactly like the
palletizer's move.

Terminology: the location is officially **`TRANSIT`**. The Arabic label stays **«الرصيف»**. There is no
`DOCK` value anywhere in the API.

## 2. App impact matrix

| App | Affected? | Reason | Required Handoff File |
|---|---:|---|---|
| Palletizing App | **Yes** | New move endpoint + pending list, new blocking errors on create / FALET / logout | this file |
| Operator App | **Yes** | Shift end, line release, takeover handover, explicit line end blocked; preview + checklist fields | `FRONTEND_HANDOFF_OPERATOR_APP_PRODUCTION_PALLET_HANDOVER_GUARD.md` |
| Warehouse App | Informational | Movement lists may now show palletizer-authored PRODUCTION→TRANSIT movements; additive `palletizerSessionId` | `FRONTEND_HANDOFF_WAREHOUSE_APP_PALLETIZER_TRANSIT_MOVEMENTS.md` |
| Admin App | Informational | Line/shift views refresh; admin end-shift is NOT blocked but leaves carryover pallets | `FRONTEND_HANDOFF_ADMIN_APP_PRODUCTION_PALLET_CARRYOVERS.md` |
| Roll Worker App | No | No contract touched | — |
| Roll Production App | No | No contract touched | — |

## 3. Backend contract

All routes are on the device-key chain (`X-Device-Key`, as every `/api/v1/palletizing-line/**` call)
and require the palletizer session token header **`X-Palletizer-Session-Token`** (the `sessionToken`
returned by `POST /lines/{lineId}/palletizer-auth`). No JWT.

### 3.1 `POST /api/v1/palletizing-line/palletizer/pallets/move-to-transit`

Request:

```json
{
  "identifier": "101000000123",
  "clientRequestId": "4d1f6c1e-0b8b-4f0e-9d0d-4a9a1f2a7c11",
  "scanType": "QR"
}
```

| Field | Rules |
|---|---|
| `identifier` | Required. The QR payload or the typed number. Spaces, bidi marks and Arabic-Indic digits (٠–٩, ۰–۹) are accepted and normalised server-side. Must end up as exactly 12 digits. |
| `clientRequestId` | Required, 1–64 chars. Generate **one UUID per physical scan** and reuse it verbatim for every retry of that scan (timeouts, lost responses). A new scan → a new id. |
| `scanType` | Optional, `QR` (default) or `NUMBER` (manual entry). Audit only. |

Success `200`:

```json
{
  "success": true,
  "data": {
    "movementId": 90211,
    "palletId": 55012,
    "scannedValue": "101000000123",
    "productTypeId": 7,
    "productTypeName": "علبة 500 مل",
    "palletizingLineId": 2,
    "palletizingLineName": "خط 2",
    "thermoformingShiftLineId": 3120,
    "fromLocation": "PRODUCTION",
    "toLocation": "TRANSIT",
    "currentLocation": "TRANSIT",
    "movedAt": "2026-09-24T12:03:11.412Z",
    "movedAtDisplay": "2026-09-24، 03:03 مساءً",
    "movedByName": "أحمد",
    "producedByPalletizerName": "محمد",
    "inherited": false,
    "replayed": false,
    "movementUndone": false
  }
}
```

- `replayed: true` — this `clientRequestId` was already executed; **no second movement** was made.
  Show the same success UI.
- `movementUndone: true` (only on a replay) — the movement was later undone by the warehouse; the
  pallet is back at PRODUCTION (`currentLocation: "PRODUCTION"`). Show it as "returned to the line"
  and refresh the pending list; do **not** show a green success.
- `inherited: true` — the pallet came from an earlier shift that ended without moving it (see §6).
- `movedAt` is a UTC instant; display in `Asia/Hebron` (or use `movedAtDisplay`).

The server does not use the device clock and does not accept a source or destination.

### 3.2 `GET /api/v1/palletizing-line/palletizer/production-pending-pallets`

Everything still at PRODUCTION on **every line the employee holds an ACTIVE session on**.

```json
{
  "success": true,
  "data": {
    "totalPendingCount": 2,
    "lines": [
      {
        "palletizerSessionId": 811,
        "palletizingLineId": 2,
        "palletizingLineName": "خط 2",
        "thermoformingShiftLineId": 3120,
        "pendingCount": 2,
        "pallets": [
          {
            "palletId": 55011,
            "scannedValue": "101000000122",
            "productTypeId": 7,
            "productTypeName": "علبة 500 مل",
            "thermoformingShiftLineId": 3120,
            "currentLocation": "PRODUCTION",
            "producedAt": "2026-09-24T11:40:00.000Z",
            "producedAtDisplay": "2026-09-24، 02:40 مساءً",
            "palletizerName": "محمد",
            "inherited": false
          }
        ]
      }
    ]
  }
}
```

Empty case: `{"totalPendingCount": 0, "lines": [{"...": "...", "pendingCount": 0, "pallets": []}]}`
(one entry per active session, each with an empty list).

### 3.3 Error codes (envelope `{"success": false, "error": {"code", "message", "details"}}`)

| Code | HTTP | When | Details | App action |
|---|---:|---|---|---|
| `PALLETIZER_SESSION_REQUIRED` | 401 | Missing / unknown / ENDED / REPLACED token (also on a retry) | — | Go to PIN login. Do not retry. |
| `VALIDATION_ERROR` | 400 | Missing `identifier` / `clientRequestId`, or longer than 64 chars | field errors | Fix the request (a bug). |
| `PALLET_IDENTIFIER_INVALID` | 400 | Not 12 digits after normalisation | — | «رقم الطبلية غير صالح» — rescan. |
| `PALLET_NOT_FOUND` | 404 | No pallet with that number | `scannedValue` | «لا توجد طبلية بهذا الرقم». |
| `PALLET_CANCELLED` | 409 | Pallet cancelled/voided | — | «هذه الطبلية ملغاة». |
| `PALLET_BLOCKED_BY_GRINDING` | 409 | Pallet recommended / approved / sent for grinding | (existing) | «الطبلية محجوزة للجرش». |
| `PALLET_OUTSIDE_PALLETIZER_LINE_SCOPE` | 403 | Pallet belongs to a line the employee has no active session on | — | «هذه الطبلية ليست من خطوطك الحالية». |
| `PALLET_OUTSIDE_CURRENT_OPERATOR_SHIFT` | 403 | Same line, but another operator shift, and not carried over | — | «هذه الطبلية من وردية مشغّل أخرى». |
| `PALLET_NOT_AT_PRODUCTION` | 409 | Already moved (e.g. a driver took it first) | `palletId`, `scannedValue`, `currentLocation` | Informational: «الطبلية ليست في خط الإنتاج» + current location; refresh the pending list. |
| `PALLETIZER_TRANSIT_MOVE_IDEMPOTENCY_KEY_REUSED` | 409 | The `clientRequestId` was used for another pallet, or by another employee | none (deliberately) | App bug — generate a fresh id per scan. |
| `PALLETIZER_TRANSIT_MOVE_REQUEST_VOIDED` | 409 | The movement of this request was deleted by an administrator | `palletId`, `scannedValue`, `currentLocation` | «تم حذف الحركة من الإدارة» — if the pallet is at PRODUCTION, the user must **scan again** (new `clientRequestId`). |

### 3.4 Existing endpoints — new refusals

| Endpoint | New error | Details |
|---|---|---|
| `POST /api/v1/palletizing-line/lines/{lineId}/pallets` (every create variant, incl. grinding recommendation) | `PREVIOUS_PALLET_STILL_AT_PRODUCTION` 409 | `thermoformingShiftLineId`, `productTypeId`, `blockingPalletCount`, `blockingPallets[≤50]` (same item shape as §3.2) |
| `POST /api/v1/palletizing-line/lines/{lineId}/palletizer-logout` | `PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS` 409 | `pendingProductionPalletCount`, `blockedLines[{thermoformingShiftLineId, palletizingLineId, palletizingLineName, count, pallets[≤50]}]` |

The refusal happens before a serial number is reserved or anything is written, so the request can
simply be retried after the blocking pallet is moved. A *different* product is never blocked.
Logging in with a PIN on a line that already has a session (session replacement) is **not** a logout
and is **not** blocked: the new session inherits the pending pallets.

## 4. Required screens / dialogs

1. **Scan to dock** — one prominent action «نقل إلى الرصيف» on the main screen (not per line).
   Opens the camera; a «إدخال يدوي» link opens a numeric field (12 digits). Submit → §3.1.
2. **Pending at production panel** — «طبليات في خط الإنتاج» with a count badge, grouped by line, each
   row: number, product, produced time, palletizer, «موروثة» chip when `inherited`. Row tap → confirm
   dialog → move (same endpoint, `scanType: "NUMBER"`). Source: §3.2.
3. **Create blocked dialog** — on `PREVIOUS_PALLET_STILL_AT_PRODUCTION`: «لا يمكن تسجيل طبلية جديدة من
   نفس المنتج قبل نقل الطبلية السابقة إلى الرصيف», list `blockingPallets`, primary button «نقل إلى
   الرصيف» per pallet.
4. **Logout blocked dialog** — on `PALLETIZER_LOGOUT_BLOCKED_BY_PRODUCTION_PALLETS`: «لا يمكن تسجيل
   الخروج قبل نقل جميع الطبليات إلى الرصيف», list per line, same move action.

Do **not** show a destination picker, a line picker or an "undo" action — undo/delete remain
warehouse/admin corrections.

## 5. Models, API client and state

- `PalletizerTransitMoveRequest { identifier, clientRequestId, scanType? }`
- `PalletizerTransitMoveResponse` — fields in §3.1 (booleans are always present).
- `ProductionPendingPallets { totalPendingCount, lines[] }`, `PendingLine`, `PendingPallet`.
- Store the `clientRequestId` with the in-flight scan; retry with the same id on network failure /
  5xx; discard it after any 2xx or any 4xx other than a network error.
- Parse the new error `details` for the two blocked dialogs.

## 6. Refresh behaviour (SSE)

After every committed change (palletizer move, driver move, undo, movement deletion, grinding
rejection) the backend emits, AFTER_COMMIT:

- `GET /api/v1/palletizing-line/app-events` → `palletizing-lines-changed` (existing frame) and
- `GET /api/v1/palletizing-line/lines/{lineId}/operator-dashboard/events` →
  `operator-dashboard-changed` with `reason: "PALLET_LOCATION_CHANGED"`, sections
  `PRODUCED_PALLETS`, `SUMMARY`.

On either, refetch §3.2 (and the produced-pallets list). Also refetch on SSE reconnect and on app
resume. No polling is required.

**Inherited pallets.** If an operator's line ended through an administrative or automatic path
(admin end-shift, pause, takeover timeout, plan reconciler) while pallets were still at PRODUCTION,
those pallets are carried over to the line and appear in the next shift's list with
`inherited: true`. They block logout and handover like the new shift's own pallets and can be moved
by the new palletizer.

## 7. Arabic UI text

| Key | Text |
|---|---|
| action | نقل إلى الرصيف |
| manual entry | إدخال يدوي |
| pending title | طبليات في خط الإنتاج |
| inherited chip | موروثة من وردية سابقة |
| success | تم نقل الطبلية إلى الرصيف |
| replay undone | أُعيدت الطبلية إلى خط الإنتاج |
| create blocked | لا يمكن تسجيل طبلية جديدة من نفس المنتج قبل نقل الطبلية السابقة إلى الرصيف |
| logout blocked | لا يمكن تسجيل الخروج قبل نقل جميع الطبليات إلى الرصيف |

## 8. Edge cases

- Driver and palletizer scan the same pallet at once → exactly one movement; the loser gets
  `PALLET_NOT_AT_PRODUCTION` (or `replayed: true` if it was its own retry).
- A pallet whose only movement an admin deleted counts as at PRODUCTION again and can be moved.
- Employee with sessions on several lines: one Scan covers all of them.
- Grinding-held pallets never block and cannot be moved; a rejected grinding recommendation makes
  the pallet pending again.
- Paused line: the move still works (it only removes blockers); logout still requires an empty list.

## 9. Testing requirements (app side)

Happy scan; manual entry with Arabic digits; retry after timeout with the same `clientRequestId`
(expect `replayed: true`); each error in §3.3; create-blocked and logout-blocked dialogs and their
"move" shortcuts; SSE-driven refresh after a driver move; inherited chip; multi-line employee.

## 10. Backend compatibility / rollout

- **Not purely additive.** Create and logout gain new 409 refusals that older app builds show as a
  generic error, and a palletizer with an old build has **no way to move** a pallet (only drivers
  can). **Ship the new Palletizing App build together with the backend.**
- Deploy between shifts, or have drivers clear PRODUCTION on active shift-lines first, so no
  palletizer is stuck at logout at go-live.
- No feature switch: the guards are enforced immediately on deploy (confirmed business decision).

## 11. Acceptance criteria

- One Scan action moves a pallet to «الرصيف» without choosing a line or destination.
- Retries never create a second movement; undone/deleted outcomes are shown truthfully.
- The two blocked dialogs list the blocking pallets and offer the move.
- The pending list refreshes on SSE without manual reload.
