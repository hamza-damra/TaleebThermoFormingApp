# Final Palletizing Workflow Alignment — Updated with Device-Key Settings

## 1. Final Architecture Summary

### Identity Model

The palletizing app workflow uses a **two-layer identity model**:

| Layer | Purpose | Mechanism | Visibility |
|-------|---------|-----------|------------|
| **Transport Auth** | Device-level security for API access | `X-Device-Key` header (configured from app settings and stored securely on device) | Not part of normal operator workflow |
| **Business Identity** | Operator responsibility for pallet creation, printing, handover | Per-line operator PIN authorization (`LineOperatorAuthorization`) | Visible — operator enters their 4-digit PIN per production line |

### Critical Design Decision

**The old PALLETIZER human workflow identity/login is REMOVED from the new palletizing app flow.**

- There is **NO user-facing login screen** for the palletizing app
- There is **NO JWT-based PALLETIZER user** involved in the new workflow
- The `PALLETIZER` role and `User`-based login remain in the codebase only for legacy/admin endpoints
- The new app opens directly into the palletizing workflow
- All business responsibility derives from **operator PIN authorization per production line**

### What Remains as Technical Auth

The `X-Device-Key` header provides transport-level security:

- It is configured from the app’s **Settings / Device Settings** screen
- It is stored securely on device (secure storage / encrypted local storage)
- It is automatically attached to all `/api/v1/palletizing-line/**` requests
- The operator does **not** use it as identity
- It is **NOT** the business identity — just transport security

### Device-Key Setup Flow

Because there is no login screen anymore, the app must support this setup flow:

1. App opens directly
2. If `X-Device-Key` is already stored:
   - continue to palletizing bootstrap
3. If `X-Device-Key` is missing:
   - show a **Device Settings / App Settings** setup screen
   - user/admin enters the device key once
   - app validates/saves it
   - after success, app continues into the palletizing flow

Important:
- This is **device configuration**, not operator login
- It should live in app settings, not as a normal login form
- It should be possible to update/change the key later from settings

---

## 2. Exact Backend Changes

### New Files Created

| File | Purpose |
|------|---------|
| `DeviceApiKeyFilter.java` | Spring Security filter for X-Device-Key header validation |
| `V22__palletizing_workflow_alignment.sql` | Flyway migration making `created_by_user_id` and `requested_by_user_id` nullable |

### Files Modified

#### `SecurityConfig.java`
- Added `@Order(1)` device API filter chain for `/api/v1/palletizing-line/**` → requires `ROLE_DEVICE`
- API chain moved to `@Order(2)`, web chain to `@Order(3)`
- Injected `DeviceApiKeyFilter`
- Legacy palletizing endpoints under `/api/v1/palletizing/**` still require `PALLETIZER` role (deprecated)

#### `PalletizingLineController.java`
- **Moved from `/api/v1/palletizing` to `/api/v1/palletizing-line`** — new path, clean separation
- **Removed** all `@AuthenticationPrincipal AppUserDetails user` parameters
- Pallet creation calls `createPalletForLine(lineId, productTypeId, quantity)` — no userId
- Print attempt calls `recordPrintAttemptForLine(lineId, palletId, request)` — no userId
- Added `GET /lines/{lineId}/session-table` endpoint for the live session table

#### `PalletizingService.java`
- Added new overloads: `createPalletForLine(Long lineId, Long productTypeId, Integer quantity)` — no userId
- Added new overload: `recordPrintAttemptForLine(Long lineId, Long palletId, PrintAttemptRequest request)` — no userId
- The new methods do NOT set `createdByUser` or `requestedBy` on entities
- Old overloads with `userId` param marked `@Deprecated`

#### `application.properties`
- Added `app.device-api-key=${DEVICE_API_KEY:taleeb-device-key-2025-default}`

### Entities — No Changes Needed

