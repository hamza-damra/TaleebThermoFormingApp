# FALET Workflow Deep Analysis

## 1. Scope and Source of Truth

### What Was Inspected

The following sources were examined in full for this document:

- **Backend Java source** — `FaletService`, `LineHandoverService`, `FaletDisputeService`, `ProductSwitchService`, `LineStateService` (FALET fields), all FALET-related JPA entities, repositories, enums, DTOs, controller classes, `ErrorCode.java`, `GlobalExceptionHandler` entries, `@Transactional` annotations, and pessimistic-lock queries.
- **Database schema** — All 39 Flyway migration files (V0_1 through V39). Specifically detailed analysis of V21, V23, V29, V35, V37, V38.
- **Web admin layer** — `WebAdminFaletDisputesController`, `WebAdminLineHandoverDisputesController` (legacy redirect), `WebAdminLineStateController`, `WebAdminPalleteController`, and all corresponding Thymeleaf templates.
- **Project documentation** — `docs/FALET_LIFECYCLE_DISPUTES_FRONTEND_SPEC.md`, `docs/FALET_REDESIGN_FRONTEND_HANDOFF.md`, `HANDOVER_REJECTION_AND_RECEIPT_NOTES_FRONTEND_SPEC.md`, `FRONTEND_AI_AGENT_HANDOFF.md`, `docs/FRONTEND_API_CONTRACT_HANDOVER_REVIEW.md`, and other handoff documents.
- **Flutter app** — No Flutter `.dart` source files exist in this repository. All Flutter-side contract information is derived exclusively from backend specification handoff documents.

### Precedence Rule Applied

**Code over docs.** Where specification documents and source code contradict each other, this document follows the source code. All inferences from docs without confirming code are explicitly marked.

### Critical Mismatch Summary (prominent up-front)

The single most important mismatch is:

> **The `faletResolutions` array requirement was added to `LineHandoverService.createHandover()` on the backend. The Flutter palletizing app has no source code in this repository to confirm it has been updated. Handoff documentation (`FRONTEND_AI_AGENT_HANDOFF.md`) explicitly marks "Handover-time FALET reconciliation" as the most critical Flutter feature "requiring implementation."** This is the root cause of the reported runtime failure pattern (see §15).

---

## 2. FALET Domain Definition in the Current System

### Business Meaning

**FALET** (Arabic: فالت, "loose/escaped") represents **cartons that have been physically produced but have not been assigned to a completed registered pallet**. They exist in a liminal state: physically real, but not yet in the warehouse tracking system as a scannable pallet.

FALET cartons arise from two real-world scenarios:

1. **Product switch mid-production**: An operator was producing Product A, built 7 cartons, then switched to Product B. Those 7 cartons are FALET — they were counted by the operator but not yet constituted into a pallet.
2. **End-of-shift last active product**: As an operator ends their shift, they declare how many cartons remain from the product they were last producing. These become FALET inherited by (or resolved before) the handover.

### How FALET Differs from Related Concepts

| Concept                        | Definition                           | Persistence                    | Represented by                                              |
| ------------------------------ | ------------------------------------ | ------------------------------ | ----------------------------------------------------------- |
| **FALET**                      | Produced cartons not yet in a pallet | Line-scoped, survives sessions | `falet_current_states`                                      |
| **Loose balance** (legacy)     | Pre-V29 equivalent concept           | Session-scoped only            | `line_handover_loose_balances` (deprecated)                 |
| **Incomplete pallet** (legacy) | Pre-V29 started pallet fields        | Inline on handover row         | Fields in `line_handovers` (deprecated)                     |
| **Normal production pallet**   | Registered, crated, scanned pallet   | Warehouse system               | `palletes` table                                            |
| **Zero-quantity FALET**        | FALET that has been resolved         | Historical only                | `falet_current_states` with `status=RESOLVED`, `quantity=0` |

The key architectural difference from the legacy model: FALET is **line-scoped and session-independent**. A FALET created in one authorization session persists across shifts until it is either converted to a pallet, disposed, or resolved via a dispute. The old `session_product_balances` and `session_incomplete_pallets` tables were migrated into `falet_current_states` by V29.

---

## 3. Data Model and Persistence

### Primary Tables

#### `falet_current_states` — Operational truth of all FALET

| Column                       | Type                                       | Notes                                                                                 |
| ---------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------- |
| `id`                         | BIGINT PK                                  | Auto-increment                                                                        |
| `production_line_id`         | BIGINT FK → `production_lines`             | Line the FALET belongs to                                                             |
| `product_type_id`            | BIGINT FK → `product_types`                | The product type of these cartons                                                     |
| `quantity`                   | INT DEFAULT 0                              | Current unresolved carton count                                                       |
| `product_type_name_snapshot` | VARCHAR(500)                               | Denormalized product name                                                             |
| `authorization_id`           | BIGINT FK → `line_operator_authorizations` | Authorization session that created it (added V35)                                     |
| `origin_type`                | VARCHAR(30)                                | `PRODUCT_SWITCH`, `HANDOVER_LAST_ACTIVE`, `RECEIVED_FROM_HANDOVER`, `DISPUTE_RELEASE` |
| `status`                     | VARCHAR(20) DEFAULT 'OPEN'                 | `OPEN`, `DISPUTED`, `RESOLVED`                                                        |
| `created_at`, `updated_at`   | TIMESTAMP(3)                               | Managed by Hibernate                                                                  |

**Indexes**: `idx_fcs_line_status` on `(production_line_id, status)`, `idx_fcs_line_product` on `(production_line_id, product_type_id)`.

**Important**: There is **no DB-level UNIQUE constraint** enforcing one OPEN FALET per `(line, product_type)`. This invariant is enforced at application level via **SELECT … FOR UPDATE** + session-scoped merge logic. Multiple OPEN FALET rows for the same `(line, product_type)` CAN exist if they originate from different `authorization_id` values (different operator sessions).

JPA Entity: `FaletCurrentState`, package `ps.taleeb.taleebbackend.palletizing`.

---

#### `falet_events` — Immutable audit trail

| Column                   | Type           | Notes                                                    |
| ------------------------ | -------------- | -------------------------------------------------------- |
| `id`                     | BIGINT PK      |                                                          |
| `falet_current_state_id` | BIGINT NULL FK | Links to the state row (nullable for historical orphans) |
| `production_line_id`     | BIGINT FK      | Redundant denormalization for fast querying              |
| `product_type_id`        | BIGINT FK      |                                                          |
| `authorization_id`       | BIGINT FK      | Which operator session emitted this event                |
| `event_type`             | VARCHAR(50)    | See `FaletEventType` enum (18 values)                    |
| `quantity_delta`         | INT            | Amount changed (positive or negative)                    |
| `quantity_after`         | INT            | Quantity after the event                                 |
| `source_handover_id`     | BIGINT NULL FK | If event relates to a handover                           |
| `related_pallete_id`     | BIGINT NULL FK | If event relates to pallet creation                      |
| `actor_operator_id`      | BIGINT NULL FK |                                                          |
| `notes`                  | TEXT NULL      |                                                          |
| `created_at`             | TIMESTAMP(3)   |                                                          |

**Append-only**: no UPDATE operations ever touch this table. JPA Entity: `FaletEvent`.

**`FaletEventType` enum (18 values)**:

```
RECORDED_FROM_PRODUCT_SWITCH
RECORDED_FROM_HANDOVER_LAST_ACTIVE
MERGED_WITH_EXISTING
RECEIVED_FROM_HANDOVER
HANDED_OVER_OUT
CONVERTED_TO_PALLET
DISPOSED
ADJUSTED
DISPUTE_REFERENCE
DISPUTE_HELD
DISPUTE_DISPOSED
DISPUTE_PALLETIZED
DISPUTE_RELEASED
DISPUTE_KEPT_ON_HOLD
DISPUTE_FULLY_RESOLVED
RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER
```

---

#### `falet_source_segments` — Per-operator attribution

Tracks which portion of a FALET row came from which operator authorization session, enabling accurate attribution in pallets and analytics.

| Column                   | Type                                       | Notes                                     |
| ------------------------ | ------------------------------------------ | ----------------------------------------- |
| `id`                     | BIGINT PK                                  |                                           |
| `falet_state_id`         | BIGINT FK → `falet_current_states`         |                                           |
| `authorization_id`       | BIGINT FK → `line_operator_authorizations` |                                           |
| `operator_id`            | BIGINT FK → `operators`                    |                                           |
| `quantity`               | INT                                        | How many cartons contributed by this auth |
| `origin_type`            | VARCHAR(30)                                | Origin classification                     |
| `operator_name_snapshot` | VARCHAR(255)                               |                                           |
| `notes`                  | VARCHAR(500) NULL                          |                                           |
| `created_at`             | TIMESTAMP(3)                               |                                           |

JPA Entity: `FaletSourceSegment`.

---

#### `line_handover_falet_snapshots` — Handover-time FALET snapshot

One row per `(handover_id, product_type_id)`. Records the FALET items that were carried forward (not reconciled) at handover creation time.

| Column                       | Type                                           | Notes                                                            |
| ---------------------------- | ---------------------------------------------- | ---------------------------------------------------------------- |
| `id`                         | BIGINT PK                                      |                                                                  |
| `handover_id`                | BIGINT FK → `line_handovers` ON DELETE CASCADE |                                                                  |
| `falet_current_state_id`     | BIGINT NULL FK → `falet_current_states`        | Link to live FALET state                                         |
| `product_type_id`            | BIGINT FK                                      |                                                                  |
| `product_type_name_snapshot` | VARCHAR(500)                                   |                                                                  |
| `quantity`                   | INT                                            | Carton count at handover time                                    |
| `observed_quantity`          | INT NULL                                       | Incoming operator's observed count (added V37, set on rejection) |
| `is_last_active_product`     | TINYINT(1) DEFAULT 0                           | Flag for the declared last-active product                        |
| `created_at`                 | TIMESTAMP(3)                                   |                                                                  |

