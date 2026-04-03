# Frontend AI Agent — Handover Dialog Update Prompt

You are the Frontend AI Agent working on the Taleeb palletizing / تكوين المشاتيح app.

Your task is to update the handover dialog (تسليم مناوبة) to align with the corrected backend contract.

---

## Step 1 — Read the Backend Changes

Before making any changes, read the following file carefully:

**`docs/ai-handoffs/palletizing/FRONTEND_HANDOVER_REQUIRED_CHANGES.md`**

This file contains:
- The exact updated backend request/response contract
- Which fields were removed and which were added
- How confirm/reject behavior changed
- A full checklist of required frontend changes

---

## Step 2 — Implement the Following Changes

### 2a. Remove Scanned Value from Incomplete Pallet Form

The `incompletePalletScannedValue` field (12-digit code) has been **removed** from the backend contract.

- Remove any scanned value / barcode / QR code input field from the incomplete pallet section of the handover dialog
- The incomplete pallet at handover time has not been finalized — it has no pallet number, no QR label
- Only `incompletePalletProductTypeId` (product type picker) and `incompletePalletQuantity` (count) should be shown

### 2b. Add Explicit Product Type + Count for Loose Balances

The old `includeLooseBalances: Boolean` flag has been **removed**. It is replaced by an explicit list of loose balance entries.

When the operator indicates there is فالت (loose balance):
- Show a form where the operator can add **one or more** loose balance rows
- Each row must have:
  - **Product type picker** — select from available product types
  - **Loose package/carton count** — integer input, minimum 1
- The operator can add multiple rows (different product types)
- **Duplicate product types are not allowed** — validate this on the frontend before submission
- Maximum 50 entries

The request format is:
```json
{
  "looseBalances": [
    { "productTypeId": 5, "loosePackageCount": 7 },
    { "productTypeId": 6, "loosePackageCount": 3 }
  ]
}
```

### 2c. Update the Handover Dialog Flow

The dialog flow should be:

1. Operator presses "تسليم مناوبة"
2. Initial question screen:
   - هل يوجد مشاتيح ناقصة؟ (Yes/No)
   - هل يوجد فالت؟ (Yes/No)
3. Based on answers, show the appropriate form sections:
   - **Incomplete pallet section**: product type picker + quantity input
   - **Loose balance section**: dynamic list of product type + count rows
   - **Both sections** if both answers are Yes
   - **Neither** if both are No (clean handover with optional notes)
4. Submit via `POST /api/v1/palletizing/lines/{lineId}/handover`

### 2d. Confirm/Reject Behavior

After handover creation, when the incoming operator authorizes and sees the pending handover:

**On Confirm** (`POST /api/v1/palletizing/lines/{lineId}/handover/{id}/confirm`):
- All handed-over items (incomplete pallet + loose balances) are transferred to the incoming operator's session
- The session table should reflect the new items immediately
- The line returns to normal `AUTHORIZED` mode

**On Reject** (`POST /api/v1/palletizing/lines/{lineId}/handover/{id}/reject`):
- Items are NOT transferred to the incoming operator
- The handover is marked for admin dispute resolution
- The line returns to normal `AUTHORIZED` mode for the incoming operator

### 2e. Session Table Verification

After a confirmed handover, the incoming operator's session table (`sessionTable` in the line state response) must show the transferred items:
- Incomplete pallet quantity appears as `loosePackageCount` for that product type
- Loose balance counts are added to existing balances or create new rows

Ensure the UI correctly reflects this data.

---

## Step 3 — Use the Correct Backend Contract

### Create Handover Request
```json
{
  "incompletePalletProductTypeId": 5,
  "incompletePalletQuantity": 25,
  "looseBalances": [
    { "productTypeId": 6, "loosePackageCount": 3 }
  ],
  "notes": "Optional notes"
}
```

**Do NOT send:**
- `incompletePalletScannedValue` — field removed
- `includeLooseBalances` — field removed

### Response Fields to Use
- `handoverType`: `"NONE"` | `"INCOMPLETE_PALLET_ONLY"` | `"LOOSE_BALANCES_ONLY"` | `"BOTH"`
- `incompletePallet.productTypeId`, `incompletePallet.productTypeName`, `incompletePallet.quantity`
- `looseBalances[].productTypeId`, `looseBalances[].productTypeName`, `looseBalances[].loosePackageCount`
- `looseBalanceCount`: total number of loose balance entries
- `status`: `"PENDING"` | `"CONFIRMED"` | `"REJECTED"` | `"RESOLVED"`
- `lineUiMode` from line state: determines which UI to render

---

## Step 4 — Create Summary

After completing the implementation, create a summary markdown file at:

**`docs/ai-handoffs/palletizing/FRONTEND_HANDOVER_IMPLEMENTATION_SUMMARY.md`**

This file should document:
- What was changed in the frontend
- Which components/screens were modified
- How the handover dialog works now
- How loose balance entry works now
- That scanned value field was removed
- How confirm/reject behavior is handled
- Any remaining follow-up items

---

## Important Rules

- Do NOT redesign the dialog from scratch — the current UX is mostly correct
- Focus on the specific changes listed above
- Keep the product type picker consistent with existing pickers in the app
- Ensure Arabic labels and RTL layout are preserved
- Test the flow: create handover → incoming authorize → confirm/reject
