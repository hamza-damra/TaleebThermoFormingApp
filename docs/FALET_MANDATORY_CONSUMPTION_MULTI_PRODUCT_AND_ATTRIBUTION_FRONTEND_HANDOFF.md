# FALET Mandatory Consumption, Multi-Product Handover & Attribution — Frontend Handoff

> **Version:** V40 (dispute decision model)
> **Date:** 2025-06-15

---

## 1. Overview

This document covers three interconnected backend changes that affect mobile and admin frontend behavior:

1. **Mandatory first-pallet consumption** — regular pallet creation is blocked when an eligible FALET exists for the current product.
2. **Multi-product handover disputes** — only quantity-mismatched items create dispute records; matched items are auto-accepted.
3. **Simplified admin dispute UI** — per-item "who is right" decision model replaces the old 4-action form.

---

## 2. Mandatory First-Pallet Consumption

### Behavior

When an operator starts producing on a line and an eligible FALET exists for the **current product**, `POST /api/v1/palletizing/lines/{lineId}/pallets` will return:

```json
{
  "success": false,
  "error": {
    "code": "FALET_MUST_BE_CONSUMED_FIRST",
    "message": "Eligible FALET exists for product {name} on this line. Use convert-to-pallet to consume it first."
  }
}
```

**HTTP Status:** `409 Conflict`

### Eligibility Conditions (same as first-pallet suggestion)

- **Same-session return:** OPEN FALET for same line + product + current auth.
- **Confirmed handover:** OPEN FALET (non-DISPUTE_RELEASE) for same product, with a confirmed handover matching the current auth.

### What Does NOT Block

- FALET for a **different product** than the one being created.
- `DISPUTE_RELEASE` origin FALETs (manager-resolved, handled separately).
- No FALET exists at all.

### Frontend Action Required

- On receiving `FALET_MUST_BE_CONSUMED_FIRST`, show a clear Arabic message directing the operator to the FALET screen.
- Suggested message: `"يوجد فالت مفتوح لهذا المنتج يجب استهلاكه أولاً. اذهب إلى شاشة الفالت لتحويله إلى بالتة."`
- The existing `GET /api/v1/palletizing/lines/{lineId}/falet/first-pallet-suggestion` endpoint still works as before for proactive UI hints.

---

## 3. Multi-Product Handover Disputes

### Key Rule: Quantity Match = No Dispute

If `senderDeclaredQty == receiverObservedQty` for any item, that item:
- Is **auto-accepted** (no dispute record created).
- Does **not** appear in admin FALET disputes.
- FALET stays `OPEN` with its original quantity.
- Any non-quantity notes are stored on the `LineHandover` record (not as a dispute).

### Quantity Mismatch Items

If `senderDeclaredQty != receiverObservedQty`:
- FALET stays `OPEN` (not `DISPUTED`) with `quantity = receiverObservedQty` (operational).
- A `FaletDisputeItem` is created with sender/receiver quantities for admin review.
- The dispute only contains mismatched items.

### Undeclared FALET (sender=0, receiver>0)

- A new FALET is created as `OPEN` with `quantity = receiverObservedQty`.
- Default attribution: sender (they forgot to declare).
- Dispute item created with `senderDeclaredQuantity=0`.

### Frontend Impact

- Accepted items in a multi-product handover **still trigger mandatory first-pallet consumption** when the operator later creates a pallet for that product.
- The rejection response still returns all FALET snapshots (including matched ones), but only mismatched items will appear in admin disputes.

---

## 4. Admin Dispute Decision Model

### Old Model (Legacy)

4 actions: DISPOSE, PALLETIZE, RELEASE, HOLD — with manual quantity input.

### New Model (V40)

Per-item binary decision: **"المسلّم صح" (Sender Right)** or **"المستلم صح" (Receiver Right)**.

### Endpoint

```
POST /web/admin/falet-disputes/{disputeId}/decide
```

**Parameters (form POST):**
| Parameter | Type | Description |
|-----------|------|-------------|
| `disputeItemId` | Long | ID of the specific dispute item |
| `decision` | Enum | `SENDER_RIGHT` or `RECEIVER_RIGHT` |