**Unique constraint**: `uk_lhfs_handover_product` on `(handover_id, product_type_id)`.

JPA Entity: `LineHandoverFaletSnapshot`.

---

#### `falet_disputes`, `falet_dispute_items`, `falet_dispute_actions` — Dispute resolution tables

Created when an incoming operator rejects a handover.

**`falet_disputes`**:

| Column                                                       | Type                         | Notes                                                |
| ------------------------------------------------------------ | ---------------------------- | ---------------------------------------------------- |
| `id`                                                         | BIGINT PK                    |                                                      |
| `handover_id`                                                | BIGINT FK → `line_handovers` | 1:1 relationship — one dispute per rejected handover |
| `production_line_id`                                         | BIGINT FK                    |                                                      |
| `status`                                                     | VARCHAR(20)                  | `OPEN`, `PARTIALLY_RESOLVED`, `RESOLVED`             |
| `total_disputed_qty`                                         | INT                          | Sum of all snapshot quantities at rejection time     |
| `disposed_qty`, `palletized_qty`, `released_qty`, `held_qty` | INT                          | Running totals per action type                       |
| `rejection_incorrect_quantity`                               | BOOLEAN                      | Structured rejection reason (V37)                    |
| `rejection_other_reason`                                     | BOOLEAN                      | Structured rejection reason (V37)                    |
| `rejection_other_reason_notes`                               | TEXT NULL                    | (V37)                                                |
| `rejection_notes`                                            | TEXT NULL                    | Legacy concatenated notes                            |
| `resolution_notes`                                           | TEXT NULL                    | Admin notes when resolved                            |
| `resolved_by_user_id`                                        | BIGINT NULL FK → `users`     | Admin who resolved                                   |
| `resolved_at`                                                | TIMESTAMP(3) NULL            |                                                      |
| `created_at`, `updated_at`                                   | TIMESTAMP(3)                 |                                                      |

**Indexes**: `idx_fd_handover`, `idx_fd_status`, `idx_fd_line_status`.

**`falet_dispute_items`**: One row per FALET product type in the dispute. Links back to `falet_current_state_id`. Has `disputed_quantity`, `remaining_quantity`, nullable `observed_quantity`. Unique constraint on `(dispute_id, falet_current_state_id)`.

**`falet_dispute_actions`**: Append-only audit of each admin action. Has `action_type` (`DISPOSE`, `PALLETIZE`, `RELEASE`, `HOLD`), `quantity`, optional `pallete_id`, `fresh_quantity_added`, `active_authorization_id`, `performed_by_user_id`.

---

#### `falet_pallete_reconciliations` — FALET-to-existing-pallet assignment at handover

Created when the outgoing operator indicates a FALET was already consumed in a pallet they produced in the same session.

| Column                            | Type                           | Notes                         |
| --------------------------------- | ------------------------------ | ----------------------------- |
| `id`                              | BIGINT PK                      |                               |
| `falet_current_state_id`          | BIGINT FK                      | Which FALET                   |
| `pallete_id`                      | BIGINT FK                      | Which pallet                  |
| `reconciled_quantity`             | INT                            | How many cartons              |
| `authorization_id`, `operator_id` | BIGINT FK                      | Who reconciled                |
| `operator_name_snapshot`          | VARCHAR(255)                   |                               |
| `handover_id`                     | BIGINT NULL FK                 | Which handover triggered this |
| `source`                          | VARCHAR(30) DEFAULT 'HANDOVER' | Always `HANDOVER` currently   |
| `reconciled_at`, `created_at`     | TIMESTAMP(6)                   |                               |

JPA Entity: `FaletPalleteReconciliation`. Repository: `FaletPalleteReconciliationRepository`.

---

### Legacy Tables (Schema present, not primary data path)

- `line_handover_loose_balances` (V21): Pre-V29 loose balance snapshots. Table exists in schema but application no longer writes to it.
- Legacy inline fields on `line_handovers`: `incomplete_pallet_product_type_id`, `incomplete_pallet_quantity`, `incomplete_pallet_scanned_value`, `incomplete_pallet_product_type_name_snapshot`. Present in schema but not used by current services.

---

### Enums Summary

| Enum Class               | Values                                                                                |
| ------------------------ | ------------------------------------------------------------------------------------- |
| `FaletCurrentStatus`     | `OPEN`, `DISPUTED`, `RESOLVED`                                                        |
| `FaletOriginType`        | `PRODUCT_SWITCH`, `HANDOVER_LAST_ACTIVE`, `RECEIVED_FROM_HANDOVER`, `DISPUTE_RELEASE` |
| `FaletDisputeStatus`     | `OPEN`, `PARTIALLY_RESOLVED`, `RESOLVED`                                              |
| `FaletDisputeActionType` | `DISPOSE`, `PALLETIZE`, `RELEASE`, `HOLD`                                             |
| `HandoverFaletAction`    | `CARRY_FORWARD`, `USED_IN_EXISTING_SESSION_PALLETE`                                   |
| `FaletEventType`         | 18 values (listed above)                                                              |

---

## 4. Entry Points Where FALET Is Created or Affected

### 4.1 Product Switch

**Source workflow**: Operator on palletizing/thermoforming app switches from Product A to Product B.

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/product-switch`

**Service method**: `ProductSwitchService.recordProductSwitch(Long lineId, Long previousProductTypeId, Long newProductTypeId, Integer faletQuantity)`

**Key logic**:

1. Validates `previousProductTypeId` matches `line.currentProductType` → throws `CURRENT_PRODUCT_MISMATCH` otherwise.
2. Validates new product ≠ current product → throws `PRODUCT_TYPE_SWITCH_SAME_PRODUCT`.
3. If `faletQuantity > 0`: calls `FaletService.recordFaletFromProductSwitch(lineId, previousProductTypeId, faletQuantity, auth)`.
4. Updates `line.currentProductType = newProductType`.
5. Publishes `LineStateChangedEvent`.

**Resulting DB changes** (when faletQuantity > 0):

- INSERT INTO `falet_current_states` (new FALET with `status=OPEN`, `originType=PRODUCT_SWITCH`) **OR** UPDATE existing row's `quantity` (session-scoped merge).
- INSERT INTO `falet_events` (event type `RECORDED_FROM_PRODUCT_SWITCH` and optionally `MERGED_WITH_EXISTING`).
- INSERT INTO `falet_source_segments`.

**Emitted events**: `LineStateChangedEvent` → triggers SSE update to all `/line-state/stream` listeners.

**Line state impact**: `hasOpenFalet=true`, `openFaletCount` incremented.

---

### 4.2 Select Product (first-time)

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/select-product`

**Service method**: `ProductSwitchService.selectProduct(Long lineId, Long productTypeId)`

**No FALET impact.** This endpoint only sets `line.currentProductType`. Throws `PRODUCT_ALREADY_SELECTED` if a product is already set. Publishes `LineStateChangedEvent`.

---

### 4.3 Handover Creation (outgoing operator)

**Source workflow**: Outgoing operator initiates end-of-shift handover on the app.

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/handover`

**Service method**: `LineHandoverService.createHandover(Long lineId, LineHandoverRequest request)`

**Step-by-step logic**:

1. **Record last-active FALET** (if `request.lastActiveProductTypeId` is set):

   ```
   FaletService.recordFaletFromHandoverLastActive(lineId, lastActiveProductTypeId,
       lastActiveProductFaletQuantity, outgoingAuth)
   ```

   This performs session-scoped merge into `falet_current_states` (same mechanism as product switch merge).

2. **Load all OPEN FALET** after last-active recording:

   ```
   List<FaletCurrentState> openFaletItems = faletService.getOpenFaletStates(lineId)
   ```

   This is the set that MUST be covered by `faletResolutions`.

3. **Validate FALET decisions** (if `openFaletItems` is non-empty):
   - If `request.faletResolutions` is null or empty → throw `HANDOVER_FALET_DECISION_REQUIRED`
   - If duplicate `faletId` values in `faletResolutions` → throw `HANDOVER_FALET_DECISION_DUPLICATE`
   - If any open FALET not covered → throw `HANDOVER_FALET_DECISION_MISSING`

4. **Process each resolution entry**:

   **`CARRY_FORWARD`**:
   - Creates `LineHandoverFaletSnapshot` for this FALET item.
   - Event: `HANDED_OVER_OUT`.
   - FALET remains OPEN (status unchanged).

   **`USED_IN_EXISTING_SESSION_PALLETE`**:
   - Validates: pallet exists, same session/auth, same line, not CANCELLED, same product type, total reconciled qty ≤ pallet qty.
   - Creates `FaletPalleteReconciliation`.
   - Sets FALET `status = RESOLVED`, `quantity = 0`.
   - Event: `RECONCILED_TO_EXISTING_PALLETE_AT_HANDOVER`.

5. **Release outgoing authorization**: `status = RELEASED`, `releaseReason = HANDOVER_CREATED`.

6. **Persist handover** with `status = PENDING`.

7. **Publish** `LineStateChangedEvent`.

**Resulting DB changes**:

- 0..N `line_handover_falet_snapshots` inserts.
- 0..N `falet_pallete_reconciliations` inserts (for USED_IN_EXISTING_SESSION_PALLETE).
- 0..N `falet_current_states` updates (status=RESOLVED for reconciled items).
- 0..N `falet_events` inserts.
- 1 `line_handovers` insert (status=PENDING).
- 1 `line_operator_authorizations` update (status=RELEASED).

---

### 4.4 Handover Confirmation (incoming operator)

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}/confirm`

**Service method**: `LineHandoverService.confirmHandover(Long lineId, Long handoverId, LineHandoverConfirmRequest request)`

**FALET impact**:

- **No FALET status changes.** Carry-forward FALET items remain OPEN.
- Sets `handover.status = CONFIRMED`, sets `handover.receiptNotes` (optional).
- Emits `RECEIVED_FROM_HANDOVER` audit event per snapshot (audit trail only).
- Publishes `LineStateChangedEvent`.

