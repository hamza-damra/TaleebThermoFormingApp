# Handover Final Alignment — Backend Summary

## Overview

This document summarizes the complete backend implementation for the per-line handover (`LineHandover`) system, aligned with the final agreed business design. The core pallet-formation (تكوين المشاتيح) workflow uses per-line handovers with operator PIN authentication, loose balance tracking, and admin dispute resolution.

---

## State Machine

```
                  ┌─────────┐
    create ──────>│ PENDING │
                  └────┬────┘
                       │
              ┌────────┼────────┐
              │                 │
         confirm            reject
              │                 │
       ┌──────▼──────┐  ┌──────▼──────┐
       │  CONFIRMED  │  │  REJECTED   │
       └─────────────┘  └──────┬──────┘
                               │
                          admin resolve
                               │
                        ┌──────▼──────┐
                        │  RESOLVED   │
                        └─────────────┘
```

**Terminal states:** CONFIRMED, RESOLVED

| Transition | Actor | Effect |
|-----------|-------|--------|
| PENDING → CONFIRMED | Incoming operator (after PIN auth) | Loose balances transferred to incoming session |
| PENDING → REJECTED | Incoming operator (after PIN auth) | NO transfer; escalated to admin as dispute |
| REJECTED → RESOLVED | Admin user via web panel | Admin closes the dispute with resolution notes |

---

## What Happens at Each Step

### 1. Outgoing operator creates handover

- Outgoing operator presses "تسليم مناوبة" on the line
- Chooses one of 4 cases: no items, incomplete pallet only, loose balances only, or both
- Backend validates the request:
  - If incomplete pallet product type is set, quantity must be > 0
  - If quantity is set, product type is required
- Incomplete pallet fields are stored directly on `LineHandover` (at most one)
- Loose balances are auto-populated from the outgoing operator's `SessionProductBalance` rows (only those with `loosePackageCount > 0`)
- Outgoing authorization is immediately **RELEASED** with reason `HANDOVER_CREATED`
- Line enters PENDING state — production is **blocked**
- Backend returns the handover with `status=PENDING` and computed `handoverType`

### 2. Incoming operator authorizes

- Line is in `PENDING_HANDOVER_NEEDS_INCOMING` mode — frontend shows PIN overlay
- Incoming operator enters their 4-digit PIN → creates a new `LineOperatorAuthorization` (ACTIVE)
- Line transitions to `PENDING_HANDOVER_REVIEW` mode
- `canConfirmHandover=true` and `canRejectHandover=true` are set in the response
- Production remains blocked until confirm/reject

### 3. Incoming operator confirms

- `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm`
- Requires active authorization on the line
- Sets incoming operator identity on the handover
- Status → `CONFIRMED`, `confirmedAt` set
- Loose balances from the handover are **transferred** (additively merged) into the incoming operator's `SessionProductBalance` rows
- Line unblocks — production can resume

### 4. Incoming operator rejects

- `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`
- Requires active authorization on the line
- Sets incoming operator identity on the handover
- Status → `REJECTED`, `rejectedAt` set, optional `rejectionNotes` stored
- **NO loose balances or incomplete pallet data are transferred** to the incoming session
- The handover becomes visible to admins in the dispute panel
- Line unblocks — incoming operator can continue production normally

### 5. Admin resolves dispute

- `POST /web/admin/line-handover-disputes/{id}/resolve`
- Only REJECTED handovers can be resolved
- Admin provides optional `resolutionNotes`
- Status → `RESOLVED`, `resolvedAt` set, `resolvedByUser` recorded

---

## How Incomplete Pallets Are Stored

Stored directly as columns on `line_handovers`:
- `incomplete_pallet_product_type_id` — FK to `product_types`
- `incomplete_pallet_quantity` — integer count
- `incomplete_pallet_scanned_value` — optional 12-digit scanned value
- `incomplete_pallet_product_type_name_snapshot` — name at time of handover

**At most ONE incomplete pallet per handover** (business rule).

## How Loose Balances Are Stored

Stored as child rows in `line_handover_loose_balances`:
- `handover_id` — FK to `line_handovers`
- `product_type_id` — FK to `product_types`
- `product_type_name_snapshot` — name at time of handover
- `loose_package_count` — integer count