### Decision Outcomes

#### Sender > Receiver (e.g., sender=13, receiver=8, diff=5)

| Decision | Result | Arabic Message |
|----------|--------|----------------|
| **المسلّم صح** | diff=5 recorded against receiver | `"المسلّم أنتج 13 عبوة فعلاً. الفرق 5 عبوة مسجّل على المستلم {name}. الكمية التشغيلية 8 عبوة."` |
| **المستلم صح** | diff=5 recorded against sender | `"المسلّم أعلن بزيادة. الفرق 5 عبوة مسجّل على المسلّم {name}. الكمية التشغيلية 8 عبوة."` |

#### Sender < Receiver (e.g., sender=5, receiver=8, diff=3)

| Decision | Result | Arabic Message |
|----------|--------|----------------|
| **المسلّم صح** | S attributed to sender, diff to receiver | `"تأكيد: 5 عبوة منسوبة للمسلّم {name}، و3 عبوة منسوبة للمستلم {name} كإنتاج جديد."` |
| **المستلم صح** | All R re-attributed to sender | `"تم نقل 3 عبوة من إنتاج المستلم الجديد إلى نسبة المسلّم {name}. الكمية الكاملة 8 عبوة منسوبة للمسلّم."` |

#### Undeclared (sender=0, receiver>0, e.g., receiver=7)

| Decision | Result | Arabic Message |
|----------|--------|----------------|
| **المسلّم صح** | All re-attributed from sender to receiver | `"تم نقل 7 عبوة من نسبة المسلّم {name} إلى المستلم {name}."` |
| **المستلم صح** | Stays attributed to sender | `"لا تغيير. 7 عبوة تبقى منسوبة للمسلّم {name} (فالت غير مُعلن)."` |

### Invariant

`operationalQty = receiverObservedQty` **always**. Manager decisions never change the operational quantity on the line.

### Response Fields per Item

| Field | Type | Description |
|-------|------|-------------|
| `senderDeclaredQuantity` | Integer | What sender declared |
| `receiverObservedQuantity` | Integer | What receiver observed |
| `operationalQuantity` | Integer | = receiverObservedQuantity (immutable) |
| `decision` | String | `SENDER_RIGHT`, `RECEIVER_RIGHT`, or null |
| `decisionResultNotes` | String | System-generated Arabic result text |
| `finalSenderAttributedQty` | Integer | Final qty attributed to sender |
| `finalReceiverAttributedQty` | Integer | Final qty attributed to receiver |
| `senderDifferenceQty` | int | Difference recorded against sender |
| `receiverDifferenceQty` | int | Difference recorded against receiver |
| `decidedAtDisplay` | String | Arabic formatted timestamp |

### Legacy Compatibility

The old action form (DISPOSE/PALLETIZE/RELEASE/HOLD) is still functional via `POST /{id}/action` for pre-V40 disputes that lack `senderDeclaredQuantity`. The admin UI collapses this into an "advanced actions" section.

---

## 5. Error Codes Reference

| Code | HTTP | When |
|------|------|------|
| `FALET_MUST_BE_CONSUMED_FIRST` | 409 | Regular pallet creation when eligible FALET exists |
| `FALET_DISPUTE_NOT_FOUND` | 404 | Invalid dispute ID |
| `FALET_DISPUTE_ALREADY_RESOLVED` | 409 | Decision on already-resolved dispute |
| `FALET_DISPUTE_ITEM_NOT_FOUND` | 404 | Invalid item ID within dispute |
| `VALIDATION_ERROR` | 400 | Already-decided item, invalid decision type |

---

## 6. Admin UI Card Layout (Thymeleaf)

Each dispute item is rendered as a card showing:
1. **Product name** (header)
2. **4-column quantity row:** sender qty, receiver qty, operational qty, disputed difference
3. **Decision result** (if decided): green alert with Arabic result message + attribution badges
4. **Two decision buttons** (if pending): "المسلّم صح" (outline-primary) / "المستلم صح" (outline-success) with confirmation dialogs

Decided cards receive `opacity-75` styling to visually distinguish resolved items.
