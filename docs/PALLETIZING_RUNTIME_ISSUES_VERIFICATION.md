# Palletizing Runtime Issues — Verification & Fix Report

## 1. Issues Investigated

| #   | Problem                            | Observed Symptom                                                                 |
| --- | ---------------------------------- | -------------------------------------------------------------------------------- |
| 1   | No per-line handover button        | App has no visible "تسليم مناوبة" action per production line                     |
| 2   | Operator not showing after PIN     | "لا يوجد مشغل مفوض" displayed instead of the authorized operator name            |
| 3   | PIN dialog reappears after refresh | Even though a line already has an active authorization, the PIN overlay reopens  |
| 4   | Per-line independence              | Lines 1 and 2 must preserve their own authorization/handover state independently |

---

## 2. Root Cause Analysis

### Issue 1 — No per-line handover button

**Category: Frontend UI not implemented**

The backend already exposes all information needed:

- `LineStateResponse.authorized = true` → operator is active on this line
- `LineStateResponse.pendingHandover` → non-null when a handover exists
- `POST /api/v1/palletizing-line/lines/{lineId}/handover` → per-line handover creation
- `GET /api/v1/palletizing-line/lines/{lineId}/handover/pending` → pending handover details

The frontend simply has not rendered the handover button/card per line.

**Backend improvement made**: Added `canInitiateHandover` (boolean) to `LineStateResponse` — true when the line is authorized and not blocked. Frontend can directly bind this to button visibility.

### Issue 2 — Operator not showing after PIN

**Category: Frontend read + data setup issue**

Backend returns `operatorName` correctly in **all three** response paths:

1. `POST .../authorize-pin` → `LineAuthorizationResponse.operatorName` ✓
2. `GET .../bootstrap` → `lines[].authorization.operatorName` ✓
3. `GET .../lines/{id}/state` → `authorization.operatorName` ✓

Possible causes:

- **Frontend not reading** `authorization.operatorName` from the response
- **No operators with PINs set** — `DataSeeder` seeds 2 production lines but does NOT create any operators. Operators and their PINs must be created via the web admin panel at `/web/admin/operators`.

### Issue 3 — PIN dialog reappears after refresh

**Category: Frontend logic bug**

Backend authorization is **DB-persisted** (`line_operator_authorizations` table with `status = ACTIVE`). It survives any app refresh.

When the app calls `GET /bootstrap`, every line with an active authorization returns:

```json
{
  "lineId": 1,
  "authorized": true,
  "lineUiMode": "AUTHORIZED",
  "authorization": {
    "authorizationId": 123,
    "operatorName": "أحمد",
    "status": "ACTIVE",
    ...
  }
}
```

The `authorizationToken` field is intentionally `null` in bootstrap/line-state responses — it is a **one-time value** returned only on successful `authorize-pin`. If the frontend uses token presence to determine authorization state, it will incorrectly show the PIN dialog on every refresh.

**Backend improvement made**: Added `lineUiMode` (String) to `LineStateResponse` — a single source-of-truth field telling the frontend exactly which UI to render.

### Issue 4 — Per-line independence

**Category: No backend issue**

Each line has its own `LineOperatorAuthorization` entity, its own handover state, and its own session table. Bootstrap returns an independent `LineStateResponse` per line. No shared/global state leaks between lines.

---

## 3. Backend Changes Made

### File: `LineStateResponse.java`

Added two fields to the main response:

- `String lineUiMode` — computed enum string:
  - `NEEDS_AUTHORIZATION` — no active operator; show PIN overlay
  - `AUTHORIZED` — operator active, no pending handover; normal production + show handover button
  - `PENDING_HANDOVER_NEEDS_INCOMING` — outgoing created handover, line released; incoming must authorize + confirm/reject
  - `PENDING_HANDOVER_REVIEW` — authorized operator present AND pending handover (edge case)
- `boolean canInitiateHandover` — `true` when `authorized && !blocked`

Added two fields to `LineHandoverSummary`:

- `String createdAtDisplay` — Arabic-formatted creation timestamp
- `String notes` — outgoing operator's handover notes

### File: `LineStateService.java`

- Injected `ArabicDateTimeFormatter`
- After computing `authorized`, `blocked`, and `pendingHandover`, computes `lineUiMode` and `canInitiateHandover`
- Populates `createdAtDisplay` and `notes` in the handover summary builder

### No changes to:

- `LineAuthorizationResponse.java` — already returns `operatorName`
- `PalletizingBootstrapService.java` — delegates to `LineStateService`; inherits new fields automatically
- `PalletizingLineController.java` — all endpoints already exist

---

## 4. Sample Response Structures

### Bootstrap response (after changes)

