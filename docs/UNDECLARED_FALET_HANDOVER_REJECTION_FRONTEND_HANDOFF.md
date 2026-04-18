# Undeclared FALET Handover Rejection - Frontend Handoff

## 1. The New Scenario Supported

A new handover rejection reason has been added: **Undeclared FALET Found**.

**Business scenario:**
- The outgoing operator creates a handover **without declaring any FALET**.
- The handover review screen shows **no FALET items** in the snapshot.
- The incoming operator arrives at the line and physically finds FALET cartons on the floor / at the work area.
- The incoming operator rejects the handover because there is FALET in reality that was not declared.

**Key behavior:**
- The **product is NOT chosen by the incoming operator**. The backend automatically uses the line's **current active product**.
- The frontend only needs to collect: **observed quantity** (required, > 0) and **optional notes**.
- This is a separate rejection reason from "incorrect quantity" and "other reason". All three can be used independently or in combination.

---

## 2. What Backend Changed

### New rejection reason flag
- `LineHandover` entity: new boolean column `rejection_undeclared_falet` (default `false`)
- `FaletDispute` entity: same new boolean column
- DB migration `V40__undeclared_falet_rejection.sql` adds the columns

### New enums
- `FaletOriginType.UNDECLARED_AT_HANDOVER` — marks the `FaletCurrentState` created for the undeclared FALET
- `FaletEventType.DISCOVERED_UNDECLARED_AT_HANDOVER` — audit event type

### Rejection service behavior
When `undeclaredFaletFound = true`:
1. Validates `undeclaredFaletObservedQuantity` is present and > 0
2. Reads `line.currentProductType` — if null, throws `NO_ACTIVE_PRODUCT_FOR_UNDECLARED_FALET`
3. Creates a new `FaletCurrentState` with status `DISPUTED` and `originType = UNDECLARED_AT_HANDOVER`
4. Adds a `LineHandoverFaletSnapshot` with `quantity = 0` (outgoing declared nothing) and `observedQuantity = N`
5. Creates a `FaletDisputeItem` for admin resolution
6. Records a `DISCOVERED_UNDECLARED_AT_HANDOVER` audit event

### Response DTOs updated
- `LineHandoverResponse` now includes `rejectionUndeclaredFalet: Boolean`
- `FaletDisputeResponse` now includes `rejectionUndeclaredFalet: Boolean`

---

## 3. New Reject Request Contract

**Endpoint:** `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`

### Full request body shape:

```json
{
  "incorrectQuantity": false,
  "otherReason": false,
  "otherReasonNotes": null,
  "undeclaredFaletFound": true,
  "undeclaredFaletObservedQuantity": 12,
  "undeclaredFaletNotes": "Found 12 cartons near the conveyor",
  "itemObservations": null
}
```

### Field reference:

| Field | Type | When required |
|---|---|---|
| `incorrectQuantity` | boolean | At least ONE of the three reason flags must be true |
| `otherReason` | boolean | At least ONE of the three reason flags must be true |
| `otherReasonNotes` | String (max 1000) | Required when `otherReason = true` |
| `undeclaredFaletFound` | boolean | At least ONE of the three reason flags must be true |
| `undeclaredFaletObservedQuantity` | Integer (> 0) | Required when `undeclaredFaletFound = true` |
| `undeclaredFaletNotes` | String (max 1000) | Optional (always) |
| `itemObservations` | List | Required when `incorrectQuantity = true` (one per existing snapshot) |

### Rejection reason combinations:

| Scenario | Fields to set |
|---|---|
| Declared FALET quantity mismatch | `incorrectQuantity = true` + `itemObservations` array |
| Other reason only | `otherReason = true` + `otherReasonNotes` |
| Undeclared FALET found only | `undeclaredFaletFound = true` + `undeclaredFaletObservedQuantity` |
| Undeclared FALET + other reason | Both flags true, both data fields filled |
| All three combined | All three flags true, all data provided |

---

## 4. Product Rule

**Critical:** The frontend must **NOT** ask the incoming operator to choose a product for this scenario.

- The backend infers the product from `ProductionLine.currentProductType`.
- The response will include the inferred product in the snapshot item (via `faletItems` in `LineHandoverResponse`).
- If the line has no current active product, the backend returns error code `NO_ACTIVE_PRODUCT_FOR_UNDECLARED_FALET`.

The frontend should:
- Show a simple quantity input and optional notes field for undeclared FALET
- Never show a product picker for this rejection reason
- The product will be visible in the response after rejection succeeds

---

## 5. Validation Rules

### Frontend should validate locally:

