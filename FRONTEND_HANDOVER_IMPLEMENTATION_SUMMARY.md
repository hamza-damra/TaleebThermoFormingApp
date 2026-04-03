# Frontend Handover Implementation Summary

## Overview

The per-line handover (تسليم مناوبة) flow is fully implemented in the Flutter mobile app, aligned with the backend contract specified in `docs/FRONTEND_HANDOVER_REQUIRED_FLOW.md`.

---

## Screens Created / Modified

### Modified

| File | Changes |
|------|---------|
| `lib/presentation/providers/palletizing_provider.dart` | Auto-fetches full handover details via `GET /lines/{lineId}/handover/pending` when `lineUiMode` transitions to `PENDING_HANDOVER_REVIEW`. This ensures the review card displays complete `incompletePallet` and `looseBalances` data instead of just the summary. |
| `lib/presentation/widgets/production_line_section.dart` | Added dedicated `_buildHandoverReviewLayout` for `PENDING_HANDOVER_REVIEW` mode. Normal production UI (form card, product picker, create button, session table) is hidden; only the handover detail card with confirm/reject buttons is shown. In `AUTHORIZED` mode, the pending handover card no longer shows resolve actions (those are reserved for the dedicated review screen). |

### Existing (no changes needed)

| File | Purpose |
|------|---------|
| `lib/presentation/widgets/handover_creation_dialog.dart` | 2-step handover creation dialog: Step 0 asks two questions (مشاتيح ناقصة / فالت), Step 1 shows the appropriate form (4 cases: clean, incomplete pallet, loose balances, both). |
| `lib/presentation/widgets/line_auth_overlay.dart` | PIN entry overlay. In `PENDING_HANDOVER_NEEDS_INCOMING` mode, shows pending handover summary card above the PIN field with "في انتظار المشغل القادم" title. |
| `lib/presentation/widgets/line_handover_card.dart` | Handover detail card showing outgoing operator info, incomplete pallet details, loose balance items table, notes, and optional confirm/reject action buttons. |
| `lib/data/repositories/palletizing_repository_impl.dart` | All handover API calls (`createLineHandover`, `getLineHandover`, `confirmLineHandover`, `rejectLineHandover`) with proper JSON bodies. |
| `lib/data/models/line_handover_info_model.dart` | JSON parsing for `LineHandoverResponse`, `IncompletePalletInfo`, and `LooseBalanceItem`. |
| `lib/domain/entities/line_handover_info.dart` | Domain entities for handover data. |

---

## What Was Removed

- **No "تغيير المشغل" / "change operator" button** exists in the UI. The operator leaves the line only through the handover flow. The `DELETE /lines/{lineId}/authorization` endpoint is not exposed in the mobile app.

---

## UI Mode Routing (lineUiMode)

| `lineUiMode` | Screen | Key Components |
|---|---|---|
| `NEEDS_AUTHORIZATION` | PIN entry overlay | `LineAuthOverlay` |
| `AUTHORIZED` | Normal production | Operator card, product picker, session table, "تسليم مناوبة" button, "إنشاء مشتاح جديد" button |
| `PENDING_HANDOVER_NEEDS_INCOMING` | Handover summary + PIN entry | `LineAuthOverlay` with pending handover summary card |
| `PENDING_HANDOVER_REVIEW` | Dedicated review screen | `_buildHandoverReviewLayout` with `LineHandoverCard` (confirm/reject buttons) |

---

## Dialog Flow

1. Operator presses **"تسليم مناوبة"** (visible when `canInitiateHandover: true`)
2. **Step 0**: Two toggle questions — "هل يوجد مشاتيح ناقصة؟" and "هل يوجد فالت؟"
3. **Step 1**: Form based on selected case:
   - **Clean**: Optional notes only
   - **Incomplete pallet**: Product type picker + quantity + optional scanned value (12 digits) + notes
   - **Loose balances**: Info banner (auto-included from session) + notes
   - **Both**: Pallet form + loose balance info + notes
4. Submit → `POST /lines/{lineId}/handover` → re-fetch line state → line enters `PENDING_HANDOVER_NEEDS_INCOMING`
5. Incoming operator enters PIN → line enters `PENDING_HANDOVER_REVIEW` → full handover details fetched
6. Incoming confirms (`تأكيد الاستلام`) or rejects (`رفض التسليم` with optional notes)
7. Line returns to `AUTHORIZED` mode

---

## Action Flag Usage

| Flag | Controls |
|------|----------|
| `canInitiateHandover` | "تسليم مناوبة" button visibility |
| `canConfirmHandover` | "تأكيد الاستلام" button in review card |
| `canRejectHandover` | "رفض التسليم" button in review card |

---

## Error Handling

Backend error codes are displayed as Arabic messages via `ApiException.displayMessage`:

| Error Code | Arabic Message |
|------------|---------------|
| `PENDING_LINE_HANDOVER_EXISTS` | يوجد تسليم معلق بالفعل لهذا الخط |
| `LINE_HANDOVER_NOT_FOUND` | لم يتم العثور على التسليم |
| `LINE_HANDOVER_ALREADY_RESOLVED` | تم معالجة هذا التسليم مسبقاً |
| `LINE_NOT_AUTHORIZED` | لا يوجد مشغل مصرح على هذا الخط |
| `VALIDATION_ERROR` | بيانات التسليم غير صحيحة |

---

## Follow-up Items

- Dispute resolution is admin-only (web portal) — not in the mobile app
- Scanned value validation (12 numeric digits) is enforced client-side in the creation dialog