The incoming operator takes on responsibility for the FALET items by confirming. Those FALET items continue with `status=OPEN`, available for the incoming operator to convert or dispose.

---

### 4.5 Handover Rejection (incoming operator)

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}/reject`

**Service method**: `LineHandoverService.rejectHandover(Long lineId, Long handoverId, LineHandoverRejectRequest request)`

**Validation**:

- At least one reason required (`incorrectQuantity=true` OR `otherReason=true`); else `REJECTION_REASON_REQUIRED`.
- If `otherReason=true`: `otherReasonNotes` required.
- If `incorrectQuantity=true`: `itemObservations` array required, one entry per FALET snapshot.

**FALET impact (critical path)**:

1. For each `LineHandoverFaletSnapshot` in the handover:
   - Locks the associated `FaletCurrentState` with `SELECT … FOR UPDATE`.
   - Sets `falet_current_states.status = DISPUTED`.
   - Creates `FaletDisputeItem` with `disputed_quantity = snapshot.quantity`, `remaining_quantity = snapshot.quantity`.
   - If `observedQuantity` was provided in `itemObservations`, sets `snapshot.observed_quantity`.
2. Creates `FaletDispute`:
   - `status = OPEN`
   - `total_disputed_qty = sum of snapshot quantities`
   - `held_qty = total_disputed_qty`
   - `rejection_incorrect_quantity`, `rejection_other_reason`, `rejection_other_reason_notes` flags.
3. Sets `handover.status = REJECTED`.
4. Publishes `LineStateChangedEvent`.

**Result**: All FALET items that were in the handover snapshot are now DISPUTED and frozen. The admin must intervene via the web dispute-resolution UI.

---

### 4.6 Convert FALET to Pallet (operator action)

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/falet/convert-to-pallet`

**Controller**: `PalletizingLineController`

**Service method**: `FaletService.convertFaletToPallet(Long lineId, ConvertFaletToPalletRequest request)`

**Request**: `{ faletId, additionalFreshQuantity (optional, ≥0) }`

**Logic**:

1. Locks `FaletCurrentState` by `faletId` with `SELECT … FOR UPDATE`.
2. Validates FALET is OPEN and belongs to `lineId`.
3. Generates scanned value (next available serial).
4. Creates `Pallete` with `quantity = faletQty + freshToAdd`.
5. Creates 2 `PalleteCreationBreakdown` rows:
   - One for FALET cartons (attributed to original source operator from `falet_source_segments`).
   - One for fresh cartons (attributed to current active operator, if `freshToAdd > 0`).
6. Sets `falet_current_states.status = RESOLVED`, `quantity = 0`.
7. Emits `CONVERTED_TO_PALLET` event.
8. Publishes `LineStateChangedEvent`.

**Returns**: `ConvertFaletToPalletResponse` with `pallet`, `creationMode` (`FROM_FALET` or `FROM_FALET_PLUS_FRESH`), `faletQuantityUsed`, `freshQuantityAdded`, `finalQuantity`, `faletId`.

---

### 4.7 Dispose FALET (operator action)

**Endpoint**: `POST /api/v1/palletizing-line/lines/{lineId}/falet/dispose`

**Controller**: `PalletizingLineController`

**Service method**: `FaletService.disposeFalet(Long lineId, DisposeFaletRequest request)`

**Request**: `{ faletId, reason (optional string) }`

**Logic**:

1. Locks FALET with `SELECT … FOR UPDATE`.
2. Validates OPEN status and line ownership.
3. Sets `status = RESOLVED`, `quantity = 0`.
4. Emits `DISPOSED` event.
5. Publishes `LineStateChangedEvent`.

**Returns**: `DisposeFaletResponse` with `faletId`, `productTypeId`, `productTypeName`, `disposedQuantity`, `reason`, `disposedAt`.

---

### 4.8 Admin Dispute Resolution (web admin UI)

**Entry point**: `POST /web/admin/falet-disputes/{disputeId}/action` (Thymeleaf form)

**Controller**: `WebAdminFaletDisputesController.executeAction()`

**Service method**: `FaletDisputeService.executeAction(Long disputeId, FaletDisputeActionRequest request, Long userId)`

**Form params**: `disputeItemId`, `actionType` (DISPOSE/PALLETIZE/RELEASE/HOLD), `quantity`, `freshQuantityAdded` (PALLETIZE only), `notes`.

**Per-action logic**:

- `DISPOSE`: `FALET.qty -= amount` → `RESOLVED` when qty=0. Dispute `disposedQty += amount`.
- `PALLETIZE`: Creates pallet, `FALET.qty -= amount` → `RESOLVED` when qty=0. Dispute `palletizedQty += amount`. Requires active authorization if `freshQtyAdded > 0`.
- `RELEASE`: Creates new `FaletCurrentState` with `status=OPEN`, `originType=DISPUTE_RELEASE`. `FALET.qty -= amount`. Dispute `releasedQty += amount`, `held_qty -= amount`.
- `HOLD`: Records action audit only. No quantity change.

After every action: recalculates `FaletDispute.status` based on `remainingQty`:

- `remainingQty == 0` → RESOLVED
- `0 < remainingQty < total_disputed_qty` → PARTIALLY_RESOLVED
- `remainingQty == total_disputed_qty` → remains OPEN

---

## 5. Full Lifecycle Walkthroughs

### Scenario A: FALET Created from Product Switch

**Trigger**: Operator on Production Line 3 is producing Product A (prefix 010). They have completed 7 cartons. They tap "Switch Product" to Product B.

**Validations** (in `ProductSwitchService.recordProductSwitch`):

- `previousProductTypeId` = currently set product? Yes.
- Same product switch? No.
- `faletQuantity > 0`? Assume yes (7 cartons).

**DB writes**:

1. `FaletCurrentStateRepository.findOpenByLineAndProductAndAuthForUpdate(lineId, productTypeA.id, auth.id)` → no existing row.
2. INSERT `falet_current_states`: `{lineId=3, productTypeId=A, quantity=7, status=OPEN, originType=PRODUCT_SWITCH, authorizationId=<currentAuth>}`.
3. INSERT `falet_events`: `{eventType=RECORDED_FROM_PRODUCT_SWITCH, quantity_delta=7, quantity_after=7}`.
4. INSERT `falet_source_segments`: `{quantity=7, originType=PRODUCT_SWITCH, operatorNameSnapshot="Mohammed"}`.
5. UPDATE `production_lines.current_product_type_id = productTypeB.id`.

**Status transitions**: New `FaletCurrentState` → `OPEN`.

**Line state**: `hasOpenFalet=true`, `openFaletCount=1`. SSE broadcast to admin dashboard.

**Frontend effect**: Next call to `GET /lines/3/falet` will return this item. `GET /lines/3/falet/first-pallet-suggestion` will return an auto-suggestion if the operator later switches back to Product A within the same session.

---

### Scenario B: Product Switch Merges with Existing FALET (same session, same product)

The session-scoped merge fires when the **same operator (same auth) switches away from Product A a second time**. Example:

1. Operator switches A → B (7 cartons of A → FALET id=X).
2. Operator produces B for a while, then switches B → A (3 cartons of B → FALET id=Y).
3. Operator switches A → C (4 more cartons of A): system finds FALET id=X (same line, same product=A, same auth) via `findOpenByLineAndProductAndAuthForUpdate` → **merges**: FALET id=X becomes `quantity = 7 + 4 = 11`.

**DB writes on merge**:

1. `findOpenByLineAndProductAndAuthForUpdate(lineId, A.id, auth.id)` → finds FALET X.
2. UPDATE `falet_current_states SET quantity = 11 WHERE id=X`.
3. INSERT `falet_events`: `{eventType=MERGED_WITH_EXISTING, quantity_delta=4, quantity_after=11}`.
4. INSERT `falet_source_segments`.

No new `falet_current_states` row is created. Only one OPEN FALET exists for (line, Product A, this auth).

---

### Scenario C: FALET Created During Handover (Last Active Product)

**Trigger**: Outgoing operator initiates handover. Their last active product was Product A, with 12 cartons remaining.

**Request body**:

```json
{
  "lastActiveProductTypeId": 101,
  "lastActiveProductFaletQuantity": 12,
  "faletResolutions": [
    { "faletId": 5, "action": "CARRY_FORWARD" },
    { "faletId": 7, "action": "CARRY_FORWARD" }
  ],
  "notes": "leaving early"
}
```

**Sequence in `createHandover()`**:

1. `faletService.recordFaletFromHandoverLastActive(lineId, 101, 12, outgoingAuth)` → creates/merges FALET with `originType=HANDOVER_LAST_ACTIVE`. Assume new FALET id=7.
2. `faletService.getOpenFaletStates(lineId)` → returns 2 items: FALET(id=5) for Product B + FALET(id=7) for Product A.
3. Validate `faletResolutions` covers both IDs → passes.
4. Both are `CARRY_FORWARD` → create 2 `line_handover_falet_snapshots`.
5. Outgoing auth released. Handover saved as PENDING.

**Line state**: `hasOpenFalet=true` (items not resolved). Incoming operator can see pending handover.

---

### Scenario D: FALET Handed Over and Confirmed

**Trigger**: Incoming operator reviews the PENDING handover and taps "Confirm".

**Request body**:

```json
{ "receiptNotes": "received 12 cartons, all good" }
```

**In `confirmHandover()`**:

- `handover.status = CONFIRMED`.
- `handover.receiptNotes = "received 12 cartons, all good"`.
- For each `LineHandoverFaletSnapshot`: emit `RECEIVED_FROM_HANDOVER` audit event.
- Publish `LineStateChangedEvent`.

**FALET state**: **Unchanged.** Both FALET items remain `status=OPEN`. Incoming operator inherits them.

**Frontend effect**: Incoming operator's `GET /lines/{lineId}/falet` returns the FALET items. `GET /lines/{lineId}/falet/first-pallet-suggestion` may offer auto-suggestion with `matchType=CONFIRMED_HANDOVER`.

