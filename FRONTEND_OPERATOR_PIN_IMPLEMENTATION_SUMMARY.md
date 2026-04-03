# Frontend Operator PIN Authorization — Implementation Summary

## Overview

This document summarizes the complete frontend refactor that replaced the old operator-dropdown workflow with a new **per-line 4-digit PIN authorization** model. The app now uses a bootstrap-first architecture where the backend is the source of truth for operator authorization, session data, and line state.

---

## What Changed

### Flows Removed
- **Operator dropdown in `ProductionLineSection`** — replaced with read-only authorized operator card
- **Operator dropdown in `CreatePalletDialog`** — removed entirely; operator is resolved by backend from line authorization
- **`operatorId` in create pallet request** — backend determines operator from the line's authorization context
- **Old `SummaryCard` usage** — replaced with backend-driven `SessionTableWidget`
- **Global `loadInitialData()`** — replaced with `loadBootstrap()` which hydrates per-line state
- **Global `isCreating` state** — replaced with per-line `isLineCreating(lineNumber)`
- **`_selectedOperators` map** — removed from provider; operator comes from authorization
- **Old print attempt endpoint** (`POST /palletizing/pallets/{id}/print-attempts`) — replaced with line-scoped endpoint
- **Old create pallet endpoint** (`POST /palletizing/pallets`) — replaced with line-scoped endpoint

### Flows Added
- **Per-line PIN authorization overlay** (`LineAuthOverlay`) — blocks each line independently until a 4-digit PIN is entered
- **Read-only authorized operator display** with "تغيير" (change) action that revokes auth and re-shows the PIN overlay
- **Session table** (`SessionTableWidget`) — professional table showing per-product-type pallet count, package count, and loose balance from backend `sessionTable` data
- **Product-switch loose-balance dialog** (`ProductSwitchDialog`) — when switching products on a line, prompts for loose package count from the previous product
- **Line-scoped handover** (`LineHandoverCard`) — shows pending handover info per line with resolve action, blocks line actions
- **Bootstrap-based initialization** — single `GET /palletizing/bootstrap` call hydrates all lines, products, auth state, session tables, and handover info
- **Per-line state refresh** — `GET /palletizing/lines/{lineId}/state` refreshes a single line after commands
- **11 new Arabic error code mappings** — `OPERATOR_PIN_INVALID`, `OPERATOR_PIN_LOCKED`, `INVALID_PIN_FORMAT`, `LINE_NOT_AUTHORIZED`, `LINE_BLOCKED_BY_PENDING_HANDOVER`, `PALLET_LINE_MISMATCH`, `PENDING_LINE_HANDOVER_EXISTS`, `LINE_HANDOVER_NOT_FOUND`, `LINE_HANDOVER_ALREADY_RESOLVED`, `INVALID_LOOSE_BALANCE`

---

## New Files Created

| File | Purpose |
|------|---------|
| `lib/domain/entities/line_authorization_state.dart` | Per-line auth state entity with `copyWith` |
| `lib/domain/entities/session_table_row.dart` | Session table row entity (product, pallets, packages, loose) |
| `lib/domain/entities/line_handover_info.dart` | Line handover entity with incomplete pallet and loose balances |
| `lib/domain/entities/bootstrap_response.dart` | Bootstrap response entity with per-line state |
| `lib/data/models/session_table_row_model.dart` | JSON deserialization for session table rows |
| `lib/data/models/line_handover_info_model.dart` | JSON deserialization for line handover info |
| `lib/data/models/bootstrap_response_model.dart` | JSON deserialization for bootstrap response |
| `lib/presentation/widgets/line_auth_overlay.dart` | Per-line PIN authorization overlay UI |
| `lib/presentation/widgets/session_table_widget.dart` | Session table UI replacing old summary card |
| `lib/presentation/widgets/product_switch_dialog.dart` | Product-switch loose-balance confirmation dialog |
| `lib/presentation/widgets/line_handover_card.dart` | Per-line pending handover display and resolve UI |

## Modified Files

