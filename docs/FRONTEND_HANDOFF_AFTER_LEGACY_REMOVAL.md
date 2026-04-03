# Frontend Handoff After Legacy Removal

## Target Audience

This document is for the **frontend AI agent** of the Taleeb Thermoforming / Palletizing app (Flutter mobile app and/or web admin).

---

## Summary of Backend Changes

A cleanup was performed to remove the last remnants of the old legacy workflow from the backend. **The business workflow itself has NOT changed.**

### What Was Removed (Backend Only)

| Removed Item | Description |
|---|---|
| `PalletizingService.createPallet(CreatePalletRequest, userId)` | Old user-login-based pallet creation method. Dead code — no endpoint called it. |
| `PalletizingService.recordPrintAttempt(palleteId, request, userId)` | Old user-login-based print attempt method. Dead code — no endpoint called it. |
| `PalletizingService.createPalletForLine(lineId, productTypeId, quantity, userId)` | `@Deprecated` wrapper that discarded the `userId` param. Dead code — no endpoint called it. |
| `PalletizingService.recordPrintAttemptForLine(lineId, palletId, request, userId)` | `@Deprecated` wrapper that discarded the `userId` param. Dead code — no endpoint called it. |
| `CreatePalletRequest.java` DTO | Only used by the removed old `createPallet` method. |

These were **internal backend dead code** — they had no exposed endpoints and were never called by any API controller.

---

## What Did NOT Change

### Endpoint Paths — NO CHANGES

All existing API endpoints remain exactly the same:

| Endpoint | Status |
|---|---|
| `POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin` | Unchanged |
| `GET /api/v1/palletizing-line/lines/{lineId}/authorization` | Unchanged |
| `DELETE /api/v1/palletizing-line/lines/{lineId}/authorization` | Unchanged |
| `GET /api/v1/palletizing-line/lines/{lineId}/state` | Unchanged |
| `GET /api/v1/palletizing-line/lines/{lineId}/session-table` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/pallets` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/product-switch` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/handover` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm` | Unchanged |
| `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject` | Unchanged |
| `GET /api/v1/palletizing-line/lines/{lineId}/handover/pending` | Unchanged |
| `GET /api/v1/palletizing-line/bootstrap` | Unchanged |
| `GET /api/v1/shift-schedule/current-shift` | Unchanged |
| `POST /api/v1/auth/pin-login` | Unchanged |
| All web admin endpoints (`/web/admin/**`) | Unchanged |

### Request/Response Contracts — NO CHANGES

All request bodies, response bodies, field names, types, and envelopes (`ApiResponse<T>`) remain exactly the same. No fields were added, removed, or renamed in any API contract.

### Authentication — NO CHANGES

- `X-Device-Key` header for palletizing-line endpoints: unchanged
- JWT authentication for shift-schedule, app-updates, me endpoints: unchanged
- Web session-based auth for admin pages: unchanged

### Business Workflow — NO CHANGES

The approved business workflow is fully preserved:

- Operator authorization via PIN on a production line
- Pallet creation (operator derived from line authorization)
- Print attempt recording
- Product switch with loose balance tracking
- Session summary / session table
- Line handover (create, confirm, reject)
- Handover dispute resolution by admin
- Line state overview
- Shift schedule management

---

## Frontend Action Items

### Can the Frontend Delete Any Old Compatibility Logic?

**If** the frontend had any code paths for:

- Sending a `userId` parameter to pallet creation or print attempt endpoints
- Using an old `CreatePalletRequest` shape that included `operatorId` and `productionLineId` in the body
- Calling any non-line-scoped palletizing endpoint (e.g., a hypothetical `/api/v1/palletizing/**` without `-line`)

...then **yes**, that code can be safely deleted. Those backend paths no longer exist.

### Must the Frontend Update Any References/Assumptions?

**No.** All currently used API endpoints, request shapes, response shapes, and authentication mechanisms are unchanged.

### Explicit Confirmation

- **No endpoint paths changed** — all URLs are identical
- **No request contracts changed** — all request bodies are identical
- **No response contracts changed** — all response bodies are identical
- **No authentication flow changed** — X-Device-Key and JWT flows are identical
- **The business workflow itself MUST remain unchanged** — no behavioral changes were made

---

## Summary

This was a backend-internal dead code cleanup. **Zero changes** to the API surface, contracts, or business behavior. The frontend should require **no modifications** unless it was referencing old compatibility code paths that were already non-functional.
