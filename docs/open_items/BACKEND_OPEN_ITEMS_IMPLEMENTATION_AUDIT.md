# Backend Open Items Implementation Audit

## 1. Audit Scope

Full implementation audit of the open items management feature (loose balances + received incomplete pallets) against the latest approved workflow decisions.

---

## 2. What Was Found in the Current Implementation

### Database Schema (V25 Migration)

| Table | Purpose | Status |
|-------|---------|--------|
| `loose_balance_events` | Immutable audit trail for loose balance lifecycle | ✅ Implemented |
| `pallete_creation_breakdowns` | How each pallet was composed (loose, fresh, incomplete) | ✅ Implemented |
| `session_incomplete_pallets` | Current-state for received incomplete pallet per session | ✅ Implemented |
| `incomplete_pallet_events` | Immutable audit trail for incomplete pallet lifecycle | ✅ Implemented |

All tables have proper foreign keys, indexes, and constraints.

### Enums

| Enum | Values | Status |
|------|--------|--------|
| `LooseBalanceEventType` | RECORDED_FROM_PRODUCT_SWITCH, RECEIVED_FROM_HANDOVER, HANDED_OVER_OUT, CONSUMED_IN_PALLET, ADDED_FRESH_FOR_PALLET, ADJUSTED, WRITTEN_OFF, DISPUTED_HANDOVER_REFERENCE | ✅ |
| `IncompletePalletEventType` | RECEIVED_FROM_HANDOVER, COMPLETED_INTO_PALLET, HANDED_OVER_OUT, DISPUTED_HANDOVER_REFERENCE | ✅ |
| `SessionIncompletePalletStatus` | PENDING, COMPLETED, HANDED_OVER | ✅ |
| `PalleteCreationMode` | STANDARD, FROM_LOOSE_ONLY, FROM_LOOSE_PLUS_FRESH, FROM_INCOMPLETE_PALLET, FROM_INCOMPLETE_PALLET_PLUS_FRESH | ✅ |

### Entities

| Entity | Table | Status |
|--------|-------|--------|
| `LooseBalanceEvent` | `loose_balance_events` | ✅ |
| `PalleteCreationBreakdown` | `pallete_creation_breakdowns` | ✅ |
| `SessionIncompletePallet` | `session_incomplete_pallets` | ✅ |
| `IncompletePalletEvent` | `incomplete_pallet_events` | ✅ |

### Repositories

| Repository | Key Methods | Status |
|-----------|-------------|--------|
| `LooseBalanceEventRepository` | findFirst/exists by auth+product+eventType, findByAuth | ✅ |
| `PalleteCreationBreakdownRepository` | findByPalleteId | ✅ |
| `SessionIncompletePalletRepository` | findByAuthAndStatus, findByAuthAndStatusForUpdate (SELECT FOR UPDATE) | ✅ |
| `IncompletePalletEventRepository` | findByAuthOrderByCreatedAt | ✅ |
| `SessionProductBalanceRepository` | findByAuthAndProductTypeForUpdate (SELECT FOR UPDATE), findByAuthAndLooseCountGT | ✅ |

### Services

| Service | Methods | Status |
|---------|---------|--------|
| `LooseBalanceService` | getOpenItems(), producePalletFromLoose() | ✅ |
| `SessionIncompletePalletService` | completeIncompletePallet() | ✅ |
| `ProductSwitchService` | recordProductSwitch() — now records audit event | ✅ |
| `LineHandoverService` | createHandover (auto-include), confirmHandover (separate transfer), rejectHandover (dispute events) | ✅ |

### Controller Endpoints

| Endpoint | Method | Status |
|----------|--------|--------|
| `GET /lines/{lineId}/open-items` | Returns combined loose balances + received incomplete pallet | ✅ |
| `POST /lines/{lineId}/loose-balances/produce-pallet` | Creates pallet from loose balance | ✅ |
| `POST /lines/{lineId}/incomplete-pallet/complete` | Completes received incomplete pallet | ✅ |

### Error Codes

| Code | Purpose | Status |
|------|---------|--------|
| `INVALID_LOOSE_BALANCE` | Loose count >= packageQuantity | ✅ |
| `INSUFFICIENT_LOOSE_BALANCE` | Not enough loose to consume | ✅ |
| `LOOSE_BALANCE_NOT_FOUND` | No loose balance row for product type | ✅ |
| `INCOMPLETE_PALLET_NOT_FOUND` | No pending received incomplete pallet | ✅ |
| `INCOMPLETE_PALLET_ALREADY_RESOLVED` | Already completed or handed over | ✅ |
| `INCOMPLETE_PALLET_HANDOVER_CONFLICT` | Two different product types in handover | ✅ |

