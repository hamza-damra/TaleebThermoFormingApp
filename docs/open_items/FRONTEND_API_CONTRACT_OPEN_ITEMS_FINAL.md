# Frontend API Contract — Open Items Management (Final)

## Base URL

```
/api/v1/palletizing-line
```

Authentication: `X-Device-Key` header (technical device auth). Business identity from per-line operator PIN authorization.

---

## 1. GET `/lines/{lineId}/open-items`

Retrieves all open operational items for the given line's current active session.

### Response: `OpenItemsResponse`

```json
{
  "looseBalances": [
    {
      "productTypeId": 5,
      "productTypeName": "أحمر 20 كغ",
      "loosePackageCount": 15,
      "origin": "CURRENT_SESSION",
      "sourceHandoverId": null
    }
  ],
  "receivedIncompletePallet": null
}
```

### Field Semantics

| Field | Type | Description |
|-------|------|-------------|
| `looseBalances` | `LooseBalanceItemResponse[]` | Always present (may be empty list). Non-zero loose balances in current session. |
| `receivedIncompletePallet` | `ReceivedIncompletePalletResponse?` | Null if no pending received incomplete pallet exists. |

#### `LooseBalanceItemResponse`

| Field | Type | Description |
|-------|------|-------------|
| `productTypeId` | `Long` | Product type ID |
| `productTypeName` | `String` | Snapshot name of product type |
| `loosePackageCount` | `int` | Current loose package count (always > 0) |
| `origin` | `String` | `"CURRENT_SESSION"` or `"CARRIED_FROM_HANDOVER"` |
| `sourceHandoverId` | `Long?` | Handover ID that delivered this balance (null for current-session items) |

#### `ReceivedIncompletePalletResponse`

| Field | Type | Description |
|-------|------|-------------|
| `id` | `Long` | SessionIncompletePallet ID (use for display, not for API calls) |
| `productTypeId` | `Long` | Product type ID |
| `productTypeName` | `String` | Snapshot name of product type |
| `quantity` | `int` | Number of packages in the incomplete pallet |
| `sourceHandoverId` | `Long` | Handover that delivered this incomplete pallet |
| `status` | `String` | Always `"PENDING"` in this response |
| `receivedAt` | `Instant` | ISO-8601 timestamp |
| `receivedAtDisplay` | `String` | Arabic-formatted display string |

### Visibility Rules

- **Loose balances**: Shown for all non-zero balances in the current session, regardless of origin.
- **Received incomplete pallet**: Only shown when status is `PENDING`. Once completed or handed over, it disappears from this response. Only created by confirmed handover — never by same-session actions.

### Error Responses

| Code | HTTP Status | When |
|------|-------------|------|
| `LINE_AUTHORIZATION_REQUIRED` | 403 | No active authorization on this line |

---

## 2. POST `/lines/{lineId}/loose-balances/produce-pallet`

Creates a pallet by consuming loose balance, optionally adding fresh packages.

### Request: `ProducePalletFromLooseRequest`

