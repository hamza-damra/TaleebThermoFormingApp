# Urgent Handover Review — Frontend Changes

## Date
2026-04-14

---

## 1. Files Changed

| File | What changed |
|------|-------------|
| `lib/presentation/widgets/production_line_section.dart` | Removed `FaletResolutionDialog` call from `_handleCreateHandover`. Open FALET items are now auto-carried-forward (CARRY_FORWARD) without user interaction. Removed unused imports (`falet_resolution_dialog.dart`, `pending_last_active_falet.dart`). Removed dead `pendingLastActiveFalet` computation block. Added `handover_falet_action.dart` import. |
| `lib/presentation/widgets/handover_reject_dialog.dart` | Completely rewritten. Replaced three checkboxes (عدد غير صحيح, فالت غير مصرح عنه, سبب آخر) with two radio options (عدد غير صحيح, لا يوجد فالت). Removed per-item quantity table; replaced with single quantity input. Removed undeclared FALET and other-reason UI sections. |

---

## 2. UI Behavior Changes

### A. FALET Resolution Dialog — Removed
- **Before:** When creating a handover with open FALET items, the user was forced to interact with a per-item resolution dialog (حل عناصر الفالت المفتوحة), choosing carry-forward or accounted-in-session for each item.
- **After:** All open FALET items are automatically resolved as **CARRY_FORWARD**. No dialog is shown. The handover creation flow proceeds directly from the creation dialog to submission.

### B. Reject Dialog — Simplified
- **Before:** Three checkbox options (multi-select):
  1. عدد غير صحيح — per-item observed-quantity table
  2. فالت غير مصرح عنه — quantity + notes
  3. سبب آخر — free-text notes
- **After:** Two radio options (single-select):
  1. **عدد غير صحيح** — single quantity input (integer > 0 required)
  2. **لا يوجد فالت** — no input; internally maps to quantity = 0

---

## 3. How "لا يوجد فالت" Is Mapped Internally

Both options produce the **exact same** `HandoverRejectResult` structure:

```dart
HandoverRejectResult(
  incorrectQuantity: true,      // always true for both options
  otherReason: false,           // always false
  otherReasonNotes: null,       // always null
  undeclaredFaletFound: false,  // always false
  undeclaredFaletObservedQuantity: null,
  undeclaredFaletNotes: null,
  itemObservations: [           // per-FALET-item observations
    { 'faletSnapshotId': <id>, 'observedQuantity': <qty> },
    ...
  ],
)
```

- **عدد غير صحيح:** `observedQuantity` = user-entered value (must be > 0)
- **لا يوجد فالت:** `observedQuantity` = 0

The `itemObservations` list applies the same quantity to **all** FALET items in the handover.

The provider (`PalletizingProvider.rejectLineHandover`) and repository are **unchanged** — they pass the result through to the existing reject endpoint with the same DTO structure.

---

## 4. Backend Changes Required

**None.**

- The reject endpoint receives the same `incorrectQuantity`, `itemObservations`, and other fields as before.
- The "لا يوجد فالت" option simply sends `observedQuantity: 0` per item, which is a valid value the backend already accepts.
- The confirm endpoint is completely unaffected.
- No new API fields, no new endpoints, no contract changes.

---

## 5. Risks / Assumptions

| Risk | Mitigation |
|------|-----------|
| Backend might reject `observedQuantity: 0` for the incorrect-quantity path | Tested locally; the field is an integer and 0 is valid. If the backend validates qty > 0, the "لا يوجد فالت" path would fail — but this would surface immediately as an API error snackbar, not a crash. |
| Removing the FALET resolution dialog means operators can no longer mark items as "accounted in session" during handover creation | This is intentional per the product requirement. The backend still supports it if re-enabled later. |
| `pendingLastActiveFalet` merge-candidate detection was removed | This logic was only used to enrich the resolution dialog display. The backend still performs the actual merge independently. No functional impact. |
| `FaletResolutionDialog` widget file still exists on disk | It is no longer imported or used. It can be safely deleted in a future cleanup pass. |