---

### Scenario E: FALET Handed Over and Rejected

**Trigger**: Incoming operator counts the FALET cartons and finds the quantity is wrong.

**Request body** (V37 structured format):

```json
{
  "incorrectQuantity": true,
  "otherReason": false,
  "itemObservations": [{ "faletSnapshotId": 42, "observedQuantity": 8 }]
}
```

**In `rejectHandover()`**:

1. Validation passes.
2. For snapshot(id=42) referencing FALET(id=5, qty=12):
   - Lock FALET(id=5) via `SELECT … FOR UPDATE`.
   - `falet_current_states SET status = 'DISPUTED' WHERE id=5`.
   - `snapshot.observed_quantity = 8`.
   - INSERT `falet_dispute_items`: `{falet_current_state_id=5, disputed_quantity=12, remaining_quantity=12, observed_quantity=8}`.
3. INSERT `falet_disputes`: `{handover_id=<handover>, status=OPEN, total_disputed_qty=12, held_qty=12, rejection_incorrect_quantity=true}`.
4. `handover.status = REJECTED`.

**FALET state**: FALET(id=5) is now `DISPUTED`. Invisible to operators. Admin must act.

---

### Scenario F: Admin Resolves Dispute — PALLETIZE + RELEASE

**Trigger**: Admin opens `/web/admin/falet-disputes/{disputeId}`, sees 12 cartons disputed for Product A, observedQty=8.

**Admin decision**: Palletize 8, release the remaining 4 back to operators.

**Action 1** — `actionType=PALLETIZE, quantity=8, freshQuantityAdded=0`:

- Creates new pallet with 8 cartons (attributed to original outgoing operator).
- `FaletCurrentState(id=5).quantity -= 8` → `quantity=4`.
- `dispute.palletized_qty = 8`, `dispute_item.remaining_quantity = 4`.
- `dispute.status = PARTIALLY_RESOLVED`.
- Event: `DISPUTE_PALLETIZED`.

**Action 2** — `actionType=RELEASE, quantity=4`:

- Creates NEW `falet_current_states`: `{status=OPEN, originType=DISPUTE_RELEASE, quantity=4}`.
- `FaletCurrentState(id=5).quantity -= 4` → `quantity=0`, `status=RESOLVED`.
- `dispute.released_qty = 4`, `dispute.held_qty -= 4`, `dispute_item.remaining_quantity = 0`.
- `dispute.status = RESOLVED`.
- Events: `DISPUTE_RELEASED` on old FALET; new OPEN FALET created.
- Publish `LineStateChangedEvent`.

**Result**: Old disputed FALET(id=5) → RESOLVED. New FALET(id=99) → OPEN with `originType=DISPUTE_RELEASE`. Visible in operator FALET screen as a manager-resolved card. **Never auto-suggested.**

---

### Scenario G: Operator Converts FALET to Pallet

**Trigger**: Operator opens FALET screen, sees FALET item for Product A (7 cartons). Taps "Convert to Pallet" with 3 additional fresh cartons.

**Request**: `POST /lines/{lineId}/falet/convert-to-pallet` → `{ faletId: 5, additionalFreshQuantity: 3 }`

**In `convertFaletToPallet()`**:

1. Lock FALET(id=5).
2. Generate scannedValue (e.g., `010000000042`).
3. Create `Pallete`: `{quantity=10}`.
4. Create 2 `PalleteCreationBreakdown`:
   - `{quantity=7, contributionSource=FALET, faletCurrentStateId=5}`.
   - `{quantity=3, contributionSource=FRESH}`.
5. `falet_current_states SET status=RESOLVED, quantity=0 WHERE id=5`.
6. INSERT `falet_events`: `{eventType=CONVERTED_TO_PALLET, quantity_delta=-7, quantity_after=0}`.
7. Publish `LineStateChangedEvent`.

**Returns**: `creationMode=FROM_FALET_PLUS_FRESH`, `faletQuantityUsed=7`, `freshQuantityAdded=3`, `finalQuantity=10`.

---

### Scenario H: Operator Disposes FALET

**Trigger**: Operator sees 3 damaged cartons of FALET for Product A.

**Request**: `POST /lines/{lineId}/falet/dispose` → `{ faletId: 5, reason: "cartons damaged during storage" }`

**In `disposeFalet()`**:

1. Lock FALET(id=5).
2. `falet_current_states SET status=RESOLVED, quantity=0 WHERE id=5`.
3. INSERT `falet_events`: `{eventType=DISPOSED, quantity_delta=-3, quantity_after=0}`.
4. Publish `LineStateChangedEvent`.

No pallet created. No dispute possible.

---

### Scenario I: FALET Left Open Across Multiple Sessions

**Is this possible?** **Yes.** FALET is line-scoped, not session-scoped.

1. Operator A creates FALET (7 cartons of Product A) via product switch.
2. Operator A's shift ends without a handover (direct auth release, not handover-based).
3. The FALET row remains OPEN with `authorizationId=A's_auth`.
4. Operator B gets authorized on the same line.
5. `GET /lines/{lineId}/falet` returns the FALET item from Operator A's session.
6. Operator B can convert or dispose it.
7. `getFirstPalletSuggestion()` will NOT auto-suggest this FALET because neither same-session-return nor confirmed-handover conditions are met → returns `OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION`.

---

### Scenario J: Multiple OPEN FALET Items for Different Products

This is the normal production scenario. An operator may have:

- FALET(id=10): Product A, 5 cartons, from earlier product switch.
- FALET(id=11): Product B, 3 cartons, from handover carry-forward.
- FALET(id=12): Product A, 7 cartons, from a different auth session (a previous operator).

All three are OPEN simultaneously. `GET /lines/{lineId}/falet` returns all three. When the operator creates a handover, `faletResolutions` must cover IDs 10, 11, **and** 12. Missing any causes `HANDOVER_FALET_DECISION_MISSING`.

---

## 6. Handover-Specific FALET Behavior (Deep)

### What Happens When Outgoing Operator Enters FALET Quantity

When creating a handover with `lastActiveProductFaletQuantity > 0`:

1. `faletService.recordFaletFromHandoverLastActive()` is called **first** within `createHandover()`, before the FALET decision validation.
2. This creates or merges a FALET row immediately.
3. The open FALET items list (from `getOpenFaletStates()`) **includes the just-created one**.
4. The outgoing operator must include this newly created FALET in `faletResolutions` in the same request.

**Implication**: The Flutter app must, at handover-creation time:

1. Fetch current open FALET → `GET /lines/{lineId}/falet`.
2. Let the operator declare the last-active product and quantity.
3. Compute the full set of FALET that will exist (existing open ones + the one about to be declared).
4. Require the operator to make a resolution decision for each.
5. Submit all in one `POST /lines/{lineId}/handover`.

### How Open FALET Items Are Snapshotted

Only `CARRY_FORWARD` items become `LineHandoverFaletSnapshot` rows. `USED_IN_EXISTING_SESSION_PALLETE` items are immediately RESOLVED and tracked via `falet_pallete_reconciliations` instead.

**Snapshot deduplication**: `UNIQUE(handover_id, product_type_id)` constraint on `line_handover_falet_snapshots`. If multiple OPEN FALET items exist for the same product type (different auths), they are **grouped by product type and summed** before snapshot creation in `LineHandoverService.createHandover()`.

### Snapshot Storage

`LineHandoverFaletSnapshot` — fields: `handover_id`, `falet_current_state_id` (individual FALET row link), `product_type_id`, `quantity` (at snapshot time), `is_last_active_product`, `observed_quantity` (filled in on rejection).

### What Incoming Operator Sees

`LineHandoverResponse` includes:

- `faletItems[]` (FaletSnapshotItem) — snapshotted FALET items with product type, quantity, `observedQuantity`, `lastActiveProduct` flag.
- `hasFalet: true/false`.
- `faletItemCount`.
- `reconciledFaletItems[]` — FALET items that were resolved via `USED_IN_EXISTING_SESSION_PALLETE`.

### What Confirm Does

Sets `handover.status = CONFIRMED`. No FALET status changes. FALET items remain OPEN and become the responsibility of the incoming operator. Optionally sets `receiptNotes`.

### What Reject Does

Sets each FALET associated with carry-forward snapshots to `DISPUTED`. All disputed FALET are frozen: invisible to operators, held for admin resolution.

### Whether FALET Remains Open After Confirm/Reject

- **After CONFIRM**: Yes, all carried-forward FALET items remain `OPEN`. Incoming operator is responsible.
- **After REJECT**: No. All carried-forward FALET items become `DISPUTED` (frozen).

### Where FALET Decision Requirements Come From

`LineHandoverService.createHandover()` calls `faletService.getOpenFaletStates(lineId)` and enforces that `request.faletResolutions` covers every returned OPEN FALET ID.

### Where `HANDOVER_FALET_DECISION_REQUIRED` May Be Thrown

Exclusively in `LineHandoverService.createHandover()`. No other service or controller throws this error code.

---

## 7. FALET Resolution Decisions Analysis

### What "FALET Resolution Decisions" Means in Code

`faletResolutions` is a `List<LineHandoverRequest.FaletResolutionEntry>` embedded in `LineHandoverRequest`. Each entry:

```java
public static class FaletResolutionEntry {
    @NotNull Long faletId;
    @NotNull HandoverFaletAction action; // CARRY_FORWARD | USED_IN_EXISTING_SESSION_PALLETE
    Long existingPalleteId;              // Required only for USED_IN_EXISTING_SESSION_PALLETE
}
```

### Which Service/Method Expects Them

Only `LineHandoverService.createHandover()`.

### Which Validation Throws If Missing