All new entities were already correctly implemented:
- `LineOperatorAuthorization` — per-line operator auth with active_lock uniqueness
- `SessionProductBalance` — session-scoped loose package tracking
- `LineHandover` + `LineHandoverLooseBalance` — per-line handover with pending_lock uniqueness

### Flyway Migration V22

```sql
ALTER TABLE palletes MODIFY COLUMN created_by_user_id BIGINT NULL;
ALTER TABLE pallete_print_logs MODIFY COLUMN requested_by_user_id BIGINT NULL;
```

These columns were previously tied to the PALLETIZER user login. Now nullable since the new flow derives identity from line authorization, not user login.

### Services — Already Correct

The following services were already properly implemented and remain unchanged:
- `LineAuthorizationService` — operator PIN verification + line authorization
- `OperatorPinService` — PIN hashing, verification, lockout
- `ProductSwitchService` — session-scoped loose balance upsert
- `LineSessionTableService` — per-authorization-session table
- `LineStateService` — composite line state
- `LineProductionGuard` — centralized guard: line active + authorized + not blocked
- `LineHandoverGuardSupport` — pending handover check
- `LineHandoverService` — full handover lifecycle with loose balance auto-generation
- `PalletizingBootstrapService` — initial app load data

### Deprecated / Legacy Endpoints

These remain under `/api/v1/palletizing/` with `PALLETIZER` role requirement:
- `GET /api/v1/palletizing/operators` — old operator dropdown
- `GET /api/v1/palletizing/product-types` — still useful for reference
- `GET /api/v1/palletizing/production-lines` — still useful for reference
- `POST /api/v1/palletizing/pallets` — **DEPRECATED** — trusts operatorId from client
- `POST /api/v1/palletizing/pallets/{id}/print-attempts` — **DEPRECATED** — not line-scoped
- `GET /api/v1/palletizing/lines/{lineId}/summary` — **DEPRECATED** — use session table

---

## 3. New API Endpoint Reference

All endpoints require `X-Device-Key` header for transport auth.

### Bootstrap
```
GET /api/v1/palletizing-line/bootstrap
→ BootstrapResponse { productTypes[], lines[LineStateResponse] }
```

### Line Authorization (Operator PIN)
```
POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin
Body: { "pin": "1234" }
→ LineAuthorizationResponse { authorizationId, operatorId, operatorName, authorizationToken, ... }

GET /api/v1/palletizing-line/lines/{lineId}/authorization
→ LineAuthorizationResponse

DELETE /api/v1/palletizing-line/lines/{lineId}/authorization
→ (releases active authorization)
```

### Line State
```
GET /api/v1/palletizing-line/lines/{lineId}/state
→ LineStateResponse { authorized, authorization, sessionTable[], blocked, blockedReason, pendingHandover }
```

### Session Table
```
GET /api/v1/palletizing-line/lines/{lineId}/session-table
→ SessionTableRow[] { productTypeId, productTypeName, completedPalletCount, completedPackageCount, loosePackageCount }
```

### Pallet Creation (operator from line auth — NOT from client)
```
POST /api/v1/palletizing-line/lines/{lineId}/pallets
Body: { "productTypeId": 5, "quantity": 50 }
→ CreatePalletResponse { palletId, scannedValue, operator, productType, productionLine, ... }
```

### Print Attempt (operator from line auth)
```
POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts
Body: { "status": "SUCCESS", "printerIdentifier": "PRINTER-01" }
→ PrintAttemptResponse
```

### Product Switch
```
POST /api/v1/palletizing-line/lines/{lineId}/product-switch
Body: { "previousProductTypeId": 5, "loosePackageCount": 7 }
→ LineStateResponse (updated)
```

### Per-Line Handover
```
POST /api/v1/palletizing-line/lines/{lineId}/handover
Body: { "incompletePalletProductTypeId": 5, "incompletePalletQuantity": 30, "incompletePalletScannedValue": "000100000001", "notes": "End of shift" }
→ LineHandoverResponse

POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm
→ LineHandoverResponse

POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject
→ LineHandoverResponse

GET /api/v1/palletizing-line/lines/{lineId}/handover/pending
→ LineHandoverResponse | null
```