---

## 3. Comparison Against Approved Workflow

### A) Dedicated management screen backend support
- **Requirement**: One UX screen for loose balances + received incomplete pallet, but separate backend concepts.
- **Implementation**: `GET /open-items` returns `OpenItemsResponse` with `looseBalances[]` and `receivedIncompletePallet` as separate fields. ✅

### B) Loose balance rules
- **Persisted safely**: In `session_product_balances` ✅
- **Never disappears silently**: Auto-included in handover create; audit trail on every state change ✅
- **Sources**: Product switch (`RECORDED_FROM_PRODUCT_SWITCH`) and confirmed handover (`RECEIVED_FROM_HANDOVER`) ✅
- **Carry-forward**: `createHandover` queries `findByAuthorizationIdAndLoosePackageCountGreaterThan` and auto-includes ✅
- **Confirm transfers**: `confirmHandover` calls `transferToIncomingSession` + records `RECEIVED_FROM_HANDOVER` event ✅
- **Reject does NOT transfer**: Only `DISPUTED_HANDOVER_REFERENCE` event recorded ✅

### C) Automatic same-session switch-back reuse REMOVED
- **Requirement**: Backend must NOT auto-consume loose balance when returning to same product.
- **Implementation**: `ProductSwitchService.recordProductSwitch()` only upserts the balance count, never deducts. `PalletizingService.createPalletForLine()` does NOT touch `session_product_balances` at all. Loose consumption is ONLY through the explicit `producePalletFromLoose` endpoint. ✅

### D) Received incomplete pallet rules
- **Visible only when received from handover**: `SessionIncompletePallet` requires `sourceHandover` (NOT NULL). Created only in `confirmHandover`. ✅
- **NOT same-session concept**: Never created during normal production flow ✅
- **NOT merged with loose balance**: Stored in `session_incomplete_pallets`, separate from `session_product_balances` ✅
- **Own audit trail**: `incomplete_pallet_events` table ✅
- **Carry-forward**: `createHandover` checks for pending SIP and auto-includes, marking it `HANDED_OVER` ✅
- **Reject does NOT transfer**: Only `DISPUTED_HANDOVER_REFERENCE` event ✅

### E) Source-of-truth boundaries
All confirmed correct:
- Loose balance current state → `session_product_balances`
- Loose balance handover snapshot → `line_handover_loose_balances`
- Loose balance immutable log → `loose_balance_events`
- Pallet composition → `pallete_creation_breakdowns`
- Incomplete pallet current state → `session_incomplete_pallets`
- Incomplete pallet immutable log → `incomplete_pallet_events`

---

## 4. What Was Missing or Incorrect (and Fixed)

### Issue 1: Outgoing HANDED_OVER_OUT events lacked sourceHandover reference

**Problem**: In `createHandover`, loose balance `HANDED_OVER_OUT` events were recorded BEFORE the handover was persisted (via `saveAndFlush`), so `sourceHandover` was always null on these events.

**Fix**: Restructured `createHandover` to build handover loose balance entries first, save the handover via `saveAndFlush`, then record `HANDED_OVER_OUT` events with the persisted handover reference.

### Issue 2: `sourceHandoverId` in `LooseBalanceItemResponse` was never populated

**Problem**: The DTO had the field but `buildLooseBalanceItems` never set it, making it always null in the API response.

**Fix**: Updated `buildLooseBalanceItems` to query `findFirstByAuthorizationIdAndProductTypeIdAndEventType(RECEIVED_FROM_HANDOVER)` and extract the source handover ID when the balance originated from a handover.

---

## 5. Loose Balance Workflow Summary

```
Product Switch → RECORDED_FROM_PRODUCT_SWITCH event + upsert session_product_balances
       ↓
Open Items Screen → GET /open-items (shows all non-zero balances with origin)
       ↓
Produce Pallet → POST /loose-balances/produce-pallet
                  → CONSUMED_IN_PALLET event
                  → ADDED_FRESH_FOR_PALLET event (if fresh > 0)
                  → pallete_creation_breakdowns record
                  → session_product_balances deducted
       ↓
Handover Create → auto-includes all non-zero balances
                   → HANDED_OVER_OUT events (with handover reference)
                   → snapshot in line_handover_loose_balances
       ↓
Handover Confirm → RECEIVED_FROM_HANDOVER events
                    → session_product_balances created for incoming auth
       ↓
Handover Reject → DISPUTED_HANDOVER_REFERENCE events only
                   → NO transfer to receiver
```

