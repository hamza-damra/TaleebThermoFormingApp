# FRONTEND_AI_AGENT_HANDOFF.md — Handover FALET Reconciliation & Admin Production Corrections

> **Generated from**: actual backend source code inspection (not the plan).
> **Date context**: After Phases 1–5 implementation. V38 migration applied.
> **Audience**: AI agent implementing the Flutter palletizing app changes.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Feature A — Handover-Time FALET Reconciliation (Flutter)](#2-feature-a--handover-time-falet-reconciliation-flutter)
3. [Feature B — Admin Production Corrections (Thymeleaf Only)](#3-feature-b--admin-production-corrections-thymeleaf-only)
4. [Endpoints — Full Contract Reference](#4-endpoints--full-contract-reference)
5. [Request DTOs](#5-request-dtos)
6. [Response DTOs](#6-response-dtos)
7. [Enums](#7-enums)
8. [Error Codes & Error Contract](#8-error-codes--error-contract)
9. [Validation Rules — Exhaustive List](#9-validation-rules--exhaustive-list)
10. [State Machine / Business Logic](#10-state-machine--business-logic)
11. [Data Flow — Step by Step](#11-data-flow--step-by-step)
12. [Existing Endpoints the Frontend Must Use](#12-existing-endpoints-the-frontend-must-use)
13. [SSE / Real-Time Events](#13-sse--real-time-events)
14. [Admin Web Changes (Thymeleaf — No Flutter Work)](#14-admin-web-changes-thymeleaf--no-flutter-work)
15. [Known Gaps / Mismatches](#15-known-gaps--mismatches)
16. [Recommended Flutter Implementation Order](#16-recommended-flutter-implementation-order)

---

## 1. Executive Summary

Two backend features were implemented:

| Feature                                    | Surface                                                       | Flutter work needed?                                                |
| ------------------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------- |
| **A — Handover-Time FALET Reconciliation** | REST API (`POST /api/v1/palletizing/lines/{lineId}/handover`) | **YES** — the handover dialog must present FALET resolution choices |
| **B — Admin Production Corrections**       | Thymeleaf web portal (`/web/admin/production-corrections`)    | **NO** — entirely server-rendered HTML; no Flutter API exposed      |

**Breaking change**: When open FALET items exist at handover time, the handover request now **requires** a `faletResolutions` array. Submitting without it returns error `HANDOVER_FALET_DECISION_REQUIRED`. When no open FALET exists, the request is unchanged (backward-compatible).

**Additive change**: The handover response now includes a `reconciledFaletItems` list (empty array when no reconciliation occurred — never null in practice, but defensively treat as nullable).

**Net impact on Pallete entity**: A new `productionStatus` field (`ACTIVE` / `CANCELLED`) was added. Cancelled pallets are excluded from session production detail and daily counts. The `SessionPalletDetail` DTO returned to Flutter does **not** include `productionStatus` — cancelled pallets are simply absent from the response.

---

## 2. Feature A — Handover-Time FALET Reconciliation (Flutter)

### What changed

When an operator initiates a handover (shift-end), the system now checks for **open FALET** items on the line. If any exist, the operator must decide what to do with each one:

- **CARRY_FORWARD** — the FALET item is included in the handover snapshot and carried to the next shift as unresolved FALET.
- **USED_IN_EXISTING_SESSION_PALLETE** — the FALET quantity is retroactively attributed to an existing pallet from the same session. The FALET is resolved (quantity set to 0), and a `FaletPalleteReconciliation` record is created.

### UX flow (recommended)

1. Operator taps "Initiate Handover" on the line screen.
2. Flutter checks `LineStateResponse.hasOpenFalet`.
3. If `true`, Flutter fetches the FALET screen (`GET .../falet`) and session production detail (`GET .../session-production-detail`).
4. Flutter presents a **resolution dialog** listing each open FALET item.
5. For each item, operator picks:
   - **Carry Forward** → no additional input needed.
   - **Reconcile to Existing Pallet** → operator selects a pallet from the same product type group. Only ACTIVE pallets from the session are eligible (cancelled ones won't appear in the session detail response).
6. Flutter submits the handover request with the `faletResolutions` array populated.
7. On success, the response includes `reconciledFaletItems` showing which pallets absorbed which FALET quantities.

### What happens server-side

- FALET items with `USED_IN_EXISTING_SESSION_PALLETE` are marked RESOLVED with `quantity = 0`.
- A `FaletPalleteReconciliation` record links the FALET to the pallet.
- A `FaletEvent` with type `RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER` is recorded.
- The handover snapshot includes **only** CARRY_FORWARD items. Reconciled items are excluded from the snapshot.
- The pallet's `quantity` is **not** modified — the reconciliation is tracked separately.

---

## 3. Feature B — Admin Production Corrections (Thymeleaf Only)

This feature allows admins to cancel pallet creation or edit pallet quantities through the web portal. **No Flutter API endpoints exist for this feature.** It is entirely server-rendered via Thymeleaf templates at `/web/admin/production-corrections`.

The only indirect effect on Flutter: cancelled pallets disappear from `SessionProductionDetailResponse` and daily counts. The Flutter app does not need to handle this — it simply won't see cancelled pallets.

---

## 4. Endpoints — Full Contract Reference

### 4.1 Handover Creation (MODIFIED — the only endpoint Flutter must change)

```
POST /api/v1/palletizing/lines/{lineId}/handover
Authorization: Bearer <JWT>
Content-Type: application/json
```

**Path parameter**: `lineId` (Long) — the production line ID.

**Request body** — `LineHandoverRequest`:

```json
{
  "lastActiveProductTypeId": 5,
  "lastActiveProductFaletQuantity": 3,
  "notes": "Shift notes here",
  "faletResolutions": [
    {
      "faletId": 101,
      "action": "CARRY_FORWARD",
      "existingPalleteId": null
    },
    {
      "faletId": 102,
      "action": "USED_IN_EXISTING_SESSION_PALLETE",
      "existingPalleteId": 42
    }
  ]
}
```

**Response** — `ApiResponse<LineHandoverResponse>`:

```json
{
  "success": true,
  "data": {
    "handoverId": 10,
    "lineId": 1,
    "lineName": "Line A",
    "operatorName": "Ahmad",
    "status": "PENDING",
    "createdAt": "2025-01-15T14:30:00.000+02:00",
    "faletItems": [
      {
        "productTypeName": "Type A",
        "quantity": 5
      }
    ],
    "faletItemCount": 1,
    "hasFalet": true,
    "reconciledFaletItems": [
      {
        "faletId": 102,
        "palleteId": 42,
        "scannedValue": "001000000015",
        "productTypeId": 5,
        "productTypeName": "Type A",
        "reconciledQuantity": 3
      }
    ]
  }
}
```

**Key behavior notes**:

- `faletItems` in the response contains **only CARRY_FORWARD** items (snapshot).
- `reconciledFaletItems` contains **only USED_IN_EXISTING_SESSION_PALLETE** items.
- `faletItemCount` and `hasFalet` reflect carry-forward only.
- When no open FALET exists, `faletResolutions` can be omitted or sent as empty — behavior is unchanged from before.

**Roles**: DRIVER, OFFICER (unchanged).

---

## 5. Request DTOs

### 5.1 LineHandoverRequest

| Field                            | Type                         | Required        | Validation                               | Notes                                                            |
| -------------------------------- | ---------------------------- | --------------- | ---------------------------------------- | ---------------------------------------------------------------- |
| `lastActiveProductTypeId`        | Long                         | No              | Must reference valid active product type | Pre-existing field                                               |
| `lastActiveProductFaletQuantity` | Integer                      | No              | `@Min(1)` when present                   | Pre-existing field; required if `lastActiveProductTypeId` is set |
| `notes`                          | String                       | No              | None                                     | Pre-existing field                                               |
| `faletResolutions`               | List\<FaletResolutionEntry\> | **Conditional** | Required when open FALET exists          | **NEW** — omit when no open FALET                                |

### 5.2 FaletResolutionEntry (inner class of LineHandoverRequest)

| Field               | Type                | Required    | Validation                                                | Notes                                                              |
| ------------------- | ------------------- | ----------- | --------------------------------------------------------- | ------------------------------------------------------------------ |
| `faletId`           | Long                | Yes         | `@NotNull`; must be in the current open FALET set         | References `FaletCurrentState.id`                                  |
| `action`            | HandoverFaletAction | Yes         | `@NotNull`; must be valid enum value                      | `CARRY_FORWARD` or `USED_IN_EXISTING_SESSION_PALLETE`              |
| `existingPalleteId` | Long                | Conditional | Required when action = `USED_IN_EXISTING_SESSION_PALLETE` | References `Pallete.id`; must pass all pallet validations (see §9) |

---

## 6. Response DTOs

### 6.1 LineHandoverResponse (modified)

All pre-existing fields are preserved. New field added:

| Field                  | Type                        | Nullable             | Notes                                                                                                     |
| ---------------------- | --------------------------- | -------------------- | --------------------------------------------------------------------------------------------------------- |
| `reconciledFaletItems` | List\<ReconciledFaletItem\> | Populated on success | Empty list when no reconciliation; `@JsonInclude(NON_NULL)` applies project-wide so null would be omitted |

### 6.2 ReconciledFaletItem (inner class of LineHandoverResponse)

| Field                | Type   | Notes                                    |
| -------------------- | ------ | ---------------------------------------- |
| `faletId`            | Long   | The FALET item that was reconciled       |
| `palleteId`          | Long   | The pallet it was reconciled to          |
| `scannedValue`       | String | Pallet's scanned value (12-digit format) |
| `productTypeId`      | Long   | Product type ID                          |
| `productTypeName`    | String | Product type display name                |
| `reconciledQuantity` | int    | Quantity attributed to this pallet       |

### 6.3 FaletScreenResponse (existing — no changes)

Returned by `GET /api/v1/palletizing/lines/{lineId}/falet`:

| Field                 | Type                      | Notes                            |
| --------------------- | ------------------------- | -------------------------------- |
| `faletItems`          | List\<FaletItemResponse\> | All FALET items for the line     |
| `totalOpenFaletCount` | int                       | Count of open (unresolved) items |
| `hasOpenFalet`        | boolean                   | `true` if any open items         |

### 6.4 FaletItemResponse (existing — no changes)

| Field                | Type    | Notes                                             |
| -------------------- | ------- | ------------------------------------------------- |
| `faletId`            | Long    | **Use this as `faletId` in FaletResolutionEntry** |
| `productTypeId`      | Long    | Product type of the FALET item                    |
| `productTypeName`    | String  | Display name                                      |
| `quantity`           | int     | Open FALET quantity                               |
| `status`             | String  | e.g. "OPEN"                                       |
| `originType`         | String  | How the FALET was created                         |
| `sourceOperatorName` | String  | Operator who created it                           |
| `authorizationId`    | Long    | Authorization context                             |
| `managerResolved`    | boolean | Whether manager resolved it                       |
| `createdAt`          | String  | ISO-8601 timestamp                                |

### 6.5 SessionProductionDetailResponse (existing — behavior changed)

Returned by `GET /api/v1/palletizing/lines/{lineId}/session-production-detail`:

```json
{
  "lineId": 1,
  "authorizationId": 10,
  "groups": [
    {
      "productTypeId": 5,
      "productTypeName": "Type A",
      "productTypePrefix": "001",
      "completedPalletCount": 3,
      "pallets": [
        {
          "palletId": 42,
          "scannedValue": "001000000015",
          "serialNumber": "000000015",
          "quantity": 20,
          "sourceType": "PRODUCTION_LINE",
          "createdAt": "2025-01-15T10:00:00.000+02:00",
          "createdAtDisplay": "10:00 AM"
        }
      ]
    }
  ]
}
```

**Behavior change**: Cancelled pallets (`productionStatus = CANCELLED`) are now **excluded** from this response. The DTO itself was not modified — cancelled pallets are simply filtered out by the repository query.

### 6.6 SessionPalletDetail (existing DTO — no changes)

| Field              | Type   | Notes                                                       |
| ------------------ | ------ | ----------------------------------------------------------- |
| `palletId`         | Long   | **Use this as `existingPalleteId` in FaletResolutionEntry** |
| `scannedValue`     | String | 12-digit value                                              |
| `serialNumber`     | String | 9-digit serial portion                                      |
| `quantity`         | int    | Current pallet quantity                                     |
| `sourceType`       | String | e.g. "PRODUCTION_LINE"                                      |
| `createdAt`        | String | ISO-8601                                                    |
| `createdAtDisplay` | String | Human-readable time                                         |

### 6.7 LineStateResponse (existing — no changes to fields)

| Field                 | Type    | Notes                                                      |
| --------------------- | ------- | ---------------------------------------------------------- |
| `hasOpenFalet`        | boolean | **Use this to decide whether to show FALET resolution UI** |
| `lineUiMode`          | String  | Current UI mode                                            |
| `canInitiateHandover` | boolean | Whether handover can be initiated                          |
| `canConfirmHandover`  | boolean | For incoming operator                                      |
| `canRejectHandover`   | boolean | For incoming operator                                      |

---

## 7. Enums

### 7.1 HandoverFaletAction (NEW)

```
CARRY_FORWARD
USED_IN_EXISTING_SESSION_PALLETE
```

- Sent as string in JSON request body.
- Case-sensitive (uppercase with underscores, as shown).

### 7.2 PalleteProductionStatus (NEW — not directly exposed to Flutter)

```
ACTIVE
CANCELLED
```

- Not present in any Flutter-facing DTO. Cancelled pallets are simply excluded from query results.

### 7.3 FaletEventType (MODIFIED — new value added)

```
RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER  (new)
```

- Not directly exposed in Flutter-facing DTOs. For audit/tracing only.

### 7.4 ProductionCorrectionType (NEW — Thymeleaf only)

```
CANCEL
QUANTITY_EDIT
```

- Not exposed to Flutter.

---

## 8. Error Codes & Error Contract

### Standard error envelope

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "HANDOVER_FALET_DECISION_REQUIRED",
    "message": "Human-readable description",
    "details": null
  }
}
```

HTTP status is `400 Bad Request` for all business validation errors (thrown as `BusinessException`).

### Handover FALET error codes (all NEW)

| Code                                      | When                                                                                  | Suggested UX                                                                  |
| ----------------------------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `HANDOVER_FALET_DECISION_REQUIRED`        | Open FALET exists but `faletResolutions` is null/empty                                | Show "You must resolve all open FALET items before handing over"              |
| `HANDOVER_FALET_DECISION_MISSING`         | Not all open FALET IDs are covered in `faletResolutions`                              | Show "Missing decision for some FALET items" — re-fetch FALET list            |
| `HANDOVER_FALET_DECISION_DUPLICATE`       | Same `faletId` appears more than once in the list                                     | Client-side bug — should never happen with correct UI                         |
| `HANDOVER_FALET_INVALID_ACTION`           | `action` value is not recognized                                                      | Client-side bug                                                               |
| `HANDOVER_FALET_PALLETE_REQUIRED`         | `action = USED_IN_EXISTING_SESSION_PALLETE` but `existingPalleteId` is null           | Show "Select a pallet to reconcile with"                                      |
| `HANDOVER_FALET_PALLETE_NOT_FOUND`        | `existingPalleteId` references pallet that doesn't exist                              | Show "Selected pallet not found" — may have been deleted/cancelled            |
| `HANDOVER_FALET_PALLETE_WRONG_SESSION`    | Pallet exists but belongs to a different authorization/session                        | Show "Pallet is from a different session"                                     |
| `HANDOVER_FALET_PALLETE_WRONG_LINE`       | Pallet exists but belongs to a different production line                              | Show "Pallet is from a different line"                                        |
| `HANDOVER_FALET_PALLETE_CANCELLED`        | Pallet has `productionStatus = CANCELLED`                                             | Show "Pallet has been cancelled" — refresh session data                       |
| `HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH` | Pallet's product type doesn't match the FALET item's product type                     | Show "Product type mismatch" — client-side filtering should prevent this      |
| `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE` | Total reconciled qty (including prior reconciliations) would exceed pallet's quantity | Show "Pallet cannot absorb this quantity" — pick a different pallet or reduce |

### Pre-existing error codes (unchanged)

| Code                          | When                                             |
| ----------------------------- | ------------------------------------------------ |
| `LINE_NOT_FOUND`              | Invalid `lineId`                                 |
| `LINE_AUTHORIZATION_REQUIRED` | No active authorization on line                  |
| `HANDOVER_ALREADY_PENDING`    | PENDING handover already exists (different auth) |
| `PRODUCT_TYPE_NOT_FOUND`      | Invalid `lastActiveProductTypeId`                |

---

## 9. Validation Rules — Exhaustive List

These are the actual server-side validations in `LineHandoverService.createHandover()`, in execution order:

### Pre-existing validations (unchanged)

1. **Active authorization required** — line must have an active `LineAuthorization`.
2. **No conflicting pending handover** — if a PENDING handover exists for a _different_ authorization, throw error. If same authorization, replay-safe (returns existing handover).
3. **Last active product cross-validation** — if `lastActiveProductTypeId` is set, `lastActiveProductFaletQuantity` must also be set (and vice versa). Product type must exist and be active.

### New FALET resolution validations

4. **FALET decision required** — if `faletService.getOpenFaletStates(lineId)` returns non-empty and `faletResolutions` is null/empty → `HANDOVER_FALET_DECISION_REQUIRED`.

5. **No duplicate FALET IDs** — each `faletId` in `faletResolutions` must be unique → `HANDOVER_FALET_DECISION_DUPLICATE`.

6. **All FALET IDs valid** — each `faletId` must exist in the open FALET set. Invalid IDs → `HANDOVER_FALET_DECISION_MISSING`.

7. **All open FALET covered** — every open FALET must have a resolution entry. Missing → `HANDOVER_FALET_DECISION_MISSING`.

8. **Action-specific validations** (for `USED_IN_EXISTING_SESSION_PALLETE` only):
   - `existingPalleteId` must not be null → `HANDOVER_FALET_PALLETE_REQUIRED`
   - Pallet must exist → `HANDOVER_FALET_PALLETE_NOT_FOUND`
   - Pallet must belong to the **same session** (same `lineAuthorization.id`) → `HANDOVER_FALET_PALLETE_WRONG_SESSION`
   - Pallet must belong to the **same line** (`lineId`) → `HANDOVER_FALET_PALLETE_WRONG_LINE`
   - Pallet must not be `CANCELLED` → `HANDOVER_FALET_PALLETE_CANCELLED`
   - Pallet's `productType.id` must match the FALET item's `productType.id` → `HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH`
   - Total reconciled quantity for the pallet (pending request + existing DB reconciliations) must not exceed `pallet.quantity` → `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE`

**Important**: Multiple FALET items CAN be reconciled to the **same pallet** in one request. The backend accumulates quantities per pallet, then validates the total. Example: pallet with qty=20, FALET-A (qty=5) + FALET-B (qty=3) reconciled to it → total 8 ≤ 20, valid.

---

## 10. State Machine / Business Logic

### FALET item lifecycle during handover

```
OPEN FALET item
  ├── CARRY_FORWARD → remains in FALET snapshot → carried to next shift
  │   (quantity unchanged, status unchanged in falet_current_states)
  │
  └── USED_IN_EXISTING_SESSION_PALLETE → RESOLVED
      - falet_current_states.quantity set to 0
      - falet_current_states.status set to RESOLVED
      - falet_pallete_reconciliations record created
      - falet_events record with type RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER
```

### Pallet lifecycle (affected by Feature B admin corrections)

```
Pallet created (productionStatus = ACTIVE)
  ├── Normal flow: appears in session detail, counts in daily stats
  ├── Admin cancels: productionStatus = CANCELLED
  │   - Disappears from session-production-detail
  │   - Disappears from daily pallet counts
  │   - Cannot be used as reconciliation target (HANDOVER_FALET_PALLETE_CANCELLED)
  └── Admin edits qty: quantity updated, correction record saved
      - New qty must be ≥ total already-reconciled amount (floor enforced)
```

### Handover idempotency

If the operator submits the same handover request twice (same authorization), the backend detects the existing PENDING handover and returns it. This is **replay-safe**. The second submission does NOT re-process FALET resolutions — they were already processed on the first call.

---

## 11. Data Flow — Step by Step

### Happy path: Handover with FALET reconciliation

```
┌─────────────────────────────────────────────────────────┐
│ 1. Flutter: GET /lines/{lineId}/state                   │
│    → Check hasOpenFalet                                 │
├─────────────────────────────────────────────────────────┤
│ 2. If hasOpenFalet == true:                             │
│    Flutter: GET /lines/{lineId}/falet                   │
│    → Get list of open FALET items (faletId, productType,│
│      quantity, etc.)                                    │
├─────────────────────────────────────────────────────────┤
│ 3. Flutter: GET /lines/{lineId}/session-production-detail│
│    → Get session pallets grouped by product type        │
│    → Use to populate pallet selection for reconciliation│
├─────────────────────────────────────────────────────────┤
│ 4. Flutter: Show FALET resolution dialog                │
│    → For each FALET item, operator chooses:             │
│      - CARRY_FORWARD (no pallet selection needed)       │
│      - USED_IN_EXISTING_SESSION_PALLETE                 │
│        → Show pallets from SAME product type group      │
│        → Operator selects one pallet                    │
├─────────────────────────────────────────────────────────┤
│ 5. Flutter: POST /lines/{lineId}/handover               │
│    Body: { faletResolutions: [...], ... }               │
├─────────────────────────────────────────────────────────┤
│ 6. Backend validates all resolutions (see §9)           │
│    → On error: returns specific error code              │
│    → On success: processes reconciliations, creates     │
│      handover, publishes LineStateChangedEvent          │
├─────────────────────────────────────────────────────────┤
│ 7. Flutter: receives LineHandoverResponse               │
│    → Show success with reconciledFaletItems summary     │
│    → SSE event refreshes line state                     │
└─────────────────────────────────────────────────────────┘
```

### Happy path: Handover without FALET

```
┌─────────────────────────────────────────────────────────┐
│ 1. Flutter: GET /lines/{lineId}/state                   │
│    → hasOpenFalet == false                              │
├─────────────────────────────────────────────────────────┤
│ 2. Flutter: POST /lines/{lineId}/handover               │
│    Body: { notes: "...", ... }                          │
│    (no faletResolutions field needed)                   │
├─────────────────────────────────────────────────────────┤
│ 3. Backend: normal handover flow (unchanged)            │
│    → reconciledFaletItems will be empty list            │
└─────────────────────────────────────────────────────────┘
```

---

## 12. Existing Endpoints the Frontend Must Use

These endpoints already existed and are **not modified**, but the Flutter app must call them to gather data for the FALET resolution dialog:

### 12.1 Line State

```
GET /api/v1/palletizing/lines/{lineId}/state
→ LineStateResponse
```

Use `hasOpenFalet` to decide whether to show the FALET resolution dialog.

### 12.2 FALET Screen

```
GET /api/v1/palletizing/lines/{lineId}/falet
→ FaletScreenResponse
```

Returns all FALET items for the line. Use `faletItems` where `status` indicates open/unresolved items. Each item's `faletId` is what you send in `FaletResolutionEntry.faletId`.

### 12.3 Session Production Detail

```
GET /api/v1/palletizing/lines/{lineId}/session-production-detail
→ SessionProductionDetailResponse
```

Returns pallets grouped by product type for the current session. Use this to:

- Show selectable pallets when operator picks `USED_IN_EXISTING_SESSION_PALLETE`.
- **Filter by product type**: only show pallets from `groups[].productTypeId` that matches the FALET item's `productTypeId`.
- Each pallet's `palletId` is what you send in `FaletResolutionEntry.existingPalleteId`.

### 12.4 Handover Confirm / Reject (unchanged)

```
POST /api/v1/palletizing/lines/{lineId}/handover/{handoverId}/confirm
POST /api/v1/palletizing/lines/{lineId}/handover/{handoverId}/reject
```

No changes. The incoming operator confirms or rejects as before.

---

## 13. SSE / Real-Time Events

### LineStateChangedEvent

The backend publishes `LineStateChangedEvent(lineId)` when:

- A handover is created (including with FALET reconciliation).
- A pallet is cancelled via admin production corrections.

The Flutter app should already be listening for this SSE event to refresh line state. No new event types were added — the existing event is reused.

**Important for reconciliation UX**: If an admin cancels a pallet while the operator is in the FALET resolution dialog, the SSE event fires. The Flutter app should consider refreshing session-production-detail when it receives this event to avoid showing stale pallet data. However, the backend will also validate at submission time and return `HANDOVER_FALET_PALLETE_CANCELLED` if a selected pallet was cancelled between dialog display and submission.

---

## 14. Admin Web Changes (Thymeleaf — No Flutter Work)

For documentation completeness only. These are server-rendered pages:

| URL                                                           | Method | Description                           |
| ------------------------------------------------------------- | ------ | ------------------------------------- |
| `/web/admin/production-corrections`                           | GET    | Search pallets by scanned value       |
| `/web/admin/production-corrections/{palleteId}`               | GET    | Pallet detail with correction history |
| `/web/admin/production-corrections/{palleteId}/cancel`        | POST   | Cancel a pallet creation              |
| `/web/admin/production-corrections/{palleteId}/edit-quantity` | POST   | Edit pallet quantity                  |

Additionally:

- **Handover detail page** (`/web/admin/handovers/{id}`) now shows a "Reconciled FALET Items" section.
- **Pallet detail page** (`/web/admin/palletes/{id}`) now shows reconciliation info if any exists.
- **Admin nav** includes a "Production Corrections" link.

---

## 15. Known Gaps / Mismatches

### 15.1 No `productTypeId` in `SessionPalletDetail`

The `SessionPalletDetail` DTO does **not** include a `productTypeId` field. However, pallets are already grouped by product type in `SessionProductionDetailResponse.groups[]`. The frontend must use the parent `ProductTypeGroup.productTypeId` to determine which pallets match a given FALET item's product type. This is not a bug — it's by design (the grouping provides the type context).

### 15.2 No `productionStatus` in `SessionPalletDetail`

The `SessionPalletDetail` DTO does not expose `productionStatus`. Cancelled pallets are excluded at the query level, so Flutter will never see them in the response. If an admin cancels a pallet between when Flutter loaded the list and when the operator submits the handover, the backend returns `HANDOVER_FALET_PALLETE_CANCELLED`. The frontend should handle this error by refreshing the pallet list.

### 15.3 No dedicated "eligible pallets for reconciliation" endpoint

There is no new endpoint specifically for fetching pallets eligible for FALET reconciliation. The frontend uses the existing `session-production-detail` endpoint and filters client-side by product type group. The backend validates everything server-side, so the frontend filtering is purely for UX (showing only relevant pallets).

### 15.4 No reconciliation quantity accumulation visibility

When multiple FALET items target the same pallet, the frontend has no way to know how much "remaining capacity" the pallet has for reconciliation (i.e., `pallet.quantity - sum(existing reconciliations)`). The `SessionPalletDetail.quantity` field is the **total** pallet quantity, not the remaining available. The backend validates the total at submission time. For a better UX, the frontend could track accumulated quantities client-side during the dialog (summing FALET quantities assigned to each pallet) but cannot know about prior reconciliations from previous handovers. In practice, for the first implementation, this is unlikely to be an issue since reconciliation is done once at handover time for the current session's pallets.

### 15.5 FALET items filtering for "open" status

The `FaletScreenResponse.faletItems` returns **all** FALET items for the line, not just open ones. The frontend should filter for items with `status` indicating they are open/unresolved. The `totalOpenFaletCount` and `hasOpenFalet` fields reflect only open items. The FALET resolution dialog should only show items that are not already resolved.

### 15.6 Production corrections are Thymeleaf-only

The plan originally envisioned REST API endpoints for production corrections. The actual implementation provides only Thymeleaf server-rendered pages. If Flutter needs correction capabilities in the future, new API endpoints would need to be added.

---

## 16. Recommended Flutter Implementation Order

### Phase 1: Data models

1. Add `HandoverFaletAction` enum: `CARRY_FORWARD`, `USED_IN_EXISTING_SESSION_PALLETE`.
2. Add `FaletResolutionEntry` model: `faletId`, `action`, `existingPalleteId`.
3. Update `LineHandoverRequest` model: add optional `faletResolutions` list.
4. Add `ReconciledFaletItem` model: `faletId`, `palleteId`, `scannedValue`, `productTypeId`, `productTypeName`, `reconciledQuantity`.
5. Update `LineHandoverResponse` model: add `reconciledFaletItems` list.

### Phase 2: Handover flow modification

6. Before initiating handover, check `LineStateResponse.hasOpenFalet`.
7. If `hasOpenFalet` is `true`:
   - Fetch FALET items: `GET /lines/{lineId}/falet`.
   - Fetch session pallets: `GET /lines/{lineId}/session-production-detail`.
   - Show FALET resolution dialog (see Phase 3).
   - Collect resolutions and include in handover request.
8. If `hasOpenFalet` is `false`: proceed with handover as before (no changes).

### Phase 3: FALET resolution dialog UI

9. List all **open** FALET items from the FALET screen response.
10. For each item, show:
    - Product type name and FALET quantity.
    - Toggle/radio: "Carry Forward" vs "Reconcile to Pallet".
11. When "Reconcile to Pallet" is selected:
    - Show pallets from the matching `ProductTypeGroup` in session production detail.
    - Display pallet scanned value, quantity, and creation time.
    - Allow single-pallet selection per FALET item.
12. Validate locally before submission:
    - All FALET items have a decision.
    - Reconciliation targets have a selected pallet.
    - (Optional) Warn if accumulated reconciliation quantity approaches pallet capacity.

### Phase 4: Error handling

13. Handle all new error codes from §8.
14. On `HANDOVER_FALET_PALLETE_CANCELLED` or `HANDOVER_FALET_PALLETE_NOT_FOUND`: refresh session data and re-show dialog.
15. On `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE`: notify user and let them pick a different pallet.
16. On `HANDOVER_FALET_DECISION_REQUIRED`: should not happen if flow is correct, but show FALET resolution dialog as fallback.

### Phase 5: Success display

17. After successful handover, optionally show `reconciledFaletItems` summary (which FALET items were reconciled to which pallets).
18. Refresh line state via SSE or explicit re-fetch.

---

## Appendix: Quick Reference — Field Mappings

| FALET Resolution Dialog needs       | Source endpoint                     | Source field                                                        |
| ----------------------------------- | ----------------------------------- | ------------------------------------------------------------------- |
| FALET item ID                       | `GET .../falet`                     | `faletItems[].faletId`                                              |
| FALET product type                  | `GET .../falet`                     | `faletItems[].productTypeId` / `.productTypeName`                   |
| FALET quantity                      | `GET .../falet`                     | `faletItems[].quantity`                                             |
| Whether FALET exists                | `GET .../state`                     | `hasOpenFalet`                                                      |
| Pallet ID for reconciliation        | `GET .../session-production-detail` | `groups[].pallets[].palletId`                                       |
| Pallet product type (for filtering) | `GET .../session-production-detail` | `groups[].productTypeId`                                            |
| Pallet display info                 | `GET .../session-production-detail` | `groups[].pallets[].scannedValue`, `.quantity`, `.createdAtDisplay` |
