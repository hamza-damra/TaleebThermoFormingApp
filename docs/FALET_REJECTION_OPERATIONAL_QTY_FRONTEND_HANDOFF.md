# FALET Rejection — Operational Quantity Fix (Frontend Handoff)

> **Date:** 2026-04-13
> **Backend fix applied:** Yes — `LineHandoverService.rejectHandover()` + `FaletCurrentStateRepository`

---

## 1. Summary

A critical backend bug caused the FALET screen to display `senderDeclaredQty` (e.g. 10) instead of `receiverObservedQty` (e.g. 5) after a handover rejection with quantity mismatch. The root cause was in the rejection flow's handling of **multi-entry consolidation** — when multiple `FaletCurrentState` rows existed for the same product on a line, only the representative was updated; the rest remained OPEN with stale quantities, inflating the total.

**The bug was backend-side. It is now fixed.**

---

## 2. Business Rule (Unchanged)

For any quantity-mismatch dispute after handover rejection:

| Field | Value |
|-------|-------|
| **Operational / visible FALET on line** | `receiverObservedQty` — always |
| **Dispute difference** | `abs(senderDeclaredQty - receiverObservedQty)` — accounting only |
| **After admin SENDER_RIGHT** | Visible FALET unchanged (still `receiverObservedQty`) |
| **After admin RECEIVER_RIGHT** | Visible FALET unchanged (still `receiverObservedQty`) |

Admin decisions affect **attribution/accounting only** — they never inflate visible operational FALET.

---

## 3. What Was Wrong

### Root cause: multi-entry consolidation gap

`createHandover()` deduplicates open FALET by `product_type_id` into **one snapshot** with a summed quantity, linking to a single **representative** `FaletCurrentState`. Example:

- `FaletCurrentState #A`: product Red, qty=6 (from previous session carry-forward)
- `FaletCurrentState #B`: product Red, qty=4 (from current session product switch)
- Snapshot: product Red, qty=10, linked to `#B` as representative

On rejection with `receiverObservedQty=5`:
- **Before fix:** Only `#B` was set to qty=5. `#A` stayed OPEN with qty=6. Total visible = **11** (wrong).
- **After fix:** `#B` set to qty=5, `#A` resolved with qty=0. Total visible = **5** (correct).

### Single-entry case

For the common case with one `FaletCurrentState` per product:
- `locked.setQuantity(receiverObservedQty)` was already correct.
- The bug may have manifested because the frontend read from the **handover response snapshot** (`faletItems[].quantity` = sender declared) instead of `GET /falet` (correct).

---

## 4. Backend Code Paths Inspected

| File | Method | Verdict |
|------|--------|---------|
| `LineHandoverService.java` | `rejectHandover()` | **Fixed** — now consolidates all open entries for the same line+product |
| `LineHandoverService.java` | `toResponse()` | Correct — `faletItems[].quantity` is intentionally the snapshot (sender declared) value |
| `FaletService.java` | `getOpenFalet()` | Correct — reads `FaletCurrentState.quantity` |
| `FaletService.java` | `toFaletItemResponse()` | Correct — uses `state.getQuantity()` |
| `FaletDisputeService.java` | `executeDecision()` | Correct — does not touch `FaletCurrentState.quantity` |
| `FaletCurrentStateRepository.java` | N/A | Added `findAllByProductionLineIdAndProductTypeIdAndStatus()` |

---

## 5. What Changed in Backend

### `FaletCurrentStateRepository.java`
- **Added:** `List<FaletCurrentState> findAllByProductionLineIdAndProductTypeIdAndStatus(Long, Long, FaletCurrentStatus)` — returns ALL open entries for a line+product (not just one).

### `LineHandoverService.rejectHandover()`
- **After** setting the representative's quantity to `receiverObservedQty`, the code now queries ALL open `FaletCurrentState` entries for the same line + product type.
- Any entries **other than the representative** are resolved (status=`RESOLVED`, qty=0) with an audit event.
- This guarantees total visible FALET for that product = `receiverObservedQty` exactly.

### No DTO/response changes
- `FaletItemResponse.quantity` still comes from `FaletCurrentState.quantity` — now correct.
- `LineHandoverResponse.FaletSnapshotItem.quantity` still returns the snapshot's sender-declared quantity — this is intentional historical data, not operational FALET.

---

## 6. Correct API Fields for Frontend

### FALET screen (operator view)
**Endpoint:** `GET /api/v1/palletizing-line/lines/{lineId}/falet`
**Response:** `FaletScreenResponse`

```json
{
  "faletItems": [
    {
      "faletId": 42,
      "productTypeId": 5,
      "productTypeName": "Red 20kg",
      "quantity": 5,          // ← THIS is the correct operational quantity
      "status": "OPEN",
      "originType": "PRODUCT_SWITCH",
      "sourceOperatorName": "Ahmad"
    }
  ],
  "totalOpenFaletCount": 1,
  "hasOpenFalet": true
}
```

**Use `faletItems[].quantity`** — this is `FaletCurrentState.quantity`, which equals `receiverObservedQty` after rejection.

### Handover rejection response
**Endpoint:** `POST /api/v1/palletizing-line/lines/{lineId}/handovers/{id}/reject`
**Response:** `LineHandoverResponse`

```json
{
  "faletItems": [
    {
      "faletId": 42,
      "productTypeId": 5,
      "productTypeName": "Red 20kg",
      "quantity": 10,          // ← sender declared (snapshot), NOT operational
      "observedQuantity": 5    // ← receiver observed
    }
  ]
}
```

**Do NOT use `faletItems[].quantity`** from the handover response as visible FALET. This is the historical snapshot (sender declared). After rejection, call `GET /falet` to get the correct operational quantities.

### Dispute detail (admin view)
**Endpoint:** `GET /web/admin/falet-disputes/{id}` or API equivalent

```json
{
  "items": [
    {
      "senderDeclaredQuantity": 10,
      "receiverObservedQuantity": 5,
      "operationalQuantity": 5,   // ← correct visible FALET
      "disputedQuantity": 5        // ← difference (accounting only)
    }
  ]
}
```

---

## 7. Examples

### Wrong (before fix)

| Step | Value |
|------|-------|
| Sender declared | 10 |
| Receiver observed | 5 |
| After rejection: FALET screen shows | **10** (or 11 with multi-entry) |

### Correct (after fix)

| Step | Value |
|------|-------|
| Sender declared | 10 |
| Receiver observed | 5 |
| After rejection: FALET screen shows | **5** |
| Dispute difference | **5** (accounting only, not visible FALET) |
| After SENDER_RIGHT decision | FALET still **5** |
| After RECEIVER_RIGHT decision | FALET still **5** |

---

## 8. What Flutter Must Verify

1. **FALET screen:** Must read from `GET /falet` → `faletItems[].quantity`, NOT from cached handover response data.
2. **After rejection:** Re-fetch FALET data via `GET /falet`. Do not use the `LineHandoverResponse.faletItems[].quantity` field — that's the snapshot (sender declared) value.
3. **Dispute detail display:** Use `operationalQuantity` for "usable FALET" and `disputedQuantity` for "difference under dispute".
4. **Post-decision display:** Verify that after any admin decision (SENDER_RIGHT or RECEIVER_RIGHT), the FALET screen still shows the same operational quantity — decisions only change attribution, never inflate visible FALET.
5. **First-pallet suggestion dialog:** If `fetchFirstPalletSuggestion` fails (500 error), fall back to `GET /falet` items and match by product. The suggestion endpoint was also recently fixed (separate `FOR UPDATE` bug in read-only transaction).