Unique constraint: one row per (handover, product_type). Multiple product types supported per handover.

**Source of truth:** When `includeLooseBalances=true`, the backend reads all `SessionProductBalance` rows for the outgoing authorization and includes those with `loosePackageCount > 0`.

## How Disputes/Escalations Are Handled

- Rejection creates a `REJECTED` handover with full audit trail
- `rejection_notes` stores the incoming operator's reason
- Admin web panel (`/web/admin/line-handover-disputes`) shows REJECTED + RESOLVED handovers
- Admin can view full details: outgoing data, incoming rejection, timestamps, operators, line
- Admin resolves with `resolution_notes` and their `user_id` is recorded
- `resolvedAt` timestamp provides full traceability

---

## Data Model

### Tables

| Table | Purpose |
|-------|---------|
| `line_handovers` | Per-line handover records with full audit fields |
| `line_handover_loose_balances` | Child table for loose balance rows per handover |
| `line_operator_authorizations` | PIN-based operator sessions per line |
| `session_product_balances` | Loose balance tracking per authorization session |
| `operators` | Operator identity with PIN hash |
| `production_lines` | Factory production lines |

### Key Constraints

- `uk_line_handover_one_pending_per_line` — generated `pending_lock` column ensures at most ONE pending handover per line
- `uk_handover_balance_handover_product` — one loose balance row per product type per handover
- `uk_line_auth_one_active_per_line` — at most one active authorization per line

### Flyway Migrations

| Migration | Content |
|-----------|---------|
| V21 | `line_handovers` + `line_handover_loose_balances` tables |
| V23 | `rejection_notes`, `resolution_notes`, `resolved_by_user_id`, `resolved_at` columns + status index |

---

## Enum: `LineHandoverStatus`

| Value | Arabic | English | Meaning |
|-------|--------|---------|---------|
| `PENDING` | قيد الانتظار | Pending | Awaiting incoming operator |
| `CONFIRMED` | مؤكد | Confirmed | Incoming accepted |
| `REJECTED` | مرفوض | Rejected | Incoming rejected → escalated to admin |
| `RESOLVED` | تم الحل | Resolved | Admin resolved the dispute |

---

## DTOs / Endpoints

### Handover Creation

**Endpoint:** `POST /api/v1/palletizing-line/lines/{lineId}/handover`

**Request (`LineHandoverRequest`):**
```json
{
  "incompletePalletProductTypeId": 5,
  "incompletePalletQuantity": 25,
  "incompletePalletScannedValue": "000100000001",
  "includeLooseBalances": true,
  "notes": "End of shift notes"
}
```

All fields optional. The 4 cases:
- **NONE:** all fields null/absent
- **INCOMPLETE_PALLET_ONLY:** pallet fields set, `includeLooseBalances` absent/false
- **LOOSE_BALANCES_ONLY:** pallet fields absent, `includeLooseBalances=true`
- **BOTH:** pallet fields set AND `includeLooseBalances=true`

### Handover Response (`LineHandoverResponse`)

Key fields: `id`, `lineId`, `lineName`, `status`, `statusDisplayNameAr`, `outgoingOperatorName`, `outgoingOperatorId`, `incomingOperatorName`, `incomingOperatorId`, `incompletePallet` (nested), `looseBalances` (list), `looseBalanceCount`, `handoverType`, `notes`, `createdAt`, `confirmedAt`, `rejectedAt`, `rejectionNotes`, `resolutionNotes`, `resolvedByUserName`, `resolvedAt` + display variants.

### Line State (`LineStateResponse`)

Key fields: `lineId`, `lineName`, `lineNumber`, `authorized`, `authorization`, `sessionTable`, `blocked`, `blockedReason`, `pendingHandover` (summary), `lineUiMode`, `canInitiateHandover`, `canConfirmHandover`, `canRejectHandover`.

**`lineUiMode` values:**

| Mode | Meaning | Handover actions available |
|------|---------|--------------------------|
| `NEEDS_AUTHORIZATION` | No operator; show PIN | None |
| `AUTHORIZED` | Normal production | Can initiate handover |
| `PENDING_HANDOVER_NEEDS_INCOMING` | Outgoing left; waiting for incoming PIN | None (show PIN overlay) |
| `PENDING_HANDOVER_REVIEW` | Incoming authorized; pending handover visible | Confirm / Reject |