| Error Code                                | Condition                                                            |
| ----------------------------------------- | -------------------------------------------------------------------- |
| `HANDOVER_FALET_DECISION_REQUIRED`        | `faletResolutions` null/empty, but `openFaletItems` non-empty        |
| `HANDOVER_FALET_DECISION_DUPLICATE`       | Same `faletId` appears more than once                                |
| `HANDOVER_FALET_DECISION_MISSING`         | An open FALET ID is not present in `faletResolutions`                |
| `HANDOVER_FALET_PALLETE_REQUIRED`         | `action=USED_IN_EXISTING_SESSION_PALLETE` but no `existingPalleteId` |
| `HANDOVER_FALET_PALLETE_NOT_FOUND`        | `existingPalleteId` references non-existent pallet                   |
| `HANDOVER_FALET_PALLETE_WRONG_SESSION`    | Pallet belongs to different authorization                            |
| `HANDOVER_FALET_PALLETE_WRONG_LINE`       | Pallet belongs to different line                                     |
| `HANDOVER_FALET_PALLETE_CANCELLED`        | Pallet production status is CANCELLED                                |
| `HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH` | Pallet's product type ≠ FALET's product type                         |
| `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE` | Sum of reconciled quantities > pallet quantity                       |

### Whether This Requirement Belongs to Handover Creation

**Yes, exclusively.** It is not part of handover confirmation, rejection, dispute resolution, or any other flow. It is required at **handover CREATION time** only.

### Whether Frontend Contract Currently Supports Sending These Decisions

#### Flutter Palletizing / Thermoforming App

**Indeterminate from code** — no Flutter source files exist in this repository. Based on handoff documentation:

- `FRONTEND_AI_AGENT_HANDOFF.md` explicitly lists "Handover-time FALET reconciliation" as **"the most critical Flutter feature requiring implementation."**
- This strongly implies the Flutter app does **not yet** implement this feature.
- **Assessment**: The Flutter app most likely does NOT currently send `faletResolutions` in the handover creation request. This is an **unimplemented feature on the Flutter side**.

#### Web Admin / Thymeleaf

The web admin layer does **not** create handovers. It handles dispute resolution only. The `faletResolutions` requirement is therefore **not applicable to the web layer**.

### Is There a Backend/Frontend Mismatch?

**Yes, confirmed.** The backend requires `faletResolutions` when open FALET items exist. The Flutter app has not been confirmed to send this field. Handoff documentation explicitly marks this as a pending Flutter implementation task.

---

## 8. API Contract Map

### 8.1 `GET /api/v1/palletizing-line/lines/{lineId}/falet`

| Field            | Value                                                                                                                                                                   |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Caller(s)        | Flutter palletizing/thermoforming app                                                                                                                                   |
| Auth             | JWT; active line authorization required                                                                                                                                 |
| Request body     | None                                                                                                                                                                    |
| Response         | `ApiResponse<FaletScreenResponse>`                                                                                                                                      |
| Response fields  | `faletItems[]`, `totalOpenFaletCount`, `hasOpenFalet`, `managerResolvedFaletCount`                                                                                      |
| Each `faletItem` | `faletId`, `productTypeId`, `productTypeName`, `quantity`, `status`, `originType`, `sourceOperatorName`, `authorizationId`, `managerResolved`, `createdAt`, `updatedAt` |
| Business rules   | Returns only `status=OPEN` items. `managerResolved=true` for `originType=DISPUTE_RELEASE`.                                                                              |
| Failures         | `LINE_NOT_FOUND`, `LINE_AUTH_REQUIRED`                                                                                                                                  |

---

### 8.2 `GET /api/v1/palletizing-line/lines/{lineId}/falet/first-pallet-suggestion`

| Field                  | Value                                                                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Caller(s)              | Flutter app (on session start, when selecting first product)                                                                           |
| Response fields        | `available`, `faletId`, `approvedCartons`, `suggestedFreshQuantity`, `sourceOperatorName`, `matchType`, `unavailableReason`            |
| `matchType` values     | `SAME_SESSION_RETURN`, `CONFIRMED_HANDOVER`                                                                                            |
| Auto-suggestion cases  | Case A: same-session FALET (same auth, same product, OPEN, not DISPUTE_RELEASE). Case B: confirmed-handover FALET for current product. |
| Non-suggestion reasons | `NO_PRODUCT_SELECTED`, `NO_ELIGIBLE_FALET`, `NO_MATCHING_FALET_FOR_CURRENT_PRODUCT`, `OPEN_FALET_NOT_ELIGIBLE_FOR_AUTO_SUGGESTION`     |
| Important              | `DISPUTE_RELEASE` FALET is never auto-suggested.                                                                                       |

---

### 8.3 `POST /api/v1/palletizing-line/lines/{lineId}/falet/convert-to-pallet`

| Field           | Value                                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| HTTP response   | 201 CREATED                                                                                                                          |
| Request body    | `{ "faletId": Long (required), "additionalFreshQuantity": Int (optional, ≥0) }`                                                      |
| Response        | `ApiResponse<ConvertFaletToPalletResponse>`                                                                                          |
| Response fields | `pallet`, `creationMode` (FROM_FALET / FROM_FALET_PLUS_FRESH), `faletQuantityUsed`, `freshQuantityAdded`, `finalQuantity`, `faletId` |
| Business rules  | FALET must be OPEN. Must belong to lineId. Creates pallet, resolves FALET.                                                           |
| Failures        | `FALET_NOT_FOUND`, `FALET_ALREADY_RESOLVED`, `LINE_AUTH_REQUIRED`                                                                    |

---

### 8.4 `POST /api/v1/palletizing-line/lines/{lineId}/falet/dispose`

| Field           | Value                                                                                                          |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| HTTP response   | 200 OK                                                                                                         |
| Request body    | `{ "faletId": Long (required), "reason": String (optional) }`                                                  |
| Response        | `ApiResponse<DisposeFaletResponse>`                                                                            |
| Response fields | `faletId`, `productTypeId`, `productTypeName`, `disposedQuantity`, `reason`, `disposedAt`, `disposedAtDisplay` |
| Business rules  | FALET must be OPEN. Must belong to lineId. No pallet created.                                                  |
| Failures        | `FALET_NOT_FOUND`, `FALET_ALREADY_RESOLVED`                                                                    |

---

### 8.5 `POST /api/v1/palletizing-line/lines/{lineId}/handover` — Create (Critical)

**Request body** (full schema):

```json
{
  "lastActiveProductTypeId": 101,
  "lastActiveProductFaletQuantity": 12,
  "notes": "optional string",
  "faletResolutions": [
    {
      "faletId": 5,
      "action": "CARRY_FORWARD",
      "existingPalleteId": null
    },
    {
      "faletId": 6,
      "action": "USED_IN_EXISTING_SESSION_PALLETE",
      "existingPalleteId": 42
    }
  ]
}
```

**Required vs optional**:

- `lastActiveProductTypeId` + `lastActiveProductFaletQuantity`: both required together or both absent.
- `faletResolutions`: **required when any open FALET items exist on the line** (including the one about to be declared via `lastActiveProductFaletQuantity`). Optional only when zero open FALET items exist.
- `existingPalleteId`: required when `action=USED_IN_EXISTING_SESSION_PALLETE`.

**Potential failure codes**: `HANDOVER_FALET_DECISION_REQUIRED`, `HANDOVER_FALET_DECISION_MISSING`, `HANDOVER_FALET_DECISION_DUPLICATE`, all `HANDOVER_FALET_PALLETE_*` codes, `LINE_AUTH_REQUIRED`, `PENDING_HANDOVER_EXISTS`.

---

### 8.6 `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm`

| Field          | Value                                                          |
| -------------- | -------------------------------------------------------------- |
| Request body   | `{ "receiptNotes": "optional string" }`                        |
| Business rules | Handover must be PENDING. Caller must be an incoming operator. |
| FALET effect   | None — FALET remains OPEN.                                     |
| Response       | `ApiResponse<LineHandoverResponse>` with `status=CONFIRMED`    |

---

### 8.7 `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`

| Field          | Value                                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Request body   | `{ "incorrectQuantity": bool, "otherReason": bool, "otherReasonNotes": string?, "itemObservations": [{ "faletSnapshotId": Long, "observedQuantity": Int }] }` |
| Business rules | At least one reason required. `itemObservations` required if `incorrectQuantity=true`. One entry per FALET snapshot.                                          |
| FALET effect   | All carry-forward FALET items → DISPUTED. FaletDispute created.                                                                                               |
| Failures       | `REJECTION_REASON_REQUIRED`, `OBSERVED_QUANTITY_REQUIRED`                                                                                                     |

---

### 8.8 `POST /api/v1/palletizing-line/lines/{lineId}/product-switch`

| Field          | Value                                                                                    |
| -------------- | ---------------------------------------------------------------------------------------- |
| Request body   | `{ "previousProductTypeId": Long, "newProductTypeId": Long, "faletQuantity": Integer }`  |
| Business rules | `previousProductTypeId` must match current product. New ≠ current.                       |
| FALET effect   | If `faletQuantity > 0`: creates/merges FALET for previous product.                       |
| Failures       | `CURRENT_PRODUCT_MISMATCH`, `PRODUCT_TYPE_SWITCH_SAME_PRODUCT`, `PRODUCT_TYPE_NOT_FOUND` |

---

### 8.9 `POST /web/admin/falet-disputes/{id}/action`

| Field          | Value                                                                                                                               |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Caller         | Web admin user (ADMIN role) — Thymeleaf form                                                                                        |
| Form params    | `disputeItemId`, `actionType` (DISPOSE/PALLETIZE/RELEASE/HOLD), `quantity`, `freshQuantityAdded` (PALLETIZE only), `notes`          |
| Business rules | Dispute must not be RESOLVED. Item must have remaining > 0. `quantity ≤ remaining`. If PALLETIZE + fresh > 0: active auth required. |
| FALET effect   | See §4.8 for per-action behavior                                                                                                    |
| Response       | Redirect to `/web/admin/falet-disputes/{id}` with flash message                                                                     |

---

## 9. Frontend Integration Map

### 9.1 Flutter Palletizing / Thermoforming App

**Source code status**: No Flutter `.dart` files exist in this repository. All entries below are based on handoff documentation.