```json
{
  "productTypeId": 5,
  "looseQuantityToUse": 15,
  "freshQuantityToAdd": 35
}
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `productTypeId` | `Long` | Yes | Must exist |
| `looseQuantityToUse` | `Integer` | Yes | >= 1 |
| `freshQuantityToAdd` | `Integer` | No | >= 0, defaults to 0 |

### Response: `ProducePalletFromLooseResponse` (HTTP 201)

```json
{
  "pallet": {
    "palletId": 123,
    "scannedValue": "000100000045",
    "operator": { "id": 10, "name": "أحمد" },
    "productType": {
      "id": 5,
      "name": "أحمر 20 كغ",
      "productName": "أحمر",
      "prefix": "0001",
      "color": "أحمر",
      "packageQuantity": 50,
      "packageUnit": "KG"
    },
    "productionLine": { "id": 1, "name": "خط الإنتاج 1", "lineNumber": 1 },
    "quantity": 50,
    "currentDestination": "PRODUCTION",
    "createdAt": "2026-04-03T23:54:08.880Z",
    "createdAtDisplay": "٣ نيسان ٢٠٢٦ ٠٢:٥٤"
  },
  "creationMode": "FROM_LOOSE_PLUS_FRESH",
  "looseQuantityUsed": 15,
  "freshQuantityAdded": 35,
  "finalQuantity": 50
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pallet` | `CreatePalletResponse` | Full pallet details (same as standard pallet creation response) |
| `creationMode` | `String` | `"FROM_LOOSE_ONLY"` or `"FROM_LOOSE_PLUS_FRESH"` |
| `looseQuantityUsed` | `int` | How many loose packages were consumed |
| `freshQuantityAdded` | `int` | How many fresh packages were added (0 if none) |
| `finalQuantity` | `int` | Total pallet quantity = loose + fresh |

### Error Responses

| Code | HTTP Status | When |
|------|-------------|------|
| `PRODUCT_TYPE_NOT_FOUND` | 404 | Invalid productTypeId |
| `LOOSE_BALANCE_NOT_FOUND` | 404 | No loose balance for this product type in current session |
| `INSUFFICIENT_LOOSE_BALANCE` | 400 | `looseQuantityToUse` > available balance |
| `LINE_AUTHORIZATION_REQUIRED` | 403 | No active authorization |
| `PENDING_LINE_HANDOVER_EXISTS` | 409 | Line blocked by pending handover |

---

## 3. POST `/lines/{lineId}/incomplete-pallet/complete`

Completes a received incomplete pallet into a finalized pallet.

### Request: `CompleteIncompletePalletRequest` (body optional)

```json
{
  "additionalFreshQuantity": 10
}
```

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `additionalFreshQuantity` | `Integer` | No | >= 0, defaults to 0 |

If no fresh quantity is needed, the request body can be omitted entirely.

### Response: `CompleteIncompletePalletResponse` (HTTP 201)

```json
{
  "pallet": {
    "palletId": 124,
    "scannedValue": "000100000046",
    "operator": { "id": 10, "name": "أحمد" },
    "productType": { "id": 5, "name": "أحمر 20 كغ", "..." : "..." },
    "productionLine": { "id": 1, "name": "خط الإنتاج 1", "lineNumber": 1 },
    "quantity": 35,
    "currentDestination": "PRODUCTION",
    "createdAt": "2026-04-03T23:54:08.880Z",
    "createdAtDisplay": "٣ نيسان ٢٠٢٦ ٠٢:٥٤"
  },
  "creationMode": "FROM_INCOMPLETE_PALLET_PLUS_FRESH",
  "incompleteQuantityUsed": 25,
  "freshQuantityAdded": 10,
  "finalQuantity": 35,
  "sourceHandoverId": 50
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pallet` | `CreatePalletResponse` | Full pallet details |
| `creationMode` | `String` | `"FROM_INCOMPLETE_PALLET"` or `"FROM_INCOMPLETE_PALLET_PLUS_FRESH"` |
| `incompleteQuantityUsed` | `int` | Original incomplete pallet quantity |
| `freshQuantityAdded` | `int` | Additional fresh packages (0 if none) |
| `finalQuantity` | `int` | Total = incomplete + fresh |
| `sourceHandoverId` | `Long` | The handover that originally delivered this incomplete pallet |

### Error Responses

| Code | HTTP Status | When |
|------|-------------|------|
| `INCOMPLETE_PALLET_NOT_FOUND` | 404 | No pending received incomplete pallet |
| `INCOMPLETE_PALLET_ALREADY_RESOLVED` | 409 | Already completed or handed over |
| `LINE_AUTHORIZATION_REQUIRED` | 403 | No active authorization |
| `PENDING_LINE_HANDOVER_EXISTS` | 409 | Line blocked by pending handover |

---

## Carry-Forward Rules

| Scenario | Loose Balances | Incomplete Pallet |
|----------|---------------|-------------------|
| **Handover Create** | All non-zero auto-included as snapshot | Pending SIP auto-included; combined with declared if same product type |
| **Handover Confirm** | Transferred to incoming `session_product_balances` | New `SessionIncompletePallet` (PENDING) created for incoming auth |
| **Handover Reject** | NOT transferred; dispute event only | NOT transferred; dispute event only |

---

## Edge Cases the Frontend Should Handle

1. **Empty open items**: Both lists empty — show "no open items" message.
2. **Loose balance already consumed**: If operator uses `producePalletFromLoose` then re-fetches, the item disappears or has reduced count.
3. **Incomplete pallet already completed**: If operator completes then re-fetches, `receivedIncompletePallet` becomes null.
4. **Line blocked by pending handover**: All write actions return `PENDING_LINE_HANDOVER_EXISTS`. Show appropriate message.
5. **Concurrent access**: Backend uses row-level locking. If two devices somehow access the same line, one will succeed and the other will get a conflict or stale data.
6. **Mixed-origin loose balances**: A single product type can have loose balance from both handover AND product switch in the same session. The `origin` shows `"CARRIED_FROM_HANDOVER"` if any part came from handover.

---

## `creationMode` Values Reference

| Value | Meaning |
|-------|---------|
| `STANDARD` | Normal production line pallet (no loose/incomplete involved) |
| `FROM_LOOSE_ONLY` | Pallet created entirely from loose balance |
| `FROM_LOOSE_PLUS_FRESH` | Pallet from loose balance + additional fresh packages |
| `FROM_INCOMPLETE_PALLET` | Pallet from received incomplete pallet only |
| `FROM_INCOMPLETE_PALLET_PLUS_FRESH` | Pallet from incomplete pallet + additional fresh packages |
