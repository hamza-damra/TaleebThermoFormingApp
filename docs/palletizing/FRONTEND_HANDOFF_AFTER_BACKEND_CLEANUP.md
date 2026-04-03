# Frontend Handoff — After Backend Legacy Cleanup

## Purpose

This document tells the **frontend AI agent** (or developer) what changed on the backend and what actions are needed on the frontend side. The backend has removed the old global shift-handover workflow and the deprecated `/api/v1/palletizing/**` controller. The new line-scoped workflow (`/api/v1/palletizing-line/**`) is **completely unchanged**.

---

## Removed API Endpoints

The following endpoints **no longer exist** on the backend. Any frontend code calling them must be deleted or migrated.

### Old Global Shift Handover (`/api/v1/shift-handover/**`)

| Method | Path | What it did |
|---|---|---|
| `POST` | `/api/v1/shift-handover` | Create a global pending handover |
| `GET` | `/api/v1/shift-handover/pending` | Get the current pending handover |
| `POST` | `/api/v1/shift-handover/{id}/confirm` | Confirm a pending handover |
| `POST` | `/api/v1/shift-handover/{id}/reject` | Reject a pending handover (creates dispute) |

**Action**: Delete all code, screens, and API client methods that call these endpoints.

**Replacement**: The per-line handover flow at `/api/v1/palletizing-line/lines/{lineId}/handover` (already implemented on both backend and frontend for the new app).

### Old Legacy Palletizing (`/api/v1/palletizing/**`)

| Method | Path | What it did |
|---|---|---|
| `GET` | `/api/v1/palletizing/operators` | List active operators |
| `GET` | `/api/v1/palletizing/product-types` | List active product types |
| `GET` | `/api/v1/palletizing/production-lines` | List active production lines |
| `POST` | `/api/v1/palletizing/pallets` | Create pallet (operator from client body) |
| `POST` | `/api/v1/palletizing/pallets/{id}/print-attempts` | Record print attempt |
| `GET` | `/api/v1/palletizing/lines/{lineId}/summary` | Line summary |

**Action**: Delete all code that calls these endpoints.

**Replacement**: The line-scoped endpoints at `/api/v1/palletizing-line/**` (already in use by the new app):
- `GET /api/v1/palletizing-line/bootstrap` — returns operators, product types, production lines in one call
- `POST /api/v1/palletizing-line/lines/{lineId}/pallets` — create pallet (operator derived from line authorization)
- `POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts` — record print attempt
- `GET /api/v1/palletizing-line/lines/{lineId}/state` — full line state including session table

---

## Unchanged Endpoints (No Action Needed)

All `/api/v1/palletizing-line/**` endpoints remain **exactly as before**:

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/palletizing-line/bootstrap` | App bootstrap data |
| `POST` | `/palletizing-line/lines/{lineId}/authorize-pin` | Operator PIN authorization |
| `GET` | `/palletizing-line/lines/{lineId}/authorization` | Get current authorization |
| `DELETE` | `/palletizing-line/lines/{lineId}/authorization` | Release authorization |
| `GET` | `/palletizing-line/lines/{lineId}/state` | Full line state |
| `GET` | `/palletizing-line/lines/{lineId}/session-table` | Session production table |
| `POST` | `/palletizing-line/lines/{lineId}/pallets` | Create pallet |
| `POST` | `/palletizing-line/lines/{lineId}/pallets/{id}/print-attempts` | Print attempt |
| `POST` | `/palletizing-line/lines/{lineId}/product-switch` | Product switch |
| `POST` | `/palletizing-line/lines/{lineId}/handover` | Create line handover |
| `POST` | `/palletizing-line/lines/{lineId}/handover/{id}/confirm` | Confirm handover |
| `POST` | `/palletizing-line/lines/{lineId}/handover/{id}/reject` | Reject handover |
| `GET` | `/palletizing-line/lines/{lineId}/handover/pending` | Get pending handover |

Also unchanged:
- `/api/v1/auth/**` — login endpoints
- `/api/v1/movements/**` — pallet movement tracking
- `/api/v1/app-updates/**` — APK distribution
- `/api/v1/shift-schedule/**` — shift schedule queries
- `/api/v1/me` — current user info

---

## Admin Portal Changes

### Removed Page
- **Handover Disputes** (`/web/admin/handover-disputes`) — the admin page for resolving old global handover disputes has been removed along with its sidebar navigation link.

### Unchanged Pages
- **Line Handover Disputes** (`/web/admin/line-handover-disputes`) — still present and working
- **Line State Overview** (`/web/admin/line-state`) — still present and working
- **Line Handovers** (`/web/admin/line-handovers`) — still present and working
- All other admin pages (dashboard, users, product types, operators, production lines, shift schedules, app updates) — unchanged

---

## Error Code Changes

The following error codes were removed from the backend. Frontend code should not expect these:

- `PRODUCT_TYPE_HAS_HANDOVER_REFERENCES`
- `HANDOVER_NOT_FOUND`
- `HANDOVER_ALREADY_RESOLVED`
- `NO_PENDING_HANDOVER`
- `PENDING_HANDOVER_EXISTS`
- `DISPUTE_ALREADY_RESOLVED`
- `HANDOVER_DUPLICATE_LINE`
- `HANDOVER_TOO_MANY_ITEMS`

All `LINE_HANDOVER_*` error codes remain unchanged:
- `PENDING_LINE_HANDOVER_EXISTS`
- `LINE_HANDOVER_NOT_FOUND`
- `LINE_HANDOVER_ALREADY_RESOLVED`
- `LINE_HANDOVER_NOT_REJECTED`

---

## Database Changes

A new migration `V24__drop_legacy_shift_handover_tables.sql` will drop:
- `shift_handovers`
- `shift_handover_items`

The `line_handovers` and `line_handover_loose_balances` tables are **untouched**.

---

## Summary of Frontend Actions

1. **Delete** any API client code for `/api/v1/shift-handover/**`
2. **Delete** any API client code for `/api/v1/palletizing/**`
3. **Delete** any screens/components that use the old global handover flow
4. **Remove** references to the removed error codes in error handling
5. **No changes** needed for the line-scoped workflow — it works exactly as before

If the frontend app was already migrated to the new line-scoped flow, there is likely **nothing to do** other than cleaning up dead code.
