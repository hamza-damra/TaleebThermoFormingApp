# FALET Zero-Receiver & Post-Decision Attribution — Frontend Handoff

## Summary

Backend changes affect how FALETs behave when the receiver observes 0 quantity, how the mobile FALET screen filters items, and how manager dispute decisions track attribution execution status.

---

## 1. Zero-Receiver FALET Rule

When the incoming operator rejects a handover and reports `observedQuantity = 0` for a FALET item:

- The FALET's `status` is set to **RESOLVED** (not OPEN)
- The FALET's `quantity` is set to **0**
- A `FaletDisputeItem` is still created for manager review
- The FALET will **NOT appear** on the mobile FALET screen

**Frontend impact**: No change needed. The mobile FALET screen endpoint already only returns OPEN items, and zero-qty items are now filtered out server-side.

---

## 2. Mobile FALET Screen Filters

The following endpoints now exclude FALET items with `quantity <= 0`:

| Endpoint / Method | Effect |
|---|---|
| `GET /api/v1/falet/open/{lineId}` | Zero-qty items excluded from response list |
| First-pallet consumption guard | Zero-qty FALETs don't trigger consumption requirement |
| First-pallet suggestion | Zero-qty FALETs don't generate suggestions |
| `GET /api/v1/falet/exists/{lineId}` | Zero-qty FALETs excluded from count |

**Frontend impact**: None. These are server-side filters. The mobile app should behave correctly without changes.

---

## 3. New Fields on Dispute Item Response

Three new fields are added to each `DisputeItemResponse` in the dispute detail API:

```json
{
  "items": [
    {
      "id": 500,
      "productTypeName": "Red 20kg",
      "senderDeclaredQuantity": 5,
      "receiverObservedQuantity": 0,
      "operationalQuantity": 0,
      "decision": "SENDER_RIGHT",
      "attributionExecutionStatus": "COMPLETE",
      "appliedAdjustmentQty": 5,
      "remainingAdjustmentQty": 0
    }
  ]
}
```

### Field definitions

| Field | Type | Values | Meaning |
|---|---|---|---|
| `attributionExecutionStatus` | String (nullable) | `COMPLETE`, `PARTIAL`, `MANUAL_RECONCILIATION_REQUIRED`, `NOT_APPLICABLE`, `null` | Status of post-decision attribution adjustment |
| `appliedAdjustmentQty` | Integer | ≥ 0 | Number of cartons successfully re-attributed |
| `remainingAdjustmentQty` | Integer | ≥ 0 | Number of cartons that could not be adjusted (insufficient fresh qty) |

### Status meanings

| Status | When | Admin UI suggestion |
|---|---|---|
| `null` | Item not yet decided | Show nothing |
| `NOT_APPLICABLE` | Decision didn't require cross-session adjustment (e.g., RECEIVER_RIGHT where no shift needed) | Show "لا حاجة لتعديل" or hide |
| `COMPLETE` | Full adjustment applied successfully | Show "✓ تم التعديل بالكامل" |
| `PARTIAL` | Some adjustment applied, remainder pending | Show "⚠ تعديل جزئي — متبقي X عبوة" with `remainingAdjustmentQty` |
| `MANUAL_RECONCILIATION_REQUIRED` | No fresh production found to adjust | Show "⚠ مطلوب تسوية يدوية — X عبوة" with `remainingAdjustmentQty` |

---

## 4. Manager Decision Effects

Manager decisions do **NOT** change the operational quantity (which always equals `receiverObservedQty`). They only affect **production attribution** — who gets credit for cartons.

| Scenario | Decision | Visible FALET | Attribution effect |
|---|---|---|---|
| sender=5, receiver=0 | SENDER_RIGHT | None (RESOLVED) | 5 cartons re-attributed from receiver's fresh production → sender |
| sender=5, receiver=0 | RECEIVER_RIGHT | None (RESOLVED) | No change (差 recorded on sender, not receiver) |
| sender=13, receiver=8 | SENDER_RIGHT | 8 (OPEN) | 5 cartons re-attributed from receiver's fresh production → sender |
| sender=13, receiver=8 | RECEIVER_RIGHT | 8 (OPEN) | No re-attribution (差 recorded on sender) |

---

## 5. `DISPUTE_RESOLUTION` Breakdown Semantics

The `DISPUTE_RESOLUTION` contribution source in `PalleteCreationBreakdown` is:

- **Attribution reallocation only** — does not inflate pallet totals
- **Same-product scoped** — only adjusts pallets of the same product type
- **Cumulative across pallets** — walks receiver's pallets oldest-first until the disputed qty is covered

Analytics and session summaries:
- Product-level totals (`SUM(p.quantity)`) are unchanged
- Operator attribution changes when operator filters are applied
- Session snapshots are immutable point-in-time captures and are NOT retroactively updated

---

## 6. Scenario Examples

### A. sender=2, receiver=0, SENDER_RIGHT

1. Handover rejected with `observedQuantity=0`
2. FALET → RESOLVED, qty=0. Not visible on mobile.
3. Dispute item created: `disputedQuantity=2`
4. Manager decides SENDER_RIGHT
5. Backend walks receiver's fresh pallets (same product, oldest first)
6. Deducts 2 from receiver's FRESH breakdowns → creates DISPUTE_RESOLUTION for sender
7. `attributionExecutionStatus = "COMPLETE"`, `appliedAdjustmentQty = 2`

### B. sender=5, receiver=0, SENDER_RIGHT, only 3 fresh cartons available

1. Same as above, but receiver only produced 3 fresh cartons of this product
2. Backend deducts 3, cannot find remaining 2
3. `attributionExecutionStatus = "PARTIAL"`, `appliedAdjustmentQty = 3`, `remainingAdjustmentQty = 2`
4. Admin UI should flag this for manual reconciliation

### C. sender=13, receiver=8, RECEIVER_RIGHT

1. FALET stays OPEN with qty=8
2. Manager decides RECEIVER_RIGHT
3. No cross-session adjustment needed (差 is on sender)
4. `attributionExecutionStatus = "NOT_APPLICABLE"`