**`LineHandoverSummary`** (inside `pendingHandover`): `handoverId`, `outgoingOperatorName`, `status`, `looseBalanceCount`, `hasIncompletePallet`, `incompletePalletProductTypeName`, `createdAtDisplay`, `notes`, `handoverType`.

### Other Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /lines/{lineId}/handover/{id}/confirm` | Incoming confirms handover |
| `POST /lines/{lineId}/handover/{id}/reject` | Incoming rejects (optional body: `{ "notes": "..." }`) |
| `GET /lines/{lineId}/handover/pending` | Get pending handover for a line |
| `POST /lines/{lineId}/authorize-pin` | Authorize with PIN |
| `GET /lines/{lineId}/state` | Full line state |

---

## Error Codes

| Code | Meaning |
|------|---------|
| `PENDING_LINE_HANDOVER_EXISTS` | A pending handover already exists for this line |
| `LINE_HANDOVER_NOT_FOUND` | Handover not found |
| `LINE_HANDOVER_ALREADY_RESOLVED` | Handover already confirmed/rejected |
| `LINE_HANDOVER_NOT_REJECTED` | Admin tried to resolve non-REJECTED handover |
| `LINE_NOT_AUTHORIZED` | No active authorization on line |
| `LINE_BLOCKED_BY_PENDING_HANDOVER` | Production blocked by pending handover |
| `VALIDATION_ERROR` | Incomplete pallet fields inconsistent |

---

## Services

| Service | Role |
|---------|------|
| `LineHandoverService` | Create/confirm/reject handover, resolve dispute, get disputes |
| `LineStateService` | Compute `lineUiMode` and all per-line UI flags |
| `LineAuthorizationService` | PIN verification → authorization creation/release |
| `LineProductionGuard` | Precondition checks for production operations |
| `LineHandoverGuardSupport` | Blocks production when pending handover exists |
| `ProductSwitchService` | Records loose balances on product switch |

---

## Admin Web Pages

**Controller:** `WebAdminLineHandoverDisputesController` at `/web/admin/line-handover-disputes`

| Route | Purpose |
|-------|---------|
| `GET /` | Paginated list of REJECTED + RESOLVED handovers |
| `GET /{id}` | Detail view with all handover data |
| `POST /{id}/resolve` | Admin resolves a REJECTED dispute |

---

## Tests

### `LineHandoverServiceTest` (20 tests)

- Create handover: NONE, INCOMPLETE_PALLET_ONLY, LOOSE_BALANCES_ONLY, BOTH cases
- Skip zero loose balances
- Release outgoing authorization on create
- Reject when pending already exists
- Confirm: sets incoming operator, transfers loose balances (new + merge)
- Confirm: guards (already resolved, line mismatch)
- Reject: without notes, with notes, no transfer, tracks for admin
- Incoming authorization required for confirm and reject
- Resolve dispute: happy path, non-REJECTED guard

### `LineStateServiceTest` (7 tests)

- `NEEDS_AUTHORIZATION` mode (no auth, no handover)
- `AUTHORIZED` mode (auth, no handover, canInitiateHandover=true)
- `PENDING_HANDOVER_NEEDS_INCOMING` mode (no auth, pending handover, canConfirm/Reject=false)
- `PENDING_HANDOVER_REVIEW` mode (auth + pending handover, canConfirm/Reject=true)
- Handover summary with incomplete pallet (handoverType=INCOMPLETE_PALLET_ONLY)
- Handover summary with loose balances (handoverType=LOOSE_BALANCES_ONLY)
- Production line not found error

---

## Concurrency

All state-change methods use `SELECT ... FOR UPDATE` via native queries:
- `findByProductionLineIdAndStatusForUpdate()` — prevents duplicate pending handovers
- `findByIdForUpdate()` — prevents race conditions on confirm/reject/resolve
- `pending_lock` generated column with unique constraint — DB-level enforcement of one pending per line

---

## What Does NOT Exist in the Backend

- No generic "change operator" action as the primary exit path (the `DELETE /authorization` endpoint exists for admin/emergency use only — the frontend must NOT show it as a primary action)
- No processing of handover before incoming operator authorization
- No transfer of items on reject
- No ambiguous handover data — incomplete pallet and loose balances are clearly separated