| Screen / Dialog                 | Expected Actions                                                                                                       | FALET Decisions Support                       | Backend Alignment                                                                                                      |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **FALET Screen**                | Lists all OPEN FALET items. "Convert to Pallet" and "Dispose" buttons per item.                                        | N/A — reads only                              | Calls `GET /lines/{lineId}/falet`. Documented as expected.                                                             |
| **Convert to Pallet Dialog**    | Operator enters optional fresh quantity. Submits conversion.                                                           | N/A                                           | Calls `POST /lines/{lineId}/falet/convert-to-pallet`. Documented.                                                      |
| **Dispose FALET Dialog**        | Operator enters optional reason. Confirms disposal.                                                                    | N/A                                           | Calls `POST /lines/{lineId}/falet/dispose`. Documented.                                                                |
| **Manager-Resolved FALET Card** | Special card for `DISPUTE_RELEASE` items. Operator acts via same convert/dispose buttons.                              | N/A                                           | Identified by `managerResolved=true`. Documented.                                                                      |
| **Product Switch Flow**         | Operator switches product, enters leftover carton count.                                                               | N/A                                           | Calls `POST /lines/{lineId}/product-switch` with `faletQuantity`. Documented.                                          |
| **First Pallet Suggestion**     | On session start with matching product, system offers FALET cartons as basis.                                          | N/A                                           | Calls `GET /lines/{lineId}/falet/first-pallet-suggestion`. Documented.                                                 |
| **Handover Creation Screen**    | Outgoing operator declares last-active product + quantity. **Must also submit `faletResolutions` for ALL open FALET.** | **CRITICAL — NOT YET IMPLEMENTED (per docs)** | Backend requires `faletResolutions` array. Marked as pending Flutter implementation in `FRONTEND_AI_AGENT_HANDOFF.md`. |
| **Handover Review Screen**      | Incoming operator reviews snapshot. Decides to confirm or reject.                                                      | Not applicable (no decisions here)            | Confirm/reject endpoints exist and documented. V37 structured rejection required.                                      |

**Key mismatch**: The handover creation screen does not currently send `faletResolutions`. This causes `HANDOVER_FALET_DECISION_REQUIRED` when any open FALET exists.

---

### 9.2 Web Admin / Thymeleaf

| Page / Template          | HTTP Path                                    | FALET Role                                                                                                   | Status                                                                |
| ------------------------ | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- |
| **FALET Disputes List**  | `GET /web/admin/falet-disputes`              | Lists all disputes by status; pagination + filter.                                                           | Fully implemented. Template: `web/admin/falet-disputes/list.html`.    |
| **FALET Dispute Detail** | `GET /web/admin/falet-disputes/{id}`         | Shows dispute info, rejection reasons, item breakdown, observed quantities, action history, resolution form. | Fully implemented. Template: `web/admin/falet-disputes/detail.html`.  |
| **Manager Action Form**  | `POST /web/admin/falet-disputes/{id}/action` | PALLETIZE / RELEASE / HOLD / DISPOSE per item.                                                               | Fully implemented. `WebAdminFaletDisputesController.executeAction()`. |
| **Line State Overview**  | `GET /web/admin/line-state`                  | Shows line authorization status. No direct FALET details. SSE stream for live updates.                       | Functional. `web/admin/line-state/overview.html`.                     |
| **Handover List**        | `GET /web/admin/line-state/handovers`        | Lists all handovers with FALET reconciliation info.                                                          | Functional. `web/admin/line-state/handovers.html`.                    |
| **Handover Detail**      | `GET /web/admin/line-state/handovers/{id}`   | Shows reconciled FALET items, snapshots, dispute link.                                                       | Functional. `web/admin/line-state/handover-detail.html`.              |
| **Pallet Detail**        | `GET /web/admin/palletes/detail?sv={sv}`     | Shows `FaletPalleteReconciliation` records linked to a pallet.                                               | Functional. `WebAdminPalleteController`.                              |
| **Legacy Redirect**      | `GET /web/admin/line-handover-disputes/**`   | All routes redirect to `/web/admin/falet-disputes`.                                                          | Legacy pass-through. `WebAdminLineHandoverDisputesController`.        |

**Admin cannot**: Create handovers, override handover FALET decisions, directly modify FALET states outside dispute resolution.

---

## 10. State Machine / Transition Map

FALET items (`falet_current_states`) move through the following confirmed transitions:

```
[CREATED]
    │
    ├─ recordFaletFromProductSwitch()        → OPEN  (originType = PRODUCT_SWITCH)
    ├─ recordFaletFromHandoverLastActive()   → OPEN  (originType = HANDOVER_LAST_ACTIVE)
    └─ FaletDisputeService RELEASE action   → OPEN  (originType = DISPUTE_RELEASE)  [new row]


OPEN
    │
    ├─ convertFaletToPallet()
    │       └─────────────────────────────────────────────────── RESOLVED
    │
    ├─ disposeFalet()
    │       └─────────────────────────────────────────────────── RESOLVED
    │
    ├─ createHandover() with USED_IN_EXISTING_SESSION_PALLETE
    │       └─────────────────────────────────────────────────── RESOLVED
    │
    ├─ createHandover() with CARRY_FORWARD
    │       └────────────────────────────────── (stays OPEN, snapshot created in line_handover_falet_snapshots)
    │
    └─ rejectHandover()
            └─────────────────────────────────────────────────── DISPUTED


DISPUTED  (frozen — operators cannot see or act on this FALET)
    │
    ├─ FaletDisputeService DISPOSE action
    │       └── qty -= amount  →  if qty = 0: RESOLVED
    │
    ├─ FaletDisputeService PALLETIZE action
    │       └── qty -= amount  →  if qty = 0: RESOLVED
    │
    ├─ FaletDisputeService RELEASE action
    │       ├── qty -= amount  →  if qty = 0: RESOLVED
    │       └── creates NEW FaletCurrentState (status = OPEN, originType = DISPUTE_RELEASE)
    │
    └─ FaletDisputeService HOLD action
            └── (no qty change — remains DISPUTED)


RESOLVED  (terminal — no further transitions possible)
```

**FaletDispute state machine** (separate from FALET item state):

```
OPEN  →  PARTIALLY_RESOLVED  →  RESOLVED
```

Transition computed automatically after each `FaletDisputeService.executeAction()` call based on `remainingQty`.

---

## 11. Concurrency, Locking, and Consistency

### SELECT … FOR UPDATE Usage

All mutation operations on FALET use pessimistic row-level locking:

| Lock Site                                 | Repository Method                              | Used In                                                                 |
| ----------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| Lock FALET by ID                          | `findByIdForUpdate(id)`                        | `convertFaletToPallet()`, `disposeFalet()`, `rejectHandover()`          |
| Lock OPEN FALET for (line, product, auth) | `findOpenByLineAndProductAndAuthForUpdate()`   | `recordFaletFromProductSwitch()`, `recordFaletFromHandoverLastActive()` |
| Lock OPEN FALET for (line, product)       | `findOpenByLineAndProductForUpdate()`          | Internal non-session-scoped queries                                     |
| Lock FaletDispute by ID                   | `FaletDisputeRepository.findByIdForUpdate(id)` | `FaletDisputeService.executeAction()`                                   |
| Lock LineHandover                         | `findByProductionLineIdAndStatusForUpdate()`   | `LineHandoverService`                                                   |

### One-PENDING-per-Line Constraint

`line_handovers` has a virtual generated column `pending_lock = IF(status='PENDING', production_line_id, NULL)` with UNIQUE constraint. Only one PENDING handover per line is physically enforced at DB level.

### Application-Level Invariants (Not DB-Enforced)

- One OPEN FALET per (line, product, auth) → enforced by session-scoped merge + FOR UPDATE.
- Multiple OPEN FALET rows for the same (line, product) with different auths ARE possible.
- One `FaletDispute` per rejected handover → enforced in service logic; no DB UNIQUE constraint.

### Risk: Multiple OPEN FALET Items for Same Product

If Operator A leaves an OPEN FALET for Product X without a handover, and Operator B creates an OPEN FALET for Product X via product switch, both rows coexist. When creating a handover, both IDs must be in `faletResolutions`. The snapshot deduplication by `product_type_id` then sums their quantities into one `LineHandoverFaletSnapshot` row.

---

## 12. Validation and Exception Map