| File | Changes |
|------|---------|
| `lib/domain/repositories/palletizing_repository.dart` | Added 8 new line-scoped methods: `bootstrap`, `authorizeLine`, `getLineState`, `createLinePallet`, `logLinePrintAttempt`, `switchProduct`, `createLineHandover`, `getLineHandover`, `resolveLineHandover` |
| `lib/data/repositories/palletizing_repository_impl.dart` | Implemented all new endpoints using `ApiClient` |
| `lib/presentation/providers/palletizing_provider.dart` | Complete rewrite: per-line auth/creating/error state, bootstrap-based init, line-scoped create/print/handover, removed `_selectedOperators` and old `createPallet` signature |
| `lib/core/exceptions/api_exception.dart` | Added 11 new PIN/line error code → Arabic message mappings |
| `lib/presentation/widgets/production_line_section.dart` | Stack with `LineAuthOverlay`, read-only operator card, `SessionTableWidget`, `LineHandoverCard`, product-switch flow, per-line create button guard, line-scoped create dialog |
| `lib/presentation/widgets/create_pallet_dialog.dart` | Removed operator dropdown, `operators` param, `initialOperator` param; only product + quantity remain |
| `lib/presentation/widgets/pallet_success_dialog.dart` | Added `lineNumber` param, updated `logPrintAttempt` call to pass `lineNumber` |
| `lib/presentation/screens/palletizing_screen.dart` | `loadInitialData()` → `loadBootstrap()`, `getSelectedOperator()` → `getAuthorizedOperator()` |
| `lib/main.dart` | `loadInitialData()` → `loadBootstrap()` in `_loadOperators` |

## Preserved Files (Not Deleted)

| File | Reason |
|------|--------|
| `lib/presentation/widgets/summary_card.dart` | No longer used in palletizing flow but kept to avoid breaking other potential consumers |
| `lib/presentation/widgets/shift_handover_dialog.dart` | Still used for global shift handover (adjacent flow) |
| `lib/presentation/widgets/pending_handover_dialog.dart` | Still used for global pending handover blocking in `AuthWrapper` |

---

## New API Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/palletizing/bootstrap` | Initial load: lines, auth, sessionTable, product types |
| POST | `/palletizing/lines/{lineId}/authorize` | PIN authorization per line |
| GET | `/palletizing/lines/{lineId}/state` | Refresh single line state |
| POST | `/palletizing/lines/{lineId}/pallets` | Create pallet (line-scoped, no operatorId) |
| POST | `/palletizing/lines/{lineId}/pallets/{palletId}/print-attempts` | Log print attempt (line-scoped) |
| POST | `/palletizing/lines/{lineId}/switch-product` | Product switch with loose balance |
| POST | `/palletizing/lines/{lineId}/handover` | Create line handover |
| GET | `/palletizing/lines/{lineId}/handover` | Get pending line handover |
| POST | `/palletizing/lines/{lineId}/handover/{id}/resolve` | Resolve line handover |

## Retired API Endpoints

| Method | Path | Replacement |
|--------|------|-------------|
| POST | `/palletizing/pallets` | `POST /palletizing/lines/{lineId}/pallets` |
| POST | `/palletizing/pallets/{id}/print-attempts` | Line-scoped version |
| GET | `/palletizing/lines/{lineId}/summary` | Replaced by `sessionTable` in bootstrap/line-state |

---

## Architecture Preserved

- **Provider/ChangeNotifier** pattern maintained throughout
- **Clean Architecture** layers (domain entities → data models → repository → provider → widgets) preserved
- **Existing UI style** (Google Fonts Cairo, responsive helpers, line color theming) maintained
- **DI via `ServiceLocator`** — no changes needed; new methods flow through existing `PalletizingRepository` interface

## Key Design Decisions

1. **Per-line `isLineCreating(lineNumber)`** — one line's create operation doesn't block the other line's button
2. **Bootstrap-first** — single call hydrates everything, then line-specific refreshes after commands
3. **`LineAuthOverlay` as Stack child** — not a global dialog; each line is independently blocked/unblocked
4. **Session table from backend** — not derived from UI-selected product; backend is sole source of truth
5. **Product switch dialog** — only shown when changing from one product to another (not on first selection)
6. **`revokeLineAuthorization()`** — cleanly resets auth state to trigger PIN overlay for operator change