---

## 6. Received Incomplete Pallet Workflow Summary

```
Handover Confirm (with incomplete pallet) →
    → SessionIncompletePallet created (status=PENDING, sourceHandover set)
    → RECEIVED_FROM_HANDOVER event in incomplete_pallet_events
       ↓
Open Items Screen → GET /open-items (shows receivedIncompletePallet if PENDING)
       ↓
Complete → POST /incomplete-pallet/complete
           → SessionIncompletePallet status → COMPLETED, resolvedPallete set
           → COMPLETED_INTO_PALLET event
           → pallete_creation_breakdowns record
       ↓
OR: Handover Create (unresolved) → auto-includes PENDING SIP
                                    → SIP status → HANDED_OVER
                                    → HANDED_OVER_OUT event
       ↓
Next Confirm → new SessionIncompletePallet for incoming auth
       ↓
Handover Reject → DISPUTED_HANDOVER_REFERENCE event only
                   → NO SessionIncompletePallet created for receiver
```

---

## 7. Carry-Forward Behavior Summary

| Item | On Handover Create | On Confirm | On Reject |
|------|-------------------|------------|-----------|
| **Loose balances (non-zero)** | Auto-included in handover snapshot + HANDED_OVER_OUT events | Transferred to incoming session_product_balances + RECEIVED_FROM_HANDOVER events | NOT transferred; DISPUTED_HANDOVER_REFERENCE events only |
| **Pending incomplete pallet** | Auto-included (combined if same product, error if different) + HANDED_OVER_OUT event | New SessionIncompletePallet created for incoming auth + RECEIVED_FROM_HANDOVER event | NOT transferred; DISPUTED_HANDOVER_REFERENCE event only |

---

## 8. Transaction / Concurrency Notes

| Operation | Lock Strategy |
|-----------|---------------|
| `producePalletFromLoose` | `SELECT ... FOR UPDATE` on `session_product_balances` row |
| `completeIncompletePallet` | `SELECT ... FOR UPDATE` on `session_incomplete_pallets` row |
| `createHandover` | `SELECT ... FOR UPDATE` on pending handover + unique constraint catch |
| `confirmHandover` | `findByIdForUpdate` on handover row |
| `rejectHandover` | `findByIdForUpdate` on handover row |
| `recordProductSwitch` | No row lock (line-scoped, single-device per line) |

All write operations are `@Transactional`. Events are published within the transaction boundary using Spring's synchronous `ApplicationEventPublisher`.

---

## 9. Verification Scenarios Checked

| # | Scenario | Result |
|---|----------|--------|
| 1 | Product switch records loose balance correctly | ✅ Pass |
| 2 | Switch-back does NOT auto-consume | ✅ Pass |
| 3 | Loose balance viewable via open-items | ✅ Pass |
| 4 | Loose from confirmed handover appears | ✅ Pass |
| 5 | Produce pallet from loose only | ✅ Pass |
| 6 | Produce pallet from loose + fresh | ✅ Pass |
| 7 | Unresolved loose auto-carried in handover | ✅ Pass |
| 8 | Reject does NOT merge into receiver balance | ✅ Pass |
| 9 | Incomplete pallet only from confirmed handover | ✅ Pass |
| 10 | NOT treated as same-session concept | ✅ Pass |
| 11 | Separate current-state from loose balance | ✅ Pass |
| 12 | Separate audit trail | ✅ Pass |
| 13 | Carry-forward if unresolved | ✅ Pass |
| 14 | Reject does NOT merge incomplete pallet | ✅ Pass |
| 15 | Standard pallet creation still works | ✅ Pass |
| 16 | Pallet quantity semantics correct | ✅ Pass |
| 17 | Session summary still works | ✅ Pass |
| 18 | Line state still works | ✅ Pass |
| 19 | Handover create/confirm/reject works | ✅ Pass |
| 20 | No operational state disappears silently | ✅ Pass |

---

## 10. Remaining Risks / Notes

1. **H2 FK warnings in tests**: Integration tests using H2 show warnings about missing FK target tables (`line_operator_authorizations`, `line_handovers`). These are Hibernate `create-drop` ordering issues in H2 only — not production (MySQL). The tests pass despite warnings.

2. **`ApiAuthorizationMatrixTest` pre-existing failures**: 5 tests fail with 404 on movement endpoints. These are pre-existing and unrelated to open items changes.

3. **Event publication timing**: `LineStateChangedEvent` is published inside the transaction. If a listener throws, the entire transaction rolls back. This is existing project-wide behavior, not specific to open items.