| Error Code                                | Thrown In                              | Condition                                            |
| ----------------------------------------- | -------------------------------------- | ---------------------------------------------------- |
| `FALET_NOT_FOUND`                         | `FaletService`                         | FALET ID not found                                   |
| `FALET_ALREADY_RESOLVED`                  | `FaletService`                         | Attempting to act on non-OPEN FALET                  |
| `FALET_QUANTITY_MISMATCH`                 | `FaletService`                         | Internal quantity inconsistency                      |
| `FALET_DISPUTE_NOT_FOUND`                 | `FaletDisputeService`                  | Dispute ID not found                                 |
| `FALET_DISPUTE_ALREADY_RESOLVED`          | `FaletDisputeService`                  | Acting on fully resolved dispute                     |
| `FALET_DISPUTE_ITEM_NOT_FOUND`            | `FaletDisputeService`                  | Dispute item not found                               |
| `FALET_DISPUTE_QUANTITY_EXCEEDED`         | `FaletDisputeService`                  | Requested qty > remaining                            |
| `FALET_DISPUTE_ALREADY_EXISTS`            | `LineHandoverService.rejectHandover()` | Rejecting an already-disputed handover               |
| `HANDOVER_FALET_DECISION_REQUIRED`        | `LineHandoverService.createHandover()` | Open FALET exists, `faletResolutions` missing        |
| `HANDOVER_FALET_DECISION_MISSING`         | `LineHandoverService.createHandover()` | Not all open FALETs covered                          |
| `HANDOVER_FALET_DECISION_DUPLICATE`       | `LineHandoverService.createHandover()` | Duplicate `faletId` in resolutions                   |
| `HANDOVER_FALET_INVALID_ACTION`           | `LineHandoverService.createHandover()` | Unknown action type                                  |
| `HANDOVER_FALET_PALLETE_REQUIRED`         | `LineHandoverService.createHandover()` | `USED_IN_EXISTING_SESSION_PALLETE` without pallet ID |
| `HANDOVER_FALET_PALLETE_NOT_FOUND`        | `LineHandoverService.createHandover()` | Pallet ID not found                                  |
| `HANDOVER_FALET_PALLETE_WRONG_SESSION`    | `LineHandoverService.createHandover()` | Pallet from different auth session                   |
| `HANDOVER_FALET_PALLETE_WRONG_LINE`       | `LineHandoverService.createHandover()` | Pallet from different line                           |
| `HANDOVER_FALET_PALLETE_CANCELLED`        | `LineHandoverService.createHandover()` | Pallet is CANCELLED                                  |
| `HANDOVER_FALET_PALLETE_PRODUCT_MISMATCH` | `LineHandoverService.createHandover()` | Pallet product ≠ FALET product                       |
| `HANDOVER_FALET_QUANTITY_EXCEEDS_PALLETE` | `LineHandoverService.createHandover()` | Total reconciled qty > pallet qty                    |
| `LINE_AUTH_REQUIRED_FOR_ACTION`           | `FaletDisputeService.executeAction()`  | PALLETIZE with fresh, no active auth on line         |
| `REJECTION_REASON_REQUIRED`               | `LineHandoverService.rejectHandover()` | No reason flags set                                  |
| `PRODUCT_TYPE_NOT_FOUND`                  | `FaletService`, `ProductSwitchService` | Product type lookup failed                           |
| `CURRENT_PRODUCT_MISMATCH`                | `ProductSwitchService`                 | `previousProductTypeId` ≠ set product                |
| `PRODUCT_TYPE_SWITCH_SAME_PRODUCT`        | `ProductSwitchService`                 | New product = current product                        |
| `PRODUCT_ALREADY_SELECTED`                | `ProductSwitchService.selectProduct()` | Product already set                                  |

---

## 13. Code-vs-Doc Mismatch Findings

| #   | Area                                         | Doc Says                                                                                                              | Code Says                                                                                                                                                                | Verdict                                                                         |
| --- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| 1   | **4-digit vs 3-digit prefix**                | Some docs reference 12-digit value with 4-digit prefix.                                                               | V31 narrowed to 3-digit prefix. `ScannedValueParser` enforces 3-digit prefix + 9-digit serial.                                                                           | **Trust code (V31).** Some docs are stale.                                      |
| 2   | **`handoverType` field**                     | Legacy docs describe `handoverType` (NONE/INCOMPLETE_ONLY/LOOSE_ONLY/BOTH) in handover response.                      | `LineHandoverResponse` uses `hasFalet` + `faletItemCount` instead. No `handoverType` field.                                                                              | **Trust code.** Redesigned in V29+.                                             |
| 3   | **`looseBalances[]` and `incompletePallet`** | Legacy spec documents describe these as handover response fields.                                                     | Both replaced by `faletItems[]`. `line_handover_loose_balances` table exists but no service writes to it post-V29.                                                       | **Trust code.** Legacy model is stale.                                          |
| 4   | **`GET /open-items`**                        | `FALET_REDESIGN_FRONTEND_HANDOFF.md` lists old endpoint `GET /lines/{lineId}/open-items`.                             | Endpoint is `GET /lines/{lineId}/falet`.                                                                                                                                 | **Trust new doc and `FaletService.getOpenFalet()`.**                            |
| 5   | **`faletResolutions` requirement**           | `FRONTEND_AI_AGENT_HANDOFF.md` describes this as "requiring implementation" — implying Flutter hasn't implemented it. | Backend fully implements and enforces it. Throws `HANDOVER_FALET_DECISION_REQUIRED`.                                                                                     | **Confirmed mismatch.** Backend enforces; Flutter presumably does not send yet. |
| 6   | **`RECEIVED_FROM_HANDOVER` originType**      | Referenced as a possible `FaletOriginType` in docs.                                                                   | Enum value exists, but no service currently creates FALET with this origin type. Handover confirm does not create new FALET rows.                                        | **Partial use.** Enum reserved; not yet used for FALET creation.                |
| 7   | **One OPEN per (line, product)**             | V29 docs imply one OPEN FALET per (line, product_type).                                                               | V35 added `authorization_id`. Session-scoped merge operates per (line, product, **auth**). Multiple OPEN rows for same (line, product) but different auths are possible. | **Docs stale vs V35 behavior.**                                                 |
| 8   | **Dispute resolution via `/resolve`**        | Legacy `WebAdminLineHandoverDisputesController` had a `/resolve` endpoint.                                            | All routes redirect to `/web/admin/falet-disputes`. Per-item DISPOSE/PALLETIZE/RELEASE/HOLD replaces single-resolve.                                                     | **Legacy redirected.** Old endpoint is a pass-through.                          |
| 9   | **`shift_handovers` table**                  | V13 created `shift_handovers` as the primary handover model.                                                          | V21 replaced with `line_handovers`. V24 dropped legacy shift handover tables.                                                                                            | **V24 cleaned up legacy.** `line_handovers` is current truth.                   |

---

## 14. Current Risks and Ambiguity Areas

### Risk 1 — Flutter `faletResolutions` Not Implemented (CRITICAL)

`FRONTEND_AI_AGENT_HANDOFF.md` explicitly flags handover-time FALET reconciliation as the most critical pending Flutter feature. The backend throws `HANDOVER_FALET_DECISION_REQUIRED` immediately when any open FALET exists and `faletResolutions` is absent. **This is a live production breakage** whenever an operator attempts a handover while any FALET is open.

---

### Risk 2 — Last-Active FALET ID Must Be in `faletResolutions` in Same Request

The `faletResolutions` array must cover ALL open FALET items, **including** the `lastActiveProductFaletQuantity` item created server-side during the same request. The Flutter app must pre-calculate this by including the about-to-be-created FALET in the decisions before submitting. If the app fetches open FALET from `GET /falet` and uses only those IDs, it will miss the last-active FALET → `HANDOVER_FALET_DECISION_MISSING`.

---

### Risk 3 — No DB Unique Constraint on One OPEN FALET per (line, product)

The session-scoped merge logic depends on `findOpenByLineAndProductAndAuthForUpdate()`. Under a crash or connection failure mid-transaction, a duplicate OPEN FALET row for the same (line, product, auth) could be left in the DB. No DB-level UNIQUE constraint prevents this. The FOR UPDATE lock mitigates it during normal operation; crash recovery is not guaranteed.

---

### Risk 4 — DISPUTED FALET Invisible to Operators

Once FALET enters DISPUTED state, operators cannot see it (`getOpenFalet()` returns only OPEN items). The line's `hasOpenFalet` flag reads `false` (since `existsByProductionLineIdAndStatus` checks for `OPEN` only). Operators may believe there are no unresolved carton issues while DISPUTED cartons are in limbo. No operator notification mechanism was found in the explored code.

---

### Risk 5 — Snapshot Deduplication Loses Per-FALET Traceability

When `CARRY_FORWARD` resolutions are grouped by `product_type_id` into snapshots, multiple FALET items for the same product (different auths) are summed into a single `LineHandoverFaletSnapshot` row. During rejection, the dispute item can only reference one `falet_current_state_id`. The exact deduplication + FK assignment behavior for multi-FALET same-product scenarios was not fully confirmed and may create ambiguous traceability in disputes.

---

### Risk 6 — `DISPUTE_RELEASE` FALET Not Auto-Suggested; Operator UX Confusion

FALET released by an admin appears in the FALET screen with a special manager-resolved card. It is explicitly excluded from auto-suggestion. Operators must manually convert or dispose it. If operators don't recognize the meaning of this card, they may leave it open indefinitely.

---

### Risk 7 — Stale Documentation

Older spec documents in `docs/` (e.g., `BACKEND_OPEN_ITEMS_IMPLEMENTATION_AUDIT.md`, `BACKEND_LEGACY_CLEANUP_REPORT.md`) may reference old open-items/loose-balance/incomplete-pallet concepts. Reviewers reading those documents without this analysis may be misled about current behavior.

---

### Risk 8 — Admin PALLETIZE with Fresh Blocked When No Active Operator

If an admin wants to PALLETIZE disputed FALET with `freshQuantityAdded > 0`, the system requires an active `LineOperatorAuthorization` on the line. If the line is currently unmanned, this check fails with `LINE_AUTH_REQUIRED_FOR_ACTION`. The admin has no way to bypass this via the web UI. They must either wait for an operator to be authorized, or use `freshQuantityAdded=0`.

---

## 15. Most Likely Explanation for Current Runtime Issues

### Reported Symptom

> "Handover succeeds when no FALET is entered, but fails when FALET quantity is entered with a business error requiring FALET resolution decisions."

### Evidence-Based Explanation

**Root cause**: The Flutter palletizing app sends a handover creation request **without a `faletResolutions` field**, which is required by `LineHandoverService.createHandover()` when open FALET items exist.

**Exact code path producing the failure**:

1. Operator enters `lastActiveProductFaletQuantity > 0` in the handover form.
2. Flutter calls `POST /api/v1/palletizing-line/lines/{lineId}/handover` with:
   ```json
   { "lastActiveProductTypeId": 101, "lastActiveProductFaletQuantity": 12 }
   ```
   — **no `faletResolutions` field**.
3. `LineHandoverService.createHandover()` executes:
   - Step 1: `faletService.recordFaletFromHandoverLastActive(lineId, 101, 12, auth)` → creates new OPEN FALET.
   - Step 2: `faletService.getOpenFaletStates(lineId)` → returns at least 1 item.
   - Step 3: `request.faletResolutions` is null → `throw BusinessException(HANDOVER_FALET_DECISION_REQUIRED)`.
