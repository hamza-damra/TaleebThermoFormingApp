# Frontend Handoff: Handover Review Refresh Bug

## Summary

**The backend has been audited and confirmed correct.** The bug is in the frontend's refresh/state restoration flow.

The backend fully persists all handover summary data (loose balances, incomplete pallet info) and returns it consistently through a dedicated endpoint. The issue is that after a page refresh, the frontend is likely not calling the right endpoint to restore the full handover detail for the review screen.

---

## Backend Endpoints Available

### For the Review Screen (Full Detail)

**`GET /api/v1/palletizing-line/lines/{lineId}/handover/pending`**

Returns: `ApiResponse<LineHandoverResponse>` (full detail — **this is what the review screen needs**)

The `data` field contains:

```json
{
  "id": 500,
  "lineId": 1,
  "lineName": "Line 1",
  "status": "PENDING",
  "statusDisplayNameAr": "...",
  "outgoingOperatorName": "Ahmad",
  "outgoingOperatorId": 10,
  "incompletePallet": {
    // null when no incomplete pallet
    "productTypeId": 5,
    "productTypeName": "Red 20kg",
    "quantity": 25
  },
  "looseBalances": [
    // empty list when no loose balances
    {
      "productTypeId": 6,
      "productTypeName": "Blue 10kg",
      "loosePackageCount": 4
    }
  ],
  "looseBalanceCount": 1,
  "handoverType": "BOTH", // NONE | INCOMPLETE_PALLET_ONLY | LOOSE_BALANCES_ONLY | BOTH
  "notes": "End of shift",
  "createdAt": "2025-06-15T10:00:00Z",
  "createdAtDisplay": "..."
}
```

**Important:** Fields with null values are omitted from the JSON response (`@JsonInclude(NON_NULL)`). For example, if there is no incomplete pallet, the `incompletePallet` field will be completely absent from the JSON, not `null`.

### For Line State / Bootstrap (Condensed Summary)

**`GET /api/v1/palletizing-line/lines/{lineId}/state`**

Returns `LineStateResponse` which includes a condensed `pendingHandover` summary:

```json
{
  "lineId": 1,
  "lineName": "Line 1",
  "lineUiMode": "PENDING_HANDOVER_REVIEW", // or "PENDING_HANDOVER_NEEDS_INCOMING"
  "pendingHandover": {
    "handoverId": 500,
    "outgoingOperatorName": "Ahmad",
    "status": "PENDING",
    "looseBalanceCount": 1, // count only — NO item details
    "hasIncompletePallet": true, // boolean only — NO quantity
    "incompletePalletProductTypeName": "Red 20kg",
    "handoverType": "BOTH",
    "createdAtDisplay": "...",
    "notes": "End of shift"
  }
}
```

**This summary does NOT contain the full loose balance item list or the incomplete pallet quantity.** It is designed for the line overview card, not the detailed review screen.

---

## The Bug — What the Frontend Must Fix

### Problem

After page refresh, the frontend review screen shows an empty summary because:

1. The frontend probably only calls `GET /state` (or uses bootstrap) after refresh
2. `GET /state` returns `LineHandoverSummary` — a condensed object that does NOT include detailed loose balance items or incomplete pallet quantity
3. The review screen was originally populated from the POST response (`LineHandoverResponse` — full detail) which is lost after refresh
4. After refresh, the review screen tries to render from the condensed summary and finds the detailed fields missing

### Fix

When the frontend detects it needs to show the handover review screen (i.e., `lineUiMode` is `PENDING_HANDOVER_REVIEW` or `PENDING_HANDOVER_NEEDS_INCOMING` and a `pendingHandover` exists), it must:

1. Read `pendingHandover.handoverId` from the state/bootstrap response
2. Call `GET /api/v1/palletizing-line/lines/{lineId}/handover/pending` to get the full `LineHandoverResponse`
3. Use that full response to populate the review screen

### Pseudocode

```dart
// After bootstrap/state refresh:
if (lineState.lineUiMode == 'PENDING_HANDOVER_REVIEW' ||
    lineState.lineUiMode == 'PENDING_HANDOVER_NEEDS_INCOMING') {

  if (lineState.pendingHandover != null) {
    // MUST fetch full detail for the review screen
    final fullHandover = await api.get(
      '/api/v1/palletizing-line/lines/${lineId}/handover/pending'
    );
    // Use fullHandover.data to populate review screen
    // fullHandover.data.looseBalances → full item list
    // fullHandover.data.incompletePallet → full detail with quantity
  }
}
```

---

## What to Check in the Frontend Code

1. **State restoration after refresh**: When the app reloads, does it call `GET /handover/pending` to restore the full handover detail, or does it only rely on bootstrap/state?

2. **Review screen data source**: Does the review screen component read from a state property that is populated from the POST response but NOT re-populated from the GET endpoint after refresh?

3. **lineUiMode handling**: After bootstrap, when `lineUiMode` is `PENDING_HANDOVER_REVIEW`, does the frontend trigger a follow-up call to `GET /handover/pending`?

4. **State key mismatch**: Is the review screen reading from a key like `handoverDetail` that is set by POST but never re-set from the refresh flow?

---

## Nullability Rules

| Field                        | When Present                                                                               | When Absent                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| `incompletePallet`           | Object with productTypeId, productTypeName, quantity                                       | **Omitted from JSON** (not null — absent due to `@JsonInclude(NON_NULL)`) |
| `looseBalances`              | Non-empty list of items                                                                    | Empty list `[]`                                                           |
| `looseBalanceCount`          | Integer >= 1                                                                               | `0`                                                                       |
| `handoverType`               | Always present: `"NONE"`, `"INCOMPLETE_PALLET_ONLY"`, `"LOOSE_BALANCES_ONLY"`, or `"BOTH"` | Always present                                                            |
| `incomingOperatorName`       | Set after confirm/reject                                                                   | **Omitted from JSON**                                                     |
| `incomingOperatorId`         | Set after confirm/reject                                                                   | **Omitted from JSON**                                                     |
| `confirmedAt` / `rejectedAt` | Set on respective action                                                                   | **Omitted from JSON**                                                     |

---

## The Two DTO Shapes — Quick Reference

### `LineHandoverResponse` (Full — from `/handover/pending`, `/handover` POST, `/handover/{id}/confirm`, `/handover/{id}/reject`)

- Has `looseBalances` list with individual item details
- Has `incompletePallet` object with quantity
- This is what the review screen needs

### `LineHandoverSummary` (Condensed — nested inside `LineStateResponse` from `/state`, `/bootstrap`)

- Has `looseBalanceCount` (int only)
- Has `hasIncompletePallet` (boolean only) and `incompletePalletProductTypeName` (string)
- Does NOT have individual loose balance items or incomplete pallet quantity
- This is for the line overview/card, not the review screen
