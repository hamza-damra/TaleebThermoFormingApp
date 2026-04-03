# Frontend Fix: Missing Request Body on `createHandover` API Call

## Error

```
org.springframework.http.converter.HttpMessageNotReadableException: Required request body is missing:
public org.springframework.http.ResponseEntity<...ApiResponse<...LineHandoverResponse>>
ps.taleeb.taleebbackend.palletizing.PalletizingLineController.createHandover(java.lang.Long, ...LineHandoverRequest)
```

## Root Cause

The Flutter app is calling `POST /api/v1/palletizing-line/lines/{lineId}/handover` **without sending a JSON request body**. The backend endpoint requires `@RequestBody LineHandoverRequest` — Spring rejects the request if no body is present at all.

All fields in `LineHandoverRequest` are **optional/nullable**, so the minimum valid body is just `{}`.

This is a **pure frontend issue** — the backend contract is correct.

## Exact Fix Required

Find the API call for creating a handover (likely in a provider, service, or API client class related to palletizing/handover). It will look something like:

```dart
// BROKEN — no body sent, or body is null
final response = await dio.post(
  '/api/v1/palletizing-line/lines/$lineId/handover',
  // Missing: data parameter
);
```

**Fix it** by always sending a JSON body, even if all fields are null:

```dart
// FIXED — always send a JSON body
final response = await dio.post(
  '/api/v1/palletizing-line/lines/$lineId/handover',
  data: {
    // All fields are optional. Include whichever are available:
    if (incompletePalletProductTypeId != null)
      'incompletePalletProductTypeId': incompletePalletProductTypeId,
    if (incompletePalletQuantity != null)
      'incompletePalletQuantity': incompletePalletQuantity,
    if (incompletePalletScannedValue != null)
      'incompletePalletScannedValue': incompletePalletScannedValue,
    if (notes != null)
      'notes': notes,
  },
);
```

Or at minimum:

```dart
data: {},  // Empty JSON object — this alone fixes the error
```

## Backend Endpoint Contract

### Request

```
POST /api/v1/palletizing-line/lines/{lineId}/handover
Authorization: Bearer <jwt_token>
Content-Type: application/json
```

**Path parameter**: `lineId` (Long) — the production line ID

**Request body** (`LineHandoverRequest`):

| Field                            | Type    | Required | Description                                         |
| -------------------------------- | ------- | -------- | --------------------------------------------------- |
| `incompletePalletProductTypeId`  | Long    | No       | Product type ID for an incomplete pallet on the line |
| `incompletePalletQuantity`       | Integer | No       | Package count in the incomplete pallet               |
| `incompletePalletScannedValue`   | String  | No       | Scanned value (12-digit) for the incomplete pallet   |
| `notes`                          | String  | No       | Free-text notes for the handover                     |

**Minimum valid body**: `{}`

**Example body with incomplete pallet**:

```json
{
  "incompletePalletProductTypeId": 1,
  "incompletePalletQuantity": 25,
  "incompletePalletScannedValue": "000100000042",
  "notes": "Shift ended mid-pallet"
}
```

### Response (201 Created)

Wrapped in `ApiResponse<LineHandoverResponse>`:

```json
{
  "success": true,
  "data": {
    "id": 10,
    "lineId": 1,
    "lineName": "Line A",
    "status": "PENDING",
    "outgoingOperatorName": "Ahmad",
    "outgoingOperatorId": 5,
    "incomingOperatorName": null,
    "incomingOperatorId": null,
    "incompletePallet": {
      "productTypeId": 1,
      "productTypeName": "أحمر 20 كغ",
      "quantity": 25,
      "scannedValue": "000100000042"
    },
    "looseBalances": [
      {
        "productTypeId": 1,
        "productTypeName": "أحمر 20 كغ",
        "loosePackageCount": 3
      }
    ],
    "looseBalanceCount": 1,
    "notes": "Shift ended mid-pallet",
    "createdAt": "2026-04-02T16:38:35.000Z",
    "createdAtDisplay": "2026-04-02T19:38:35.000+03:00",
    "confirmedAt": null,
    "confirmedAtDisplay": null,
    "rejectedAt": null,
    "rejectedAtDisplay": null
  }
}
```

**Notes**:
- `incompletePallet` is `null` if no incomplete pallet info was provided in the request.
- `looseBalances` is auto-generated from the server's `SessionProductBalance` records — the frontend does NOT send these.
- `incomingOperatorName`/`incomingOperatorId` are `null` until the handover is confirmed by an incoming operator.
- `status` values: `PENDING`, `CONFIRMED`, `REJECTED`.
- Null fields are omitted from JSON (`@JsonInclude(NON_NULL)`).

### Error Responses

| HTTP Status | Error Code                      | When                                                |
| ----------- | ------------------------------- | --------------------------------------------------- |
| 400         | (Spring default)                | Missing or malformed request body (current bug)     |
| 401         | Unauthorized                    | Missing/invalid JWT                                 |
| 403         | Forbidden                       | User not authorized for this line                   |
| 404         | `PRODUCT_TYPE_NOT_FOUND`        | `incompletePalletProductTypeId` doesn't exist       |
| 409         | `PENDING_LINE_HANDOVER_EXISTS`  | A pending handover already exists for this line     |

## Quick Checklist

- [ ] Search for the handover API call (look for `handover` in API service/provider files)
- [ ] Ensure the POST request includes `data: { ... }` (or at minimum `data: {}`)
- [ ] Ensure `Content-Type: application/json` header is set (Dio does this automatically when `data` is a Map)
- [ ] Parse the response using the `LineHandoverResponse` shape above
- [ ] Test: trigger a handover → verify 201 response, no more `HttpMessageNotReadableException`
