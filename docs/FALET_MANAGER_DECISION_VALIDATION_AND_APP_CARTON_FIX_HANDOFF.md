# FALET Manager Decision Validation & App Carton Fix — Frontend Handoff

## Summary

Two backend changes that affect the FALET dispute manager-decision flow:

1. **Manager decisions can now be blocked** if the receiver hasn't produced enough same-product cartons to cover the attribution shift.
2. **Session table carton counts are now attribution-aware** — the same existing `completedPackageCount` field now reflects post-decision corrected values.

**No Flutter UI changes required.** Same fields, corrected semantics.

---

## Change 1: Decision Blocking (HTTP 409)

### When does it happen?

When a manager tries to make a decision (e.g., `SENDER_RIGHT`) that would shift attribution from receiver → sender, but the receiver's session does not have enough **same-product fresh production** to cover the shift.

### API behavior

- **Endpoint**: `POST /web/admin/falet-disputes/{id}/decide`
- **Error code**: `INSUFFICIENT_RECEIVER_PRODUCTION`
- **HTTP status**: `409 Conflict`
- **Message** (Arabic): `لا يمكن اتخاذ القرار: إنتاج المستلم من نفس المنتج غير كافٍ. المطلوب: X عبوة، المتوفر: Y عبوة.`

### Web admin handling

The existing Thymeleaf controller already catches `BusinessException` and shows `errorMessage` via flash attributes. The Arabic message will appear in the admin UI automatically.

### What the app should know

- The app does **not** call the decision endpoint directly (only admin web does).
- **No app-side changes needed** for decision blocking.

---

## Change 2: Attribution-Aware Carton Counts

### What changed?

The `completedPackageCount` field in the session table now reflects **attribution-corrected** values instead of raw pallet quantities.

### Affected endpoints

| Endpoint | Field | Before | After |
|---|---|---|---|
| `GET /api/v1/palletizing-line/lines/{lineId}/session-table` | `completedPackageCount` | Sum of `Pallete.quantity` by `lineAuthorization` | Sum of attributed quantities from `PalleteCreationBreakdown` by `sourceAuthorization` |
| `GET /api/v1/palletizing-line/lines/{lineId}/state` | `sessionTable[].completedPackageCount` | Same as above | Same as above |

### Example scenario

1. Sender produced 18 cartons into a pallet, handed over 2 extra cartons as FALET
2. Receiver says 0 received
3. Manager decides `SENDER_RIGHT` (shift = 2 from receiver → sender)

**Before fix:**
- Receiver's session table: `completedPackageCount = 50` (full pallet qty)
- Sender's session table: `completedPackageCount = 100` (own pallets only)

**After fix:**
- Receiver's session table: `completedPackageCount = 48` (50 − 2 shifted to sender)
- Sender's session table: `completedPackageCount = 102` (100 + 2 from DISPUTE_RESOLUTION)

### What does NOT change

- `completedPalletCount` — still physical pallet count (attribution doesn't move pallets)
- `loosePackageCount` — still from `SessionProductBalance` (unchanged)
- `quantity` in `SessionPalletDetail` (per-pallet detail view) — still physical pallet quantity
- Warehouse analytics — unchanged (already uses breakdown-level attribution)

### Flutter app impact

- **No UI changes needed** — same field names, same JSON shape
- The numbers shown in the session table will automatically reflect corrected values
- Both active receiver sessions and historical sender sessions (if queried) return corrected counts

---

## Removed Statuses

The following `attributionExecutionStatus` values are no longer reachable:

| Status | Before | After |
|---|---|---|
| `PARTIAL` | Set when insufficient production found during adjustment | **Blocked upfront** — decision never executes |
| `MANUAL_RECONCILIATION_REQUIRED` | Set when no production found at all | **Blocked upfront** — decision never executes |

Only these statuses remain in use:
- `COMPLETE` — adjustment fully applied
- `NOT_APPLICABLE` — no attribution shift was needed