4. HTTP 400 response: `{ "success": false, "error": { "code": "HANDOVER_FALET_DECISION_REQUIRED", ... } }`.

**Why it succeeds when no FALET is entered**:

- `lastActiveProductFaletQuantity = 0` or `lastActiveProductTypeId = null` → Step 1 is skipped.
- If no pre-existing FALET items exist → `getOpenFaletStates()` returns empty list.
- Validation passes (nothing to require decisions for).
- Handover proceeds to PENDING status.

**Secondary failure path**: Even with `lastActiveProductFaletQuantity = 0`, if the operator previously performed a product switch that created open FALET, the same `HANDOVER_FALET_DECISION_REQUIRED` error will occur.

**Path to resolution**: The Flutter palletizing/thermoforming app must be updated to:

1. Fetch open FALET before handover creation (`GET /lines/{lineId}/falet`).
2. Display the full FALET list (including the about-to-be-created last-active FALET).
3. Collect operator decision for each (`CARRY_FORWARD` or `USED_IN_EXISTING_SESSION_PALLETE`).
4. Include the `faletResolutions` array in the handover creation request.

This is documented as the expected Flutter implementation in `FRONTEND_AI_AGENT_HANDOFF.md`.

---

## 16. Appendix: Code References

### Backend Services

| Class                  | Package                               | Key Methods                                                                                                                                                                                                     |
| ---------------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `FaletService`         | `ps.taleeb.taleebbackend.palletizing` | `recordFaletFromProductSwitch`, `recordFaletFromHandoverLastActive`, `getOpenFalet`, `getFirstPalletSuggestion`, `convertFaletToPallet`, `disposeFalet`, `getOpenFaletStates`, `hasOpenFalet`, `countOpenFalet` |
| `LineHandoverService`  | `ps.taleeb.taleebbackend.palletizing` | `createHandover`, `confirmHandover`, `rejectHandover`, `resolveDispute`                                                                                                                                         |
| `FaletDisputeService`  | `ps.taleeb.taleebbackend.palletizing` | `executeAction`, `listDisputes`, `listDisputesByStatus`, `countOpenDisputes`, `getDispute`                                                                                                                      |
| `ProductSwitchService` | `ps.taleeb.taleebbackend.palletizing` | `selectProduct`, `recordProductSwitch`                                                                                                                                                                          |
| `LineStateService`     | `ps.taleeb.taleebbackend.palletizing` | `getLineState` (includes `hasOpenFalet`, `openFaletCount` via `FaletService`)                                                                                                                                   |

### Backend Controllers

| Class                                    | Base Path                           | FALET Endpoints                                                                                                                                                                                                                                                                                    |
| ---------------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PalletizingLineController`              | `/api/v1/palletizing-line`          | `GET /lines/{lineId}/falet`, `POST /lines/{lineId}/falet/convert-to-pallet`, `POST /lines/{lineId}/falet/dispose`, `GET /lines/{lineId}/falet/first-pallet-suggestion`, `POST /lines/{lineId}/handover`, `POST /lines/{lineId}/handover/{id}/confirm`, `POST /lines/{lineId}/handover/{id}/reject` |
| `WebAdminFaletDisputesController`        | `/web/admin/falet-disputes`         | `GET /`, `GET /{id}`, `POST /{id}/action`                                                                                                                                                                                                                                                          |
| `WebAdminLineHandoverDisputesController` | `/web/admin/line-handover-disputes` | All routes redirect to `/web/admin/falet-disputes`                                                                                                                                                                                                                                                 |
| `WebAdminLineStateController`            | `/web/admin/line-state`             | `GET /`, `GET /stream` (SSE), `GET /handovers`, `GET /handovers/{id}`                                                                                                                                                                                                                              |
| `WebAdminPalleteController`              | `/web/admin/palletes`               | `GET /detail` (shows FALET reconciliation)                                                                                                                                                                                                                                                         |

### JPA Entities

| Entity                       | Table                           |
| ---------------------------- | ------------------------------- |
| `FaletCurrentState`          | `falet_current_states`          |
| `FaletEvent`                 | `falet_events`                  |
| `FaletSourceSegment`         | `falet_source_segments`         |
| `FaletDispute`               | `falet_disputes`                |
| `FaletDisputeItem`           | `falet_dispute_items`           |
| `FaletDisputeAction`         | `falet_dispute_actions`         |
| `FaletPalleteReconciliation` | `falet_pallete_reconciliations` |
| `LineHandoverFaletSnapshot`  | `line_handover_falet_snapshots` |
| `LineHandover`               | `line_handovers`                |

### Repositories

| Repository                             | Key Locking Methods                                                                                  |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `FaletCurrentStateRepository`          | `findOpenByLineAndProductForUpdate`, `findByIdForUpdate`, `findOpenByLineAndProductAndAuthForUpdate` |
| `FaletDisputeRepository`               | `findByIdForUpdate`, `findByHandoverId`, `existsByProductionLineIdAndStatus`                         |
| `LineHandoverRepository`               | `findByProductionLineIdAndStatusForUpdate`, `findByIdForUpdate`                                      |
| `FaletPalleteReconciliationRepository` | `findByPalleteId`, `findByHandoverId`, `sumReconciledQuantityByPalleteId`                            |
| `FaletEventRepository`                 | `findByFaletCurrentStateIdOrderByCreatedAtAsc`, `findByProductionLineIdOrderByCreatedAtDesc`         |
| `FaletSourceSegmentRepository`         | `findByFaletCurrentStateIdOrderByCreatedAtAsc`, `findByAuthorizationIdOrderByCreatedAtAsc`           |

### DTOs

| DTO                                                                        | Transport Direction | Endpoint                                     |
| -------------------------------------------------------------------------- | ------------------- | -------------------------------------------- |
| `LineHandoverRequest` (inner: `FaletResolutionEntry`)                      | Request             | `POST /handover`                             |
| `LineHandoverResponse` (inner: `FaletSnapshotItem`, `ReconciledFaletItem`) | Response            | All handover endpoints                       |
| `LineHandoverRejectRequest` (inner: `ItemObservation`)                     | Request             | `POST /handover/{id}/reject`                 |
| `LineHandoverConfirmRequest`                                               | Request             | `POST /handover/{id}/confirm`                |
| `FaletScreenResponse`, `FaletItemResponse`                                 | Response            | `GET /falet`                                 |
| `FirstPalletSuggestionResponse`                                            | Response            | `GET /falet/first-pallet-suggestion`         |
| `ConvertFaletToPalletRequest`, `ConvertFaletToPalletResponse`              | Request / Response  | `POST /falet/convert-to-pallet`              |
| `DisposeFaletRequest`, `DisposeFaletResponse`                              | Request / Response  | `POST /falet/dispose`                        |
| `FaletDisputeResponse` (nested static classes)                             | Response            | Dispute endpoints and Thymeleaf model        |
| `FaletDisputeActionRequest`                                                | Request             | `POST /web/admin/falet-disputes/{id}/action` |

### Enums

| Enum                     | Package                               |
| ------------------------ | ------------------------------------- |
| `FaletCurrentStatus`     | `ps.taleeb.taleebbackend.palletizing` |
| `FaletEventType`         | `ps.taleeb.taleebbackend.palletizing` |
| `FaletOriginType`        | `ps.taleeb.taleebbackend.palletizing` |
| `FaletDisputeStatus`     | `ps.taleeb.taleebbackend.palletizing` |
| `FaletDisputeActionType` | `ps.taleeb.taleebbackend.palletizing` |
| `HandoverFaletAction`    | `ps.taleeb.taleebbackend.palletizing` |

### Key Migrations

| Migration                                                                                  | Purpose                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/main/resources/db/migration/V21__line_handover_module.sql`                            | Creates `line_handovers`, `line_handover_loose_balances` (legacy)                                                                                                                                 |
| `src/main/resources/db/migration/V29__falet_redesign.sql`                                  | Creates `falet_current_states`, `falet_events`, `line_handover_falet_snapshots`; migrates legacy data                                                                                             |
| `src/main/resources/db/migration/V35__falet_lifecycle_disputes_shift_history.sql`          | Creates `falet_source_segments`, `falet_disputes`, `falet_dispute_items`, `falet_dispute_actions`, `shift_execution_snapshots`; adds `authorization_id` + `origin_type` to `falet_current_states` |
| `src/main/resources/db/migration/V37__structured_handover_rejection_and_receipt_notes.sql` | Adds structured rejection fields; adds `observed_quantity` to snapshots                                                                                                                           |
| `src/main/resources/db/migration/V38__falet_reconciliation_and_production_corrections.sql` | Creates `falet_pallete_reconciliations`, `production_corrections`; adds `production_status` to `palletes`                                                                                         |

### Key Documentation Files

| Document                                                | Location                                                       | Status                                                             |
| ------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------ |
| `FALET_LIFECYCLE_DISPUTES_FRONTEND_SPEC.md`             | `docs/FALET_LIFECYCLE_DISPUTES_FRONTEND_SPEC.md`               | Active spec; aligned with current code                             |
| `FALET_REDESIGN_FRONTEND_HANDOFF.md`                    | `docs/FALET_REDESIGN_FRONTEND_HANDOFF.md`                      | Active; covers V29 redesign                                        |
| `HANDOVER_REJECTION_AND_RECEIPT_NOTES_FRONTEND_SPEC.md` | `HANDOVER_REJECTION_AND_RECEIPT_NOTES_FRONTEND_SPEC.md` (root) | Active; covers V37 structured rejection                            |
| `FRONTEND_AI_AGENT_HANDOFF.md`                          | `FRONTEND_AI_AGENT_HANDOFF.md` (root)                          | Active; marks `faletResolutions` as pending Flutter implementation |

---

_Document based on codebase state as of April 2026. All behavioral descriptions are derived from actual source code inspection unless explicitly marked as inference or assumption. Primary divergence risk: Flutter app source code is not in this repository; all Flutter-side statements are derived from handoff documentation and should be validated against the Flutter app repository separately._