```json
{
  "success": true,
  "data": {
    "productTypes": [
      {
        "id": 1,
        "name": "أحمر 20 كغ",
        "prefix": "0001",
        "color": "أحمر",
        "packageQuantity": 50,
        "packageUnit": "KG"
      }
    ],
    "lines": [
      {
        "lineId": 1,
        "lineName": "خط الإنتاج 1",
        "lineNumber": 1,
        "authorized": true,
        "lineUiMode": "AUTHORIZED",
        "canInitiateHandover": true,
        "authorization": {
          "authorizationId": 42,
          "lineId": 1,
          "lineName": "خط الإنتاج 1",
          "lineNumber": 1,
          "operatorId": 7,
          "operatorName": "أحمد",
          "status": "ACTIVE",
          "authorizedAt": "2026-04-02T08:00:00Z",
          "authorizedAtDisplay": "2026-04-02، 11:00 صباحًا",
          "lastUsedAt": "2026-04-02T09:30:00Z",
          "lastUsedAtDisplay": "2026-04-02، 12:30 مساءً"
        },
        "sessionTable": [
          {
            "productTypeId": 1,
            "productTypeName": "أحمر 20 كغ",
            "productTypePrefix": "0001",
            "completedPalletCount": 5,
            "completedPackageCount": 250,
            "loosePackageCount": 3
          }
        ],
        "blocked": false
      },
      {
        "lineId": 2,
        "lineName": "خط الإنتاج 2",
        "lineNumber": 2,
        "authorized": false,
        "lineUiMode": "NEEDS_AUTHORIZATION",
        "canInitiateHandover": false,
        "blocked": false
      }
    ]
  }
}
```

### Line with pending handover

```json
{
  "lineId": 1,
  "lineName": "خط الإنتاج 1",
  "lineNumber": 1,
  "authorized": false,
  "lineUiMode": "PENDING_HANDOVER_NEEDS_INCOMING",
  "canInitiateHandover": false,
  "blocked": true,
  "blockedReason": "PENDING_HANDOVER",
  "pendingHandover": {
    "handoverId": 15,
    "outgoingOperatorName": "أحمد",
    "status": "PENDING",
    "looseBalanceCount": 2,
    "hasIncompletePallet": true,
    "createdAtDisplay": "2026-04-02، 02:00 مساءً",
    "notes": "باقي 3 طرود من الأحمر"
  }
}
```

---

## 5. Frontend Prompt

