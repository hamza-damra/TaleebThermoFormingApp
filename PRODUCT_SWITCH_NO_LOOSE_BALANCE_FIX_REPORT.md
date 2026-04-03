# Product Switch "No Loose Balance" Bug Fix Report

## Exact Root Cause

**Response parsing mismatch** in the repository layer.

The backend endpoint `POST /api/v1/palletizing-line/lines/{lineId}/product-switch` returns a **`LineStateResponse` object** (a JSON object containing `sessionTable`, `authorized`, `authorization`, etc.), identical in shape to `GET /lines/{lineId}/state`.

However, the frontend repository method `switchProduct()` used `ApiClient.requestList()`, which assumes `response.data` is a **JSON array** (`List<dynamic>`). The cast at `api_client.dart:102`:

```dart
final dataList = responseData['data'] as List<dynamic>;
```

threw a `TypeError` because `data` was a `Map<String, dynamic>`, not a `List`. This `TypeError` was caught by the generic `catch (e)` block in the provider, which produced the user-facing error message:

> فشل في تبديل المنتج

This failure occurs for **both** "لا يوجد فالت" (looseCount = 0) and "نعم يوجد فالت" (looseCount > 0) paths, because the parsing bug happens **after** the backend processes the request successfully. The bug is entirely in response parsing, not in the request payload.

## Where the Bug Was Found

- **File:** `lib/data/repositories/palletizing_repository_impl.dart`
- **Method:** `switchProduct()`
- **Line:** 165 (original) — `_apiClient.requestList<SessionTableRow>(...)`
- **Layer:** Frontend — repository/data layer
- **Type:** Frontend-only (integration contract mismatch)

## What Code Was Changed

### 1. `lib/data/repositories/palletizing_repository_impl.dart` — **Primary fix**

Changed `switchProduct()` from `requestList()` to `request()` with a custom parser that correctly extracts the `sessionTable` array from the `LineStateResponse` object:

```dart
// BEFORE (broken):
return await _apiClient.requestList<SessionTableRow>(
  path: '/palletizing-line/lines/$lineId/product-switch',
  method: 'POST',
  data: { ... },
  itemParser: (json) => SessionTableRowModel.fromJson(json),
);

// AFTER (fixed):
return await _apiClient.request<List<SessionTableRow>>(
  path: '/palletizing-line/lines/$lineId/product-switch',
  method: 'POST',
  data: { ... },
  parser: (json) {
    final data = json['data'] as Map<String, dynamic>;
    final sessionTableJson = data['sessionTable'] as List<dynamic>? ?? [];
    return sessionTableJson
        .map((item) =>
            SessionTableRowModel.fromJson(item as Map<String, dynamic>))
        .toList();
  },
);
```

### 2. `lib/presentation/providers/palletizing_provider.dart` — **Diagnostics improvement**

Added `debugPrint` in the generic `catch (e)` block of `switchProduct()` so that unexpected errors are logged with the actual exception message instead of being silently replaced by a generic string.

## Request/Response Behavior Corrected

### Request (unchanged — was already correct)
```
POST /api/v1/palletizing-line/lines/{lineId}/product-switch
Body: { "previousProductTypeId": <int>, "loosePackageCount": <int> }
```

- `loosePackageCount: 0` is sent when "لا يوجد فالت" is selected
- `loosePackageCount: N` (N > 0) is sent when "نعم يوجد فالت" is selected with a count

### Response (parsing fixed)

The backend returns:
```json
{
  "success": true,
  "data": {
    "lineId": 1,
    "lineNumber": 1,
    "lineName": "...",
    "authorized": true,
    "authorization": { ... },
    "sessionTable": [
      {
        "productTypeId": 5,
        "productTypeName": "TT-20 BLACK 500",
        "completedPalletCount": 0,
        "completedPackageCount": 0,
        "loosePackageCount": 10
      }
    ],
    ...
  }
}
```

The fix now correctly navigates into `data.sessionTable` to extract the session rows.

## Scenarios Verified (code trace)

| Scenario | Status |
|----------|--------|
| Switch product with "لا يوجد فالت" (looseCount = 0) | ✅ Fixed — parser now handles LineStateResponse correctly |
| Switch product with "نعم يوجد فالت" (looseCount > 0) | ✅ Fixed — same parser path, was also broken before |
| Switch back to a previous product | ✅ Same API path, same fix applies |
| Switch while session has existing balances | ✅ No change — backend handles balance merging |
| Switch when network is slow | ✅ No change — timeout handling is separate from parsing |
| Switch immediately after bootstrap/refresh | ✅ No change — no race condition; fix is in response parsing |
| Session table updates after success | ✅ Provider stores parsed `sessionTable` in `_sessionTables` |
| Cancel dialog returns null | ✅ No change — null check in UI handler prevents API call |
| Handover flow unaffected | ✅ No change — different endpoint and code path |

## Remaining Risks / Notes

1. **No backend change needed.** The backend was returning the correct `LineStateResponse` all along. The bug was purely in frontend response parsing.

2. **The fix only extracts `sessionTable` from the response.** The `LineStateResponse` also contains updated `authorized`, `authorization`, `pendingHandover`, `lineUiMode`, etc. Currently these fields are not consumed after a product switch. If future requirements need them, the return type could be changed to `BootstrapLineState` — but that would be a feature enhancement, not a bug fix.

3. **Both loose-balance paths were broken.** Despite the bug report focusing on "لا يوجد فالت", the "نعم يوجد فالت" path had the same parsing bug. Both are now fixed.

4. **The `debugPrint` addition** in the provider's generic catch block ensures that any future unexpected errors will be visible in development logs, preventing silent failures.

---

*Fix applied: April 2026*
*Root cause: Frontend response parsing mismatch (requestList vs object response)*
*Scope: Frontend-only, 2 files changed, 0 backend changes*
