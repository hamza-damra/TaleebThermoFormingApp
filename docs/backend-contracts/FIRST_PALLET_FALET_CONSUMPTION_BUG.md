# FIRST PALLET FALET CONSUMPTION BUG

**Severity:** Critical — operator workflow is stuck in a loop.
**Owner:** Palletizing-Line backend service.
**Filed by:** Palletizing Flutter app (`hamza-damra/TaleebThermoFormingApp`).
**Date filed:** 2026-05-27.

**Status:** RESOLVED on TESTING (`https://138.68.66.215/api/v1`). Backend commit
`c6c5311` ("fix(palletizing): consume FALET atomically with first-pallet
creation") implements Option A. Flutter follow-up landed alongside this
update — see §9 for what changed.

---

## 1. Summary

The first-pallet FALET-consumption flow is **not atomic** with pallet creation
because the create-pallet API contract has no field referencing the FALET to be
consumed. As a result the FALET remains open in the backend after the first
pallet is created, and the same first-pallet suggestion dialog reappears on
every subsequent "إنشاء طبلية جديدة" tap. The operator must manually dispose
the FALET via a separate flow — which is the **wrong** business behaviour
(FALET that was already counted into a pallet must not require a second manual
disposal step).

This is a **backend contract gap**, not a frontend bug. The Flutter app already
follows the documented workflow: it calls `GET /first-pallet-context`, shows
the suggestion dialog, and on confirm posts to the create-pallet endpoint with
the full pallet target quantity. There is no extra request the frontend could
send today that would deduct the FALET.

---

## 2. Reproduction

1. A line has an open matching FALET, quantity = **5** (created by a previous
   shift / product switch).
2. The current production-plan item for the line has
   `packagesPerPallet = 32`.
3. Operator taps **"إنشاء طبلية جديدة"**.
4. Flutter calls `GET /palletizing-line/lines/{lineId}/first-pallet-context`
   → backend returns:

   ```json
   {
     "success": true,
     "data": {
       "lineId": 1,
       "currentPlanItemId": 42,
       "currentPlanItemProductTypeId": 17,
       "currentPlanItemProductName": "TBS-13 C1500 Beige",
       "currentPlanItemPackagesPerPallet": 32,
       "hasOpenFalet": true,
       "matchingProductFaletQuantity": 5,
       "nonMatchingFaletQuantity": 0,
       "canSuggestFirstPalletDialog": true,
       "suggestedFaletQuantityForFirstPallet": 5,
       "requiresOperatorFaletDecision": false,
       "messageAr": null,
       "blockReason": null
     }
   }
   ```

5. Flutter shows `FirstPalletSuggestionDialog` with:
   - target = 32, FALET = 5, additional fresh = 27, total = 32.
6. Operator taps **"تأكيد وإنشاء الطبلية"**.
7. Flutter posts:

   ```
   POST /palletizing-line/lines/{lineId}/pallets
   Headers: X-Device-Key: <redacted>
   Body:
   {
     "productTypeId": 17,
     "quantity": 32,
     "confirmOverproduction": false
   }
   ```

8. Backend responds **HTTP 201** with a normal `PalletCreateResponse`.
9. Frontend refreshes `BootstrapLineState` and re-fetches
   `first-pallet-context`.
10. Backend **still** returns `canSuggestFirstPalletDialog: true`,
    `matchingProductFaletQuantity: 5`, `hasOpenFalet: true`. The FALET was
    **not** deducted as part of step 7.
11. On the next "إنشاء طبلية جديدة" tap, the same dialog appears again with
    the same numbers, forever.

---

## 3. Current endpoint and contract

### Request: create pallet

| Field | Type | Source |
|---|---|---|
| `productTypeId` | `int` | from `first-pallet-context.currentPlanItemProductTypeId` |
| `quantity` | `int` | the pallet target (e.g. `32`) — **not** the FALET quantity |
| `confirmOverproduction` | `bool` | `false` on first attempt; `true` only after V81 confirmation dialog |

**There is no field on the request that references the FALET row or the
quantity to deduct from it.**

### Response: create pallet

The response body (`PalletCreateResponseModel`) carries:

```
palletId, scannedValue, qrCodeData, operator, productType, productionLine,
quantity, currentDestination, createdAt, createdAtDisplay,
sessionProductSequence
```

**No `consumedFaletId`, no `consumedFaletQuantity`, no `faletBreakdown`.**

---

## 4. Expected backend behaviour

When the create-pallet request originates from a first-pallet FALET flow,
the backend **must** atomically:

1. Lock the matching open FALET row(s) for the product on this line
   (`FOR UPDATE` or equivalent).
2. Validate that the suggested FALET quantity is still available (no other
   transaction has reduced it).
3. Create the pallet row and pallet-items row(s).
4. Write a FALET-consumption audit/breakdown row linking the pallet to the
   FALET id(s) and the consumed quantity per row.
5. Decrement the FALET row's remaining quantity. If the FALET row is fully
   consumed, transition its status to `RESOLVED` (or whatever the existing
   terminal status is) and stamp the resolution audit.
6. Commit. Only after commit, publish the SSE line-state event so the
   palletizer app refreshes from a consistent snapshot.

### Required invariant

> **If first-pallet creation consumes the suggested FALET quantity, that
> FALET quantity MUST be deducted/resolved atomically in the same database
> transaction as pallet creation.**

If the backend cannot deduct it (e.g. FALET row no longer exists, was
consumed by a concurrent request, or quantity is insufficient), the entire
pallet creation **must** fail with a specific error code so the frontend
can re-fetch `first-pallet-context` and show the updated state. Pallet
creation must not silently fall back to "create the pallet without touching
FALET".

---

## 5. Required contract changes

Two options — backend team picks one. The frontend will adapt either way.

### Option A — extend the existing endpoint (preferred, smallest blast radius)

Add an optional field to the create-pallet request body:

```jsonc
POST /palletizing-line/lines/{lineId}/pallets
{
  "productTypeId": 17,
  "quantity": 32,
  "confirmOverproduction": false,

  // NEW — present only when the create call originates from the first-pallet
  // FALET flow. Backend validates and consumes the indicated FALET quantity
  // atomically with pallet creation. Server-side rounding/saturation is OK
  // only if it is documented and the response surfaces the actual consumed
  // amount.
  "firstPalletFaletConsumption": {
    "expectedFaletQuantity": 5,
    // Optional — if backend wants to bind to a specific FALET row instead of
    // "all matching open FALET for this product on this line":
    "faletId": 9876
  }
}
```

And extend the response:

```jsonc
{
  "success": true,
  "data": {
    // … existing fields …
    "faletConsumption": {
      "consumedFaletId": 9876,
      "consumedQuantity": 5,
      "faletStatusAfter": "RESOLVED"        // or "PARTIAL"
    }
  }
}
```

If `firstPalletFaletConsumption` is absent the endpoint must behave exactly
as today (zero behaviour change for non-first-pallet flows).

### Option B — dedicated endpoint

```
POST /palletizing-line/lines/{lineId}/first-pallet-with-falet
Body: { productTypeId, quantity, confirmOverproduction,
        expectedFaletQuantity, faletId? }
Response: same as create-pallet plus the `faletConsumption` block.
```

The dedicated endpoint may be cleaner for auditing but doubles the surface
area. Option A is preferred.

---

## 6. Required `first-pallet-context` behaviour after success

After a successful first-pallet creation that consumed the matching FALET:

- `GET /first-pallet-context` for the same line MUST return:
  - `hasOpenFalet`: `false` if no other open FALET remains, else `true`
    (for non-matching FALET).
  - `matchingProductFaletQuantity`: `0` for the just-consumed product.
  - `canSuggestFirstPalletDialog`: `false`.
  - `suggestedFaletQuantityForFirstPallet`: `null`.
- `GET /lines/{lineId}/state` MUST reflect the deduction (any cached
  FALET-summary fields in the bootstrap/line-state payload must be
  re-derived from the same transaction).

Stale snapshots / cached counters are the root cause of the current loop —
any read endpoint that surfaces FALET totals must read after the consumption
transaction commits.

---

## 7. Concurrency requirements

1. **Pessimistic lock** on the matching FALET row(s) for the duration of
   the create-pallet transaction. Postgres example: `SELECT … FROM falet
   WHERE line_id = ? AND product_type_id = ? AND status = 'OPEN'
   ORDER BY created_at FOR UPDATE`.
2. **Idempotency**: if the operator double-taps confirm and two requests
   race, only one must succeed in consuming the FALET. The second must
   either:
   - fail with `FALET_ALREADY_CONSUMED` (preferred — fast, observable), or
   - succeed but consume `0` and surface that in the response.
   Either way the second request must not double-create the pallet against
   a stale FALET total.
3. **Outbox / event publish** must happen post-commit so the SSE line-state
   event reflects the consumed FALET. Pre-commit publish (read-your-own-
   writes via cache) re-introduces the loop.
4. **No background reconciliation** for this — the consumption must be
   inline. Async resolution leaks the same race window.

---

## 8. Tests the backend must add

Mark these as P0; the workflow does not ship without them.

1. **Partial FALET consumption** — FALET = 5, target = 32, confirm →
   pallet created with `quantity=32`, FALET row deducted by 5, status
   transitions to `RESOLVED`. `first-pallet-context` then returns
   `canSuggestDialog=false`.
2. **Full FALET consumption** — FALET = 32, target = 32, confirm →
   pallet created with `quantity=32`, FALET fully consumed → `RESOLVED`.
3. **FALET larger than target** — FALET = 50, target = 32 → either reject
   (`FALET_QUANTITY_MISMATCH`) or consume exactly 32 and keep 18 open.
   Document which; frontend currently shows 32 in the dialog so consuming
   exactly 32 is the natural behaviour.
4. **Multiple matching FALET rows** — two open FALET rows for the same
   product totalling 5. Confirm with target = 32. Both rows are consumed in
   stable order (e.g. by `created_at ASC`) within the same transaction.
5. **Concurrent first-pallet creation** — two simultaneous confirms from the
   same line. Only one transaction wins; the loser receives
   `FALET_ALREADY_CONSUMED` or equivalent.
6. **Stale snapshot read** — after a successful consume, the next read of
   `first-pallet-context` and `lines/{id}/state` MUST NOT return the
   pre-consume FALET totals. Use a fresh transaction in the test to bypass
   any client-side cache.
7. **Backwards compatibility** — call `POST /pallets` WITHOUT the new
   `firstPalletFaletConsumption` block. Behaviour must be identical to
   today (no FALET touched).
8. **Failure case rollback** — simulate a print-attempt failure or any
   post-create rollback path. The FALET deduction must roll back with the
   pallet; status must return to `OPEN`.

---

## 9. Frontend integration (landed)

The Flutter follow-up is now in:

- `lib/data/repositories/palletizing_repository_impl.dart` —
  `createLinePallet` attaches `firstPalletFaletConsumption.expectedFaletQuantity`
  (and an optional `faletId`) when the call originates from the first-pallet
  FALET path. Block is omitted on every other create-pallet call.
- `lib/data/models/pallet_create_response_model.dart` — tolerant parser for
  the new `faletConsumption` block (missing / null / partial payloads all
  degrade gracefully to "no consumption").
- `lib/domain/entities/falet_consumption.dart` — new value object
  (`consumedFaletId`, `consumedQuantity`, `faletStatusAfter`).
- `lib/presentation/providers/palletizing_provider.dart` — `createPallet`
  forwards the new optional parameters.
- `lib/presentation/widgets/production_line_section.dart` — first-pallet
  confirm passes `ctx.suggestedFaletQuantityForFirstPallet`; on success the
  app emits an Arabic snack `"تم احتساب N من الفالت السابق"`. On
  `FALET_ALREADY_CONSUMED` it emits
  `"تم استخدام هذا الفالت مسبقاً، تم تحديث حالة الخط"` and lets the existing
  provider line-state refresh re-route the UI. The previous diagnostic
  post-create re-fetch (`[FirstPallet POST-CREATE STATE]`) was removed; the
  `[FirstPallet SUGGEST]` and `[FirstPallet CONFIRM]` logs are kept for
  on-device debugging.
- `lib/core/exceptions/api_exception.dart` — `FALET_ALREADY_CONSUMED` and
  `FALET_QUANTITY_MISMATCH` Arabic display strings.

No local FALET hiding, no fake state, no behavioural diverge from the
backend snapshot — the backend remains the source of truth.

---

## 10. Reference artefacts

- Frontend create-pallet path:
  `lib/data/repositories/palletizing_repository_impl.dart:createLinePallet`
  (current request body has no FALET field).
- Frontend first-pallet flow:
  `lib/presentation/widgets/production_line_section.dart:_showCreateDialog`
  (step 3 — the new diagnostic logs surface this bug to `adb logcat`).
- Frontend confirmation dialog:
  `lib/presentation/widgets/first_pallet_suggestion_dialog.dart`.
- Frontend context entity:
  `lib/domain/entities/first_pallet_context.dart`.