> **To: Frontend AI Agent**
>
> The backend palletizing API has been verified and enhanced. All reported runtime issues are caused by frontend logic. Here is exactly what needs to be fixed.
>
> ### Context
>
> - Backend authorization is DB-persisted and survives app refresh
> - `GET /api/v1/palletizing-line/bootstrap` returns all lines with full state
> - Each line in `bootstrap.lines[]` is a `LineStateResponse`
> - A new field `lineUiMode` (String) is the single source of truth for which UI to render per line
> - A new field `canInitiateHandover` (boolean) controls handover button visibility
>
> ### Fix 1 — Restore authorization state from bootstrap (no unnecessary PIN dialog)
>
> On app start / refresh, call `GET /bootstrap` and for each line:
>
> - Read `line.lineUiMode`:
>   - `"NEEDS_AUTHORIZATION"` → show LineAuthOverlay (PIN dialog) for this line
>   - `"AUTHORIZED"` → show normal production UI with operator info and handover button
>   - `"PENDING_HANDOVER_NEEDS_INCOMING"` → show pending handover card; if incoming operator logs in (PIN → authorize-pin), then show confirm/reject actions
>   - `"PENDING_HANDOVER_REVIEW"` → show production UI + pending handover info
> - **Do NOT** use `authorizationToken` presence to determine auth state — this field is `null` in bootstrap (one-time value from authorize-pin only)
> - **Do NOT** re-show the PIN overlay if `lineUiMode` is `"AUTHORIZED"` — the operator is already authorized
>
> ### Fix 2 — Show operator name after authorization
>
> After successful `POST /lines/{lineId}/authorize-pin`:
>
> - Read `response.data.operatorName` from the `LineAuthorizationResponse`
> - Display it in the "المشغل المسؤول" section for that specific line
>
> On bootstrap restore:
>
> - Read `line.authorization.operatorName` for each line where `line.authorized == true`
> - Display it in the operator section — do NOT show "لا يوجد مشغل مفوض" when `authorized` is `true`
>
> ### Fix 3 — Add per-line handover button
>
> For each line where `canInitiateHandover == true`:
>
> - Show a "تسليم مناوبة" button in the line's UI section
> - On tap: call `POST /api/v1/palletizing-line/lines/{lineId}/handover` with optional `{ notes, incompletePalletProductTypeId, incompletePalletQuantity, incompletePalletScannedValue }`
> - After handover creation: refresh line state (`GET /lines/{lineId}/state`)
> - The line will now return `lineUiMode: "PENDING_HANDOVER_NEEDS_INCOMING"` and `blocked: true`
>
> For each line where `pendingHandover` is non-null:
>
> - Show the `LineHandoverCard` with:
>   - `pendingHandover.outgoingOperatorName` — who created the handover
>   - `pendingHandover.createdAtDisplay` — when it was created
>   - `pendingHandover.notes` — optional notes from outgoing operator
>   - `pendingHandover.looseBalanceCount` — number of loose balance items
>   - `pendingHandover.hasIncompletePallet` — whether there's an incomplete pallet
> - If the current line is newly authorized (incoming operator did PIN), show confirm/reject:
>   - Confirm: `POST /lines/{lineId}/handover/{handoverId}/confirm`
>   - Reject: `POST /lines/{lineId}/handover/{handoverId}/reject`
>
> ### Fix 4 — Per-line independence
>
> All state is per-line. The `bootstrap.lines[]` array contains independent `LineStateResponse` objects.
>
> - Line 1 can be `AUTHORIZED` while line 2 is `NEEDS_AUTHORIZATION`
> - Line 1 can have a pending handover while line 2 is in normal production
> - Authorization, handover, and session table are all scoped to `lineId`
> - **Never** use a global/shared state variable for authorization across lines
>
> ### API Quick Reference
>
> | Endpoint                                                        | Method | Purpose                                             |
> | --------------------------------------------------------------- | ------ | --------------------------------------------------- |
> | `/api/v1/palletizing-line/bootstrap`                            | GET    | Initial state hydration (all lines + product types) |
> | `/api/v1/palletizing-line/lines/{lineId}/state`                 | GET    | Single line state refresh                           |
> | `/api/v1/palletizing-line/lines/{lineId}/authorize-pin`         | POST   | Authorize operator by PIN (body: `{"pin":"1234"}`)  |
> | `/api/v1/palletizing-line/lines/{lineId}/authorization`         | GET    | Read current authorization                          |
> | `/api/v1/palletizing-line/lines/{lineId}/authorization`         | DELETE | Release authorization                               |
> | `/api/v1/palletizing-line/lines/{lineId}/handover`              | POST   | Create per-line handover                            |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/pending`      | GET    | Get pending handover details                        |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm` | POST   | Confirm handover (incoming)                         |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`  | POST   | Reject handover (incoming)                          |
>
> ### Key `lineUiMode` Decision Matrix
>
> | `authorized` | `pendingHandover` | `lineUiMode`                      | Frontend UI                             |
> | ------------ | ----------------- | --------------------------------- | --------------------------------------- |
> | `false`      | `null`            | `NEEDS_AUTHORIZATION`             | PIN overlay                             |
> | `true`       | `null`            | `AUTHORIZED`                      | Production + handover button            |
> | `false`      | present           | `PENDING_HANDOVER_NEEDS_INCOMING` | Pending handover card, PIN for incoming |
> | `true`       | present           | `PENDING_HANDOVER_REVIEW`         | Production + handover review            |
>
> ### Data Setup Reminder
>
> - Production lines are seeded by `DataSeeder` (2 lines)
> - **Operators must be created manually** via web admin at `/web/admin/operators` — the seeder does NOT create operators
> - Each operator needs a 4-digit PIN set via the admin panel
> - Product types must also exist (admin creates them) — the "لا يوجد أنواع منتجات" warning is a data setup issue

---

## 6. Verification Notes

### Endpoints verified (code inspection)

- `GET /api/v1/palletizing-line/bootstrap` — calls `PalletizingBootstrapService.getBootstrap()` → `LineStateService.getLineState()` per line → returns new `lineUiMode` and `canInitiateHandover` fields
- `GET /api/v1/palletizing-line/lines/{lineId}/state` — calls `LineStateService.getLineState()` directly → same enriched response
- `POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin` — creates DB-persisted `LineOperatorAuthorization` with `status=ACTIVE` → returns `operatorName` in `LineAuthorizationResponse`
- `DELETE /api/v1/palletizing-line/lines/{lineId}/authorization` — sets `status=RELEASED` → subsequent state queries return `authorized=false`
- `POST /api/v1/palletizing-line/lines/{lineId}/handover` — creates pending handover, releases outgoing auth → line becomes blocked
- Handover confirm/reject endpoints update status correctly

### Authorization persistence verified

- `LineOperatorAuthorization` entity has `status` column (ACTIVE/RELEASED/REPLACED)
- `active_lock` generated column (`IF(status='ACTIVE', production_line_id, NULL)`) + unique constraint enforces at-most-one active per line at DB level
- Authorization survives app refresh — it's a DB row, not a session/token
- `authorizationToken` is only returned once (on authorize-pin) and is intentionally null in bootstrap/line-state — by design

### Tests

- Existing `PalletizingWorkflowAlignmentTest` unaffected — tests `PalletizingService` via mocks, not `LineStateService`
- Compilation verified