| Field | Rule |
|---|---|
| At least one reason flag | `incorrectQuantity \|\| otherReason \|\| undeclaredFaletFound` must be true |
| `undeclaredFaletObservedQuantity` | Required and > 0 when `undeclaredFaletFound = true` |
| `undeclaredFaletNotes` | Optional, max 1000 chars |
| `otherReasonNotes` | Required when `otherReason = true`, max 1000 chars |
| `itemObservations` | Required when `incorrectQuantity = true`; one entry per FALET snapshot |

### Backend enforces all of the above and additionally:
- Current active product must exist on the line (for undeclared FALET)
- Handover must be in `PENDING` status
- Incoming operator must have active authorization on the line

---

## 6. Error Cases

### New error:
| Error Code | HTTP Status | When |
|---|---|---|
| `NO_ACTIVE_PRODUCT_FOR_UNDECLARED_FALET` | 400 | `undeclaredFaletFound = true` but no product is currently selected on the line |

### Existing errors (unchanged):
| Error Code | HTTP Status | When |
|---|---|---|
| `REJECTION_REASON_REQUIRED` | 400 | No reason flag is true |
| `VALIDATION_ERROR` | 400 | `otherReason = true` but `otherReasonNotes` is blank; or `undeclaredFaletFound = true` but quantity is null/0 |
| `OBSERVED_QUANTITY_REQUIRED` | 400 | `incorrectQuantity = true` but `itemObservations` missing or count mismatch |
| `LINE_HANDOVER_NOT_FOUND` | 404 | Handover ID not found |
| `LINE_HANDOVER_ALREADY_RESOLVED` | 409 | Handover not in PENDING status |
| `LINE_NOT_AUTHORIZED` | 403 | No active authorization on line |

---

## 7. Review/Reject UI Expectations

### When the handover has NO FALET snapshots (the new scenario):

The reject dialog should show:

1. **Undeclared FALET Found** checkbox/toggle
   - When enabled, show:
     - Quantity input (required, integer > 0)
     - Notes text field (optional)
   - Do NOT show a product picker

2. **Other Reason** checkbox/toggle (existing)
   - When enabled, show notes text field (required)

3. **Incorrect Quantity** checkbox/toggle (existing)
   - Only relevant when FALET snapshots exist in the handover
   - When the handover has zero FALET snapshots, this option can be hidden or disabled

### When the handover HAS FALET snapshots:

All three options should be available. The operator might report:
- Incorrect quantities on declared items (`incorrectQuantity`)
- AND/OR undeclared FALET of a different nature (`undeclaredFaletFound`)
- AND/OR other reasons (`otherReason`)

---

## 8. Admin/Dispute Visibility

When a handover is rejected with `undeclaredFaletFound = true`:

- The **handover detail page** shows a new badge: "فالت غير مصرح عنه" (Undeclared FALET Found)
- The **FALET items table** on the handover detail shows a row with:
  - Product: the line's current active product name
  - Declared Qty: **0** (outgoing didn't declare it)
  - Observed Qty: the quantity reported by the incoming operator
- The **dispute detail page** shows:
  - The same "فالت غير مصرح عنه" badge in rejection reasons
  - A dispute item row for the undeclared FALET with the inferred product, disputed quantity, and remaining quantity
  - Admin can DISPOSE / PALLETIZE / RELEASE / HOLD this item just like any other dispute item

The dispute's `rejectionNotes` summary will include:
`"فالت غير مصرح عنه (12 عبوة)"` — with the observed quantity.

---

## 9. Final Frontend Recommendation

### Implementation steps:

1. **Update the reject dialog** to add a third rejection reason toggle: "Undeclared FALET Found" / "فالت غير مصرح عنه"
2. **Conditionally show** quantity + notes fields when the toggle is on
3. **Never show a product picker** — the backend handles product inference
4. **Map the form fields** to the updated `LineHandoverRejectRequest` JSON shape
5. **Handle the new error** `NO_ACTIVE_PRODUCT_FOR_UNDECLARED_FALET` — show a user-friendly message like "لا يوجد منتج نشط على الخط" (No active product on the line)
6. **Read `rejectionUndeclaredFalet`** from `LineHandoverResponse` to display the correct rejection badge/label after rejection
7. **When handover has no FALET snapshots**: consider hiding the "Incorrect Quantity" option (it requires snapshots to reference) and emphasizing "Undeclared FALET Found" and "Other Reason" as the available options

### Minimal example — undeclared FALET only:

```json
{
  "undeclaredFaletFound": true,
  "undeclaredFaletObservedQuantity": 15,
  "undeclaredFaletNotes": "وجدت عبوات بجانب الخط"
}
```

### Minimal example — undeclared FALET + other reason:

```json
{
  "undeclaredFaletFound": true,
  "undeclaredFaletObservedQuantity": 15,
  "otherReason": true,
  "otherReasonNotes": "الخط غير نظيف"
}
```

All boolean fields default to `false` — only send the flags that are true.