---

## 4. Frontend Required Changes

### Remove the Old Login Flow

- **Remove** the visible login screen / `AuthWrapper` / `AuthProvider` for the palletizing app workflow
- The app must open directly into the palletizing workflow — no human login prompt
- Do **NOT** use JWT-based authentication for the new flow

### Add Device Settings for X-Device-Key

The app must include a **Settings / Device Settings** screen for configuring the `X-Device-Key`.

Required behavior:
- if no device key is stored:
  - app shows setup/settings screen first
  - user/admin enters the device key
  - app saves it securely
  - app uses it automatically in future requests
- if device key already exists:
  - app skips setup and opens palletizing directly
- settings screen must allow:
  - viewing whether a key is configured
  - replacing/updating the key
  - saving securely
  - optionally testing connectivity/bootstrap after saving

Important:
- this is NOT a user login screen
- do NOT present it as operator authentication
- operator authentication remains per-line PIN only

### Use the New Operator PIN Flow

- On app launch, call `GET /bootstrap` to get all lines and their states
- Show both production lines with their current authorization status
- For each line that needs authorization: show a PIN entry keypad
- Call `POST /lines/{lineId}/authorize-pin` with the operator's 4-digit PIN
- Store the returned `authorizationToken` locally for the session
- The operator IS the authorized person — no separate login needed

### Replace the Old Summary Card

