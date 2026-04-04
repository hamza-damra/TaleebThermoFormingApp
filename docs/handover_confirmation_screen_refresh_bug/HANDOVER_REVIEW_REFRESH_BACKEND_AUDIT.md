# Handover Review Refresh — Backend Audit

## Conclusion

**The backend is NOT the cause of the disappearing handover summary after refresh.**

All handover data (loose balances, incomplete pallet info) is fully persisted in the database and consistently available through all relevant endpoints on every request.

---

## What Was Inspected

### Endpoints Checked

| Endpoint                                                        | Method | Returns                                                     | Used For                         |
| --------------------------------------------------------------- | ------ | ----------------------------------------------------------- | -------------------------------- |
| `/api/v1/palletizing-line/lines/{lineId}/handover`              | POST   | `LineHandoverResponse` (full)                               | Creating handover                |
| `/api/v1/palletizing-line/lines/{lineId}/handover/pending`      | GET    | `LineHandoverResponse` (full)                               | Fetching pending handover detail |
| `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm` | POST   | `LineHandoverResponse` (full)                               | Confirming handover              |
| `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`  | POST   | `LineHandoverResponse` (full)                               | Rejecting handover               |
| `/api/v1/palletizing-line/lines/{lineId}/state`                 | GET    | `LineStateResponse` (with `LineHandoverSummary`)            | Line state/bootstrap             |
| `/api/v1/palletizing-line/bootstrap`                            | GET    | `BootstrapResponse` (contains `LineStateResponse` per line) | App initialization               |

### DTOs Checked

1. **`LineHandoverResponse`** — Full detail DTO with:
   - `incompletePallet` (`IncompletePalletInfo`: productTypeId, productTypeName, quantity)
   - `looseBalances` (List of `LooseBalanceItem`: productTypeId, productTypeName, loosePackageCount)
   - `handoverType` (NONE / INCOMPLETE_PALLET_ONLY / LOOSE_BALANCES_ONLY / BOTH)
   - `looseBalanceCount` (int)
   - Status, operator info, timestamps, notes

2. **`LineStateResponse.LineHandoverSummary`** — Condensed summary with:
   - `handoverId`, `outgoingOperatorName`, `status`
   - `looseBalanceCount` (int count only — no item details)
   - `hasIncompletePallet` (boolean), `incompletePalletProductTypeName` (no quantity, no productTypeId)
   - `handoverType`, `createdAtDisplay`, `notes`

### Services Checked

- **`LineHandoverService`** — `createHandover()`, `confirmHandover()`, `rejectHandover()`, `getPendingHandover()`, `toResponse()`
- **`LineStateService`** — `getLineState()`
- **`PalletizingBootstrapService`** — `getBootstrap()`

### Entity/Repository Checked

- **`LineHandover`** entity — all fields persisted to `line_handovers` table
- **`LineHandoverLooseBalance`** entity — child table with `CascadeType.ALL`
- **`LineHandoverRepository`** — `findByProductionLineIdAndStatus()` with `@EntityGraph` eagerly loading `looseBalances`, `outgoingOperator`, `incomingOperator`, `incompletePalletProductType`, `productionLine`

---

## Verification Results

### 1. Is summary data fully persisted after handover creation?

**YES.** The `createHandover()` method:

- Saves incomplete pallet fields directly on the `LineHandover` entity (`incompletePalletProductType`, `incompletePalletQuantity`, `incompletePalletProductTypeNameSnapshot`)
- Saves `LineHandoverLooseBalance` child entities via `CascadeType.ALL` through `handover.addLooseBalance()`
- Calls `handoverRepository.saveAndFlush()` — data is committed to DB

### 2. On refresh, does the backend still return complete summary data?

**YES.** The `GET /lines/{lineId}/handover/pending` endpoint:

- Calls `lineHandoverRepository.findByProductionLineIdAndStatus(lineId, PENDING)`
- This query uses `@EntityGraph` to eagerly load all relationships
- Maps through `toResponse()` which produces the full `LineHandoverResponse` with all loose balance items and incomplete pallet info
- This is identical in shape and content to what `createHandover()` returns

### 3. Are there multiple endpoints returning different shapes?

**YES — but by design.** Two different DTO shapes exist:

- `LineHandoverResponse` (full detail) — from `GET /handover/pending`, `POST /handover`, `POST /handover/{id}/confirm`, `POST /handover/{id}/reject`
- `LineStateResponse.LineHandoverSummary` (condensed) — from `GET /state`, `GET /bootstrap`

The summary intentionally omits detailed loose balance items and incomplete pallet quantity. **This is expected** — the summary is for line state overview, not for the review screen.

### 4. Is any data only available in the initial response but missing from refresh?

**NO.** The `GET /handover/pending` endpoint reads from the same persisted DB data and produces the exact same `LineHandoverResponse` structure as the initial `POST /handover` response.

### 5. Are null/empty collections returned incorrectly?

**NO.** The `toResponse()` method always:

- Returns `looseBalances` as an empty list (never null) when no loose balances exist
- Returns `incompletePallet` as null when no incomplete pallet exists (consistently omitted by `@JsonInclude(NON_NULL)`)
- This behavior is consistent between creation and re-fetch

### 6. Is any data dependent on in-memory state?

**NO.** All data comes from the database. No caches, no in-memory-only state.

---

## Likely Root Cause (Frontend)

The most probable frontend issue is one of:

1. **The frontend only uses `GET /state` or `GET /bootstrap` after refresh** — these return `LineHandoverSummary` (condensed), not `LineHandoverResponse` (full detail). The review screen needs the full detail from `GET /handover/pending`.

2. **The frontend stores the full `LineHandoverResponse` from the POST creation response in local state**, displays it correctly on the review screen, but after refresh loses that state and only restores from bootstrap/state which has the lighter summary — never re-fetching the full detail.

3. **The frontend review screen reads from a state key that is populated by the POST response but not re-populated after bootstrap/state refresh** — i.e., the review screen component expects state shaped like `LineHandoverResponse` but after refresh only gets `LineHandoverSummary`.

---

## Backend Changes Made

**None.** The backend is correct and requires no changes.

---

## Scenarios Verified

| #   | Scenario                                 | Backend Result                                                                                            |
| --- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1   | Handover with loose balance only         | Full data persisted and returned on both POST and GET /pending                                            |
| 2   | Handover with incomplete pallet only     | Full data persisted and returned on both POST and GET /pending                                            |
| 3   | Handover with both loose + incomplete    | Full data persisted and returned on both POST and GET /pending                                            |
| 4   | Review screen immediately after creation | POST returns full `LineHandoverResponse`                                                                  |
| 5   | Review screen after page refresh         | GET /pending returns identical `LineHandoverResponse`; GET /state returns condensed `LineHandoverSummary` |
| 6   | Bootstrap after refresh                  | Contains `LineHandoverSummary` per line (condensed — by design)                                           |
| 7   | Data persistence check                   | All data in DB tables, no in-memory dependency                                                            |