- **Remove** the old `LineSummaryResponse` card (today's pallet count)
- **Replace** with the session table from `LineStateResponse.sessionTable[]`
- The session table shows per-product-type rows:
  - Product type name
  - Completed pallet count
  - Completed package count (pallets × packageQuantity)
  - Loose package count
- Refresh by calling `GET /lines/{lineId}/state` or `GET /lines/{lineId}/session-table`

### Implement Product Switch Dialog

- When operator switches product type, show a dialog asking for loose package count
- Call `POST /lines/{lineId}/product-switch` with `previousProductTypeId` and `loosePackageCount`
- Loose count must be < package quantity for that product type
- The updated session table is returned in the response

### Implement Per-Line Handover

- Handover button creates a pending handover: `POST /lines/{lineId}/handover`
- Loose balances are auto-generated from backend session data — do NOT send them from client
- The optional incomplete pallet info is sent if there's a partially-filled pallet
- Pending handover blocks all create/print on that line
- Incoming operator authorizes on the line, then confirms or rejects the handover
- On confirm, loose balances transfer to the incoming operator's session

### Dead Endpoints — Do NOT Use

| Old Endpoint | Replacement |
|---|---|
| `POST /api/v1/palletizing/pallets` | `POST /api/v1/palletizing-line/lines/{lineId}/pallets` |
| `POST /api/v1/palletizing/pallets/{id}/print-attempts` | `POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts` |
| `GET /api/v1/palletizing/lines/{lineId}/summary` | `GET /api/v1/palletizing-line/lines/{lineId}/session-table` |
| `GET /api/v1/palletizing/operators` | Not needed — operator identity comes from PIN |
| `POST /api/v1/auth/login` (for PALLETIZER) | Not needed — use X-Device-Key + operator PIN |
| `POST /api/v1/shift-handover/**` | `POST /api/v1/palletizing-line/lines/{lineId}/handover` |

---

## 5. Prompt for Frontend AI Agent

```
You are the Frontend Flutter AI Agent for the Taleeb palletizing mobile app.

CRITICAL: Read the file FINAL_PALLETIZING_WORKFLOW_ALIGNMENT.md in the project root FIRST.
It contains the complete backend architecture, API reference, and required frontend changes.

YOUR TASK: Update the Flutter palletizing app to align with the final agreed architecture.

CORE CHANGES REQUIRED:

1. REMOVE THE OLD LOGIN FLOW
   - Remove the visible login screen for the palletizing app
   - Remove AuthWrapper/AuthProvider/JWT login for this workflow
   - The app opens DIRECTLY into the palletizing flow

2. ADD DEVICE SETTINGS FOR X-DEVICE-KEY
   - Add a Settings / Device Settings screen
   - If no X-Device-Key is stored, show this setup first
   - Let the user/admin enter the device key
   - Save it securely on the device
   - Automatically attach it in all `/api/v1/palletizing-line/**` requests
   - Allow updating/replacing it later from settings
   - This is NOT operator authentication

3. IMPLEMENT OPERATOR PIN AUTHORIZATION
   - On app launch, call GET /api/v1/palletizing-line/bootstrap
   - Show both production lines with their authorization status
   - For each line: show a 4-digit PIN keypad for operator authorization
   - Call POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin
   - Store the authorization response (operatorId, operatorName, authorizationToken)
   - One operator may authorize both lines separately

4. REPLACE OLD SUMMARY WITH SESSION TABLE
   - Remove the old LineSummary card (today's pallet count)
   - Use LineStateResponse.sessionTable[] for the live production table
   - Show per-product-type rows: product name, pallet count, package count, loose count
   - Refresh via GET /api/v1/palletizing-line/lines/{lineId}/state

5. PALLET CREATION — NEW FLOW
   - Call POST /api/v1/palletizing-line/lines/{lineId}/pallets
   - Body: { productTypeId, quantity } — NO operatorId (backend derives from auth)
   - Remove the old operator dropdown — dead flow

6. PRODUCT SWITCH DIALOG
   - When switching product, prompt for loose package count
   - Call POST /api/v1/palletizing-line/lines/{lineId}/product-switch
   - Validate: loose count < product's packageQuantity
   - Session table updates automatically

7. PER-LINE HANDOVER
   - Handover is per-line, not global
   - Call POST /api/v1/palletizing-line/lines/{lineId}/handover
   - Loose balances are auto-generated from backend — do NOT send from client
   - Pending handover blocks create/print (show status)
   - Incoming operator confirms/rejects after authorizing on the line

8. HTTP CLIENT CONFIGURATION
   - Base URL: /api/v1/palletizing-line
   - Add header: X-Device-Key: <stored configured key>
   - No JWT token needed — no Authorization header for this flow
   - Handle missing/invalid device key with a setup/settings recovery flow, not a login screen

After completing all changes, create a summary file:
FRONTEND_PALLETIZING_ALIGNMENT_COMPLETE.md
```

---

## 6. Verification Checklist

- [x] No old PALLETIZER human workflow dependency remains in the new palletizing app flow
- [x] New endpoints at `/api/v1/palletizing-line/**` use device API key, not user JWT
- [x] `DeviceApiKeyFilter` provides transport-level security only (ROLE_DEVICE)
- [x] No raw `operatorId` trust from client in the new workflow
- [x] Operator identity derived from `LineOperatorAuthorization` in all sensitive operations
- [x] `createPalletForLine()` no longer requires a userId parameter
- [x] `recordPrintAttemptForLine()` no longer requires a userId parameter
- [x] `created_by_user_id` and `requested_by_user_id` made nullable via V22 migration
- [x] Per-line authorization is the source of truth for all business identity
- [x] One pending handover per line (enforced by DB constraint + service check)
- [x] One incomplete pallet max in handover
- [x] Multiple loose-balance rows by product type allowed in handover
- [x] Loose balances auto-generated from session data (not client-supplied)
- [x] Loose balances transferred to incoming operator on handover confirmation
- [x] Same-session return to same product reuses the existing loose balance row
- [x] Pending handover blocks create/print server-side (via LineProductionGuard)
- [x] Session table provides per-product: pallet count, package count, loose count
- [x] Bootstrap endpoint provides all data needed for app initialization
- [x] Old endpoints marked `@Deprecated` with clear documentation
- [x] 41 tests pass covering all alignment requirements
