# FALET Reject Handover — Frontend Fix Handoff

> **Date:** 2026-04-28
> **Backend Branch:** `hotfix/production-bug-20260428`
> **Frontend Task:** Update Flutter app to comply with strict validation
> **Status:** Backend response now exposes `faletSnapshotId` — Flutter must switch to it

---

## 0. UPDATE — Backend Response Contract Gap Closed

After the strict validation rolled out, the Flutter logs showed `faletItems[]` only contained:
- `faletId`
- `lastActiveProduct`
- `observedQuantity`
- `productTypeId`
- `productTypeName`
- `quantity`

There was **no `faletSnapshotId`** on the response. Flutter was sending `faletId` (e.g. `62`) as `faletSnapshotId`, and the backend correctly rejected it because `faletId` is `FaletCurrentState.id`, not `LineHandoverFaletSnapshot.id`.

**Backend fix shipped on this branch:** `LineHandoverResponse.FaletSnapshotItem` now includes `faletSnapshotId` as an **additive** field. `faletId` is preserved unchanged for backward compatibility.

**New response shape per FALET item:**
```json
{
  "faletSnapshotId": 47,        // ← NEW. LineHandoverFaletSnapshot.id — USE THIS FOR REJECT
  "faletId": 62,                // ← UNCHANGED. FaletCurrentState.id — DO NOT use for reject
  "productTypeId": 5,
  "productTypeName": "Red 20kg",
  "quantity": 10,               // sender declared
  "observedQuantity": null,     // null until receiver records observations
  "lastActiveProduct": true
}
```

**Required Flutter change:**
- In the handover model parser, **add `faletSnapshotId`** alongside `faletId`.
- When building `itemObservations` for the reject request, use **`item.faletSnapshotId`**, not `item.faletId`.
- Keep parsing `faletId` (it is still useful for the FALET screen / reconciliation views) but **never** copy it into a reject `itemObservations[].faletSnapshotId`.

---

## 1. Executive Summary

**Backend is now strict by design.** After the FALET full fix (Phases 1–8), the handover rejection endpoint performs **full validation before any mutation**. This prevents the old production bug where a handover could become `REJECTED` without creating a `FaletDispute`, leaving the manager with no resolution path.

**Current error observed:**
```
Observation references unknown snapshot id 62 (not part of handover 82).
```

**Root cause:** The previous response payload omitted `faletSnapshotId`, so the Flutter app had no way to obtain the correct ID and was substituting `faletId` (`62`). The backend response is now fixed (see Section 0). Flutter must read the new field from the response and use it when building reject observations.

**This is correct backend behavior.** It means the Flutter app sent a reject-handover request, but the request contained an ID (`62`) that is not a `LineHandoverFaletSnapshot.id` for handover `82`.

**Do not ask the backend to weaken validation.** Fix the Flutter app to read `faletSnapshotId` from the new response field and send it in `itemObservations`.

**Business rule clarification:**
A rejected handover does **NOT** mean the incoming operator failed to receive the line. The incoming operator **receives and continues the line immediately**. The system temporarily trusts the incoming operator's observed FALET quantity as the operational quantity until the manager decides in `/web/admin/falet-disputes`. After the manager decides `SENDER_RIGHT` or `RECEIVER_RIGHT`, the backend corrects production attribution and accounting.

---

## 2. Runtime Error Observed

**Exact error from backend logs:**
```
BusinessException: Observation references unknown snapshot id 62 (not part of handover 82).
```

**What this means in plain language:**

1. The Flutter app attempted to reject handover `#82`.
2. The app sent an observation with `faletSnapshotId = 62`.
3. Handover `#82` has its own set of valid FALET snapshots (stored in `line_handover_falet_snapshots`).
4. Snapshot `62` is not one of them.
5. The backend validation intercepted this mismatch **before** changing the `LineHandover` status.
6. **No partial mutation happened.** The handover remains `PENDING` and can be retried.
7. The backend returned a 400 error with error code `HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH`.

**Why this validation exists:**
The old production bug allowed observations with mismatched snapshot IDs to silently pass. The system would then create a dispute, but the observation-to-snapshot mapping was corrupted, causing incorrect dispute items and operational quantity calculations.

---

## 3. Correct Backend Contract

### Endpoint

```
POST /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}/reject
```

**Route:** Defined in `PalletizingLineController` (line ~165).

**Request DTO:** `LineHandoverRejectRequest`

### Request DTO Fields

```java
public class LineHandoverRejectRequest {
    private Boolean incorrectQuantity;           // true if quantity mismatch
    private Boolean otherReason;                 // true for additional comment
    private String otherReasonNotes;             // required if otherReason=true
    private Boolean undeclaredFaletFound;        // true if unreported FALET found
    private Integer undeclaredFaletObservedQuantity; // observed qty of undeclared FALET
    private String undeclaredFaletNotes;         // optional note
    private List<LineHandoverItemObservation> itemObservations; // per-snapshot observations

    // LineHandoverItemObservation
    public class LineHandoverItemObservation {
        private Long faletSnapshotId;            // snapshot ID from current handover
        private Integer observedQuantity;        // actual observed qty (0 = "no FALET")
    }
}
```

### Validation Rules (Enforced by Backend)

1. **Snapshot ID validity:**
   - Each `itemObservation.faletSnapshotId` must exist in the current handover's `line_handover_falet_snapshots`.
   - Unknown snapshot IDs are rejected with `HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH`.

2. **Snapshot ID uniqueness:**
   - No duplicate snapshot IDs in `itemObservations[]`.
   - Duplicates are rejected with `HANDOVER_OBSERVATION_DUPLICATE`.

3. **Snapshot ID completeness (if incorrectQuantity=true):**
   - Every snapshot in the current handover must have exactly one matching observation.
   - Missing observations are rejected with `HANDOVER_OBSERVATION_MISSING`.

4. **Observed quantity validity:**
   - `observedQuantity` must not be `null`.
   - `observedQuantity` must be `>= 0`.
   - Invalid quantities are rejected with `HANDOVER_OBSERVED_QUANTITY_INVALID`.

5. **Rejection reason requirements:**
   - At least one flag must be set: `incorrectQuantity`, `undeclaredFaletFound`, or `otherReason`.
   - `otherReason` alone is **no longer allowed** (new validation).
   - If `otherReason=true` without `incorrectQuantity` or `undeclaredFaletFound`, the request is rejected with `HANDOVER_REJECTION_REASON_INVALID`.
   - `otherReason` is **additive only** — it's an additional note, not a standalone reason.

6. **Note requirements:**
   - If `otherReason=true`, `otherReasonNotes` is required (non-empty string).
   - If `undeclaredFaletFound=true`, `undeclaredFaletObservedQuantity` must be `> 0`.

7. **Quantity mismatch requirement:**
   - If `incorrectQuantity=true` and all observed quantities equal sender declared quantities, the request is rejected with `HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH`.
   - (This prevents confusing rejections where there's no actual mismatch to resolve.)

8. **FALET state availability:**
   - All FALETs referenced must still be in `OPEN` state (not already `RESOLVED`).
   - FALETs in other states are rejected with `FALET_STATE_NOT_AVAILABLE_FOR_REJECTION`.

---

## 4. Required Flutter Behavior

### A. When Opening the Handover Review Screen

- Load the current pending handover from the backend.
  - Endpoint: `GET /api/v1/palletizing-line/lines/{lineId}/handover/{handoverId}` (or equivalent).
  - Response includes: `id` (handover id), `status`, and `faletItems[]` with — most importantly — **`faletSnapshotId`**, `faletId`, `productTypeId`, `productTypeName`, `quantity` (sender declared), `observedQuantity`, `lastActiveProduct`.
- Store the **handover `id`** in local state.
- Store the **list of valid `faletSnapshotId` values** from `faletItems[]` in a set (for quick lookup).
- **Do not reuse snapshot IDs from previous handovers.**
- **Do not use `faletId` as `faletSnapshotId`.** They are different entities (`faletId` = `FaletCurrentState.id`, `faletSnapshotId` = `LineHandoverFaletSnapshot.id`).

**Update the Dart model first.** Add a new field to your handover FALET item class:

```dart
class HandoverFaletItem {
  final int faletSnapshotId;  // NEW — required for reject API
  final int? faletId;         // existing — keep, but DO NOT use for reject
  final int productTypeId;
  final String productTypeName;
  final int quantity;          // sender declared
  final int? observedQuantity;
  final bool lastActiveProduct;

  HandoverFaletItem.fromJson(Map<String, dynamic> json)
      : faletSnapshotId = json['faletSnapshotId'] as int,  // NEW
        faletId = json['faletId'] as int?,
        productTypeId = json['productTypeId'] as int,
        productTypeName = json['productTypeName'] as String,
        quantity = json['quantity'] as int,
        observedQuantity = json['observedQuantity'] as int?,
        lastActiveProduct = json['lastActiveProduct'] as bool? ?? false;
}
```

**Code pattern:**
```dart
// CORRECT
final handover = await fetchPendingHandover(lineId, handoverId);
final validSnapshotIds = handover.faletItems.map((s) => s.faletSnapshotId).toSet();
// Store for validation

// WRONG (this was the bug that caused the production error)
final snapshotIds = handover.faletItems.map((s) => s.faletId).toSet(); // BAD: faletId is FaletCurrentState.id
```

### B. Before Submitting Reject

Validate locally that the request is correct before sending to the backend:

1. **Snapshot ID validation:**
   - For each `itemObservation.faletSnapshotId`, verify it exists in the current handover's valid snapshot ID set.
   - If any snapshot ID is unknown, show a friendly error: "بيانات التسليم قديمة، يرجى تحديث الصفحة والمحاولة مرة أخرى." (Handover data is outdated; please refresh and try again.)

2. **Duplicate detection:**
   - Ensure no snapshot ID appears twice in `itemObservations[]`.
   - If duplicates exist, show: "تم إرسال نفس بند الفالت أكثر من مرة." (The same FALET item was submitted multiple times.)

3. **Observed quantity validation:**
   - For each observation, ensure `observedQuantity` is not `null`.
   - Ensure `observedQuantity >= 0`.
   - Show: "الكمية المرصودة غير صحيحة." (Observed quantity is invalid.)

4. **Completeness for incorrectQuantity:**
   - If `incorrectQuantity=true`, ensure every snapshot in the current handover has exactly one observation.
   - Show: "يجب تحديد الكمية المرصودة لكل بند فالت." (You must specify the observed quantity for every FALET item.)

5. **Reason validation:**
   - Ensure at least one flag is set: `incorrectQuantity`, `undeclaredFaletFound`, or (optionally) `otherReason`.
   - Ensure `otherReason=true` is **not** submitted without at least one of the other reasons.
   - Show: "سبب الرفض غير كافٍ. يجب اختيار مشكلة كمية أو فالت غير مصرح عنه." (Rejection reason is insufficient. You must select a quantity issue or undeclared FALET.)

### C. For "عدد غير صحيح" (Incorrect Quantity)

- The user indicates the sender declared a quantity, but the receiver observed a different amount.
- The app must request the **actual observed quantity** from the user.
- Send that value as `observedQuantity`.
- **Important:** If the observed quantity **equals** the sender declared quantity, do **not** submit as `incorrectQuantity`. The backend will reject this with `HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH`.
- Show a local validation message: "الكمية المرصودة تطابق الكمية المصرح عنها. لا يمكن الرفض." (Observed quantity matches declared quantity. Rejection not needed.)

### D. For "لا يوجد فالت" (No FALET Found)

- This means the receiver looked for the FALET but did not find it.
- In backend terms: **`observedQuantity = 0`**.
- **Do not send `null`.** Do not omit the item observation.
- Send `itemObservations` with the same current `faletSnapshotId` and **`observedQuantity = 0`**.
- This must create a `FaletDispute` so the manager can decide later whether the sender's declaration was correct or whether the receiver is correct that no FALET was found.
- Set `incorrectQuantity=true` to trigger observation collection.

**Code pattern:**
```dart
// CORRECT: "No FALET found" = observed quantity of 0
observations = [
  LineHandoverItemObservation(
    faletSnapshotId: snapshotId,
    observedQuantity: 0 // Not null, explicitly zero
  )
];
incorrectQuantity = true;
```

### E. For "فالت غير مصرح عنه" (Undeclared FALET Found)

- The receiver found FALET items that the sender did not declare (or declared fewer).
- Set `undeclaredFaletFound = true`.
- Set `undeclaredFaletObservedQuantity` to the **actual count** of undeclared items found.
- Provide an optional note in `undeclaredFaletNotes`.
- **Do not** send `itemObservations` for undeclared FALETs (they are not part of the snapshot list).
- The backend will create a separate dispute item for the undeclared quantity.

**Code pattern:**
```dart
// CORRECT: Undeclared FALET
undeclaredFaletFound = true;
undeclaredFaletObservedQuantity = 4;
undeclaredFaletNotes = "تم العثور على 4 بنود فالت إضافية في الكونتينر";
// itemObservations is for declared snapshots only, not used here
```

### F. For "سبب آخر" (Other Reason)

- `otherReason` is **only an additional note**, not a standalone rejection reason.
- It cannot be submitted alone.
- It must be accompanied by either `incorrectQuantity=true` or `undeclaredFaletFound=true`.
- Require `otherReasonNotes` to be filled (non-empty).
- **If the user has only a comment and no quantity/FALET issue**, the app should **not** allow the rejection.
- Show a message: "الملاحظات الإضافية وحدها غير كافية للرفض. يجب تحديد مشكلة كمية أو فالت." (Additional notes alone are not enough to reject. You must select a quantity issue or undeclared FALET.)

---

## 5. Common Bug Causes To Investigate In Flutter

Ask the frontend team to inspect the codebase for these patterns:

1. **Snapshot ID vs. FALET ID confusion:**
   - Does the reject dialog use `faletId` instead of `faletSnapshotId`?
   - Check: Are snapshot IDs being loaded from the handover detail, or from the FALET screen endpoint?

2. **Stale pending handover:**
   - Does the app cache the `pendingHandover` from bootstrap and not refresh it after incoming operator authorization?
   - Does a line state SSE/update event invalidate the cached handover?

3. **Old LineHandoverInfo in state:**
   - Does the app keep the old `LineHandoverCard` data after line state changes?
   - Does the app re-open a reject dialog for a handover that was already rejected/accepted?

4. **Observation reuse from previous handover:**
   - Does the app reuse `itemObservations` from a previous handover without re-validating snapshot IDs?
   - Check: Are observations cached at the line level, not the handover level?

5. **Observations from FALET screen instead of handover snapshots:**
   - Does the app build observations from the open FALET screen items instead of from the handover's snapshot list?
   - These are different data sources and will have different IDs.

6. **Line state update without dialog invalidation:**
   - Does the app update line state (via SSE or polling) but not update the reject dialog model?
   - If handover changes, the dialog should close or reload.

7. **Stale LineHandoverCard props:**
   - Does the app open the reject dialog from `LineHandoverCard` props that were set long ago?
   - Is the dialog's `handover` object a Dart `late` field that was assigned once and never refreshed?

8. **Multiple provider maps keyed only by lineId:**
   - Does the state management have `providers[lineId] = HandoverData` instead of `providers[(lineId, handoverId)] = HandoverData`?
   - Keying only by `lineId` can cause the same data to be reused across different handovers.

9. **No cleanup on reject failure:**
   - If the reject API call fails, does the app clear the pending handover state?
   - Or does it keep the old state, so a retry uses stale data?

10. **"لا يوجد فالت" submits null instead of zero:**
    - Does the code have `if (noFaletFound) { observation.observedQuantity = null; }`?
    - Should be: `observation.observedQuantity = 0;`

---

## 6. Correct Payload Examples

### Example 1: Incorrect Quantity (Sender 10, Receiver Observed 5)

**Scenario:** Sender declared 10 units of FALET, but receiver counted only 5.

**Correct payload:**
```json
{
  "incorrectQuantity": true,
  "otherReason": false,
  "undeclaredFaletFound": false,
  "itemObservations": [
    {
      "faletSnapshotId": 123,
      "observedQuantity": 5
    }
  ]
}
```

**Backend result:** `REJECTED` status, `FaletDispute` created with operational quantity = 5, manager can review and decide.

---

### Example 2: No FALET Found (لا يوجد فالت)

**Scenario:** Sender declared 10 units, but receiver says no FALET was found.

**Correct payload:**
```json
{
  "incorrectQuantity": true,
  "otherReason": false,
  "undeclaredFaletFound": false,
  "itemObservations": [
    {
      "faletSnapshotId": 123,
      "observedQuantity": 0
    }
  ]
}
```

**Backend result:** `REJECTED` status, `FaletDispute` created with operational quantity = 0, manager can review and decide.

---

### Example 3: Undeclared FALET Found (فالت غير مصرح عنه)

**Scenario:** Sender declared nothing (or only 3 units), but receiver found 4 undeclared units in the line.

**Correct payload:**
```json
{
  "incorrectQuantity": false,
  "otherReason": false,
  "undeclaredFaletFound": true,
  "undeclaredFaletObservedQuantity": 4,
  "undeclaredFaletNotes": "تم العثور على فالت غير مصرح عنه في الكونتينر"
}
```

**Backend result:** `REJECTED` status, `FaletDispute` created with undeclared item, manager can review and decide.

---

### Example 4: Incorrect Quantity + Additional Note

**Scenario:** Sender declared 10, receiver observed 5, and also wants to add a note explaining why.

**Correct payload:**
```json
{
  "incorrectQuantity": true,
  "otherReason": true,
  "otherReasonNotes": "الكمية كانت في صندوق مختلف، لم أرها في البداية",
  "undeclaredFaletFound": false,
  "itemObservations": [
    {
      "faletSnapshotId": 123,
      "observedQuantity": 5
    }
  ]
}
```

**Backend result:** `REJECTED` status, `FaletDispute` created, note stored in dispute for manager context.

---

### Example 5: Multiple FALET Snapshots

**Scenario:** Handover has 3 FALET items. Receiver observed different quantities for each.

**Correct payload:**
```json
{
  "incorrectQuantity": true,
  "otherReason": false,
  "undeclaredFaletFound": false,
  "itemObservations": [
    {
      "faletSnapshotId": 100,
      "observedQuantity": 8
    },
    {
      "faletSnapshotId": 101,
      "observedQuantity": 0
    },
    {
      "faletSnapshotId": 102,
      "observedQuantity": 12
    }
  ]
}
```

**Backend result:** `REJECTED` status, `FaletDispute` created with 3 dispute items (one per snapshot).

---

### Invalid Example 1: Other Reason Only (REJECTED)

**Scenario:** User has only a comment, no actual quantity or FALET issue.

**Wrong payload:**
```json
{
  "incorrectQuantity": false,
  "otherReason": true,
  "otherReasonNotes": "الخط لم يكن جاهزًا في الوقت المتوقع",
  "undeclaredFaletFound": false
}
```

**Backend result:** `400 HANDOVER_REJECTION_REASON_INVALID`
**Message:** "سبب الرفض غير كافٍ. يجب اختيار مشكلة كمية أو فالت غير مصرح عنه."

**Why:** `otherReason` alone is not a valid rejection reason. The backend requires a FALET or quantity issue to create a dispute.

---

### Invalid Example 2: Wrong Snapshot ID (REJECTED)

**Scenario:** App sends an observation for snapshot `62`, but the current handover doesn't have snapshot `62`.

**Wrong payload:**
```json
{
  "incorrectQuantity": true,
  "itemObservations": [
    {
      "faletSnapshotId": 62,
      "observedQuantity": 0
    }
  ]
}
```

**Backend result:** `400 HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH`
**Message:** "Observation references unknown snapshot id 62 (not part of handover 82)."

**Why:** Snapshot `62` does not belong to the current handover. The app either cached an old handover, or is using the wrong snapshot ID source.

---

### Invalid Example 3: Duplicate Snapshot IDs (REJECTED)

**Scenario:** App sends the same snapshot ID twice in observations.

**Wrong payload:**
```json
{
  "incorrectQuantity": true,
  "itemObservations": [
    {
      "faletSnapshotId": 100,
      "observedQuantity": 5
    },
    {
      "faletSnapshotId": 100,
      "observedQuantity": 3
    }
  ]
}
```

**Backend result:** `400 HANDOVER_OBSERVATION_DUPLICATE`
**Message:** "Observation for snapshot id 100 appears more than once."

**Why:** Each snapshot can only have one observation.

---

### Invalid Example 4: Missing Observation (REJECTED)

**Scenario:** Handover has 3 snapshots (IDs: 100, 101, 102), but app sends observations for only 2.

**Wrong payload:**
```json
{
  "incorrectQuantity": true,
  "itemObservations": [
    {
      "faletSnapshotId": 100,
      "observedQuantity": 5
    },
    {
      "faletSnapshotId": 101,
      "observedQuantity": 3
    }
  ]
}
```

**Backend result:** `400 HANDOVER_OBSERVATION_MISSING`
**Message:** "Observation missing for snapshot id 102."

**Why:** When marking as `incorrectQuantity`, every snapshot must have an observation.

---

### Invalid Example 5: Null Observed Quantity (REJECTED)

**Scenario:** App sends `observedQuantity: null` instead of a number.

**Wrong payload:**
```json
{
  "incorrectQuantity": true,
  "itemObservations": [
    {
      "faletSnapshotId": 123,
      "observedQuantity": null
    }
  ]
}
```

**Backend result:** `400 HANDOVER_OBSERVED_QUANTITY_INVALID`
**Message:** "Observed quantity cannot be null."

**Why:** The backend requires a concrete number (including 0 for "no FALET found").

---

### Invalid Example 6: Mismatch Not Detected (REJECTED)

**Scenario:** Sender declared 10, receiver observed 10 (same), but app submits as `incorrectQuantity`.

**Wrong payload:**
```json
{
  "incorrectQuantity": true,
  "itemObservations": [
    {
      "faletSnapshotId": 123,
      "observedQuantity": 10
    }
  ]
}
```

**Backend result:** `400 HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH`
**Message:** "Cannot reject as incorrect quantity when observed quantity matches declared quantity."

**Why:** If there's no actual mismatch, there's no dispute to create.

---

## 7. Error Codes The Flutter App Should Handle

The backend now returns these error codes (in the `error.code` field of the `ApiResponse`). Add localized error handling for each:

| Error Code | HTTP | Meaning | Recommended Arabic UI Message | Recommended English UI Message |
|---|---|---|---|---|
| `HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH` | 400 | Snapshot ID not part of current handover | بيانات التسليم قديمة، يرجى تحديث الصفحة والمحاولة مرة أخرى. | Handover data is outdated. Please refresh and try again. |
| `HANDOVER_OBSERVATION_DUPLICATE` | 400 | Snapshot ID submitted multiple times | تم إرسال نفس بند الفالت أكثر من مرة. | The same FALET item was submitted multiple times. |
| `HANDOVER_OBSERVATION_MISSING` | 400 | Snapshot has no observation when incorrectQuantity=true | يجب تحديد الكمية المرصودة لكل بند فالت. | You must specify observed quantity for every FALET item. |
| `HANDOVER_OBSERVED_QUANTITY_INVALID` | 400 | observedQuantity is null or < 0 | الكمية المرصودة غير صحيحة. | Observed quantity is invalid. |
| `HANDOVER_INCORRECT_QUANTITY_NO_MISMATCH` | 400 | All quantities match; no mismatch to reject | الكمية المرصودة تطابق الكمية المصرح عنها. لا يمكن الرفض. | Observed quantity matches declared. Rejection not needed. |
| `HANDOVER_REJECTION_REASON_INVALID` | 400 | otherReason only, without quantity/FALET issue | سبب الرفض غير كافٍ. يجب اختيار مشكلة كمية أو فالت. | Rejection reason is insufficient. Select a quantity or FALET issue. |
| `FALET_STATE_NOT_AVAILABLE_FOR_REJECTION` | 400 | FALET state changed (no longer OPEN) | حالة الفالت تغيرت، يرجى تحديث بيانات الخط. | FALET state changed. Please refresh line data. |

**UI implementation pattern:**
```dart
try {
  await rejectHandover(lineId, handoverId, request);
  showSnackBar("تم الرفض بنجاح.");
} on BusinessException catch (e) {
  switch (e.errorCode) {
    case 'HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH':
      showError("بيانات التسليم قديمة، يرجى تحديث الصفحة والمحاولة مرة أخرى.");
      // Optionally: refresh handover and close dialog
      break;
    case 'HANDOVER_OBSERVATION_MISSING':
      showError("يجب تحديد الكمية المرصودة لكل بند فالت.");
      break;
    // ... other codes
    default:
      showError(e.message ?? "حدث خطأ غير متوقع.");
  }
}
```

---

## 8. Required Frontend State Strategy

Restructure state management to ensure snapshot IDs are always fresh and correct:

### 1. Key By Handover, Not Just Line

**WRONG:**
```dart
final pendingHandoverProvider = Provider((ref) {
  final lineId = ref.watch(selectedLineIdProvider);
  return fetchPendingHandover(lineId);
});
// No way to distinguish between multiple handovers on the same line
```

**CORRECT:**
```dart
final pendingHandoverProvider = FutureProvider.family<LineHandoverDetail, (int, int)>((ref, params) {
  final (lineId, handoverId) = params;
  return fetchPendingHandover(lineId, handoverId);
});
// Each (lineId, handoverId) pair has its own cached state
```

### 2. Always Refresh After Incoming Authorization

When the incoming operator authorizes (after scanning their PIN), immediately refetch the pending handover:

```dart
final onIncomingOperatorAuthorized = (lineId, handoverId) async {
  await ref.refresh(pendingHandoverProvider((lineId, handoverId)));
  // Dialog now has fresh snapshot IDs
};
```

### 3. Pass Exact Handover Detail to Reject Dialog

Do not pass props from long-lived state. Always pass the current handover object:

**WRONG:**
```dart
// rejectDialogHandover may be stale
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => RejectDialog(
      lineId: lineId,
      handover: rejectDialogHandover, // Set minutes ago
    ),
  ),
);
```

**CORRECT:**
```dart
final handover = await ref.read(pendingHandoverProvider((lineId, handoverId)).future);
// Fresh handover data, snapshot IDs are current
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => RejectDialog(
      lineId: lineId,
      handover: handover,
    ),
  ),
);
```

### 4. Invalidate Dialog on Line State Update

When line state SSE or polling updates the handover, invalidate the reject dialog:

```dart
void onLineStateChanged(LineState lineState) {
  if (lineState.handoverId != currentHandoverId) {
    // Handover changed, close reject dialog
    Navigator.pop(context);
    // Optionally show a message: "تم تحديث بيانات التسليم."
  } else {
    // Same handover, but data may have changed
    ref.refresh(pendingHandoverProvider((lineId, handoverId)));
  }
}
```

### 5. Disable Submit While Refreshing

Show a loading spinner while handover data is being refreshed. Do not allow submit until refresh completes:

```dart
final isRefreshing = ref.watch(pendingHandoverProvider((lineId, handoverId))).isLoading;

submitButton.enabled = !isRefreshing && isFormValid();
```

### 6. On HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH, Reload

If the backend returns `HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH`, the snapshot IDs are stale. Refresh and re-open the dialog:

```dart
catch (e) {
  if (e.errorCode == 'HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH') {
    // Close current dialog
    Navigator.pop(context);
    // Refresh handover
    await ref.refresh(pendingHandoverProvider((lineId, handoverId)));
    // Re-open dialog with fresh data
    showRejectDialog(freshHandover);
  }
}
```

### 7. Never Build Observations from FALET Screen Items

The open FALET screen (from a different endpoint) has different IDs. Always build observations from the handover response, using `faletSnapshotId`:

**WRONG (this was the production bug):**
```dart
// Mixing two different ID spaces
final faletItems = await fetchFaletScreen(lineId);
final observations = faletItems.map((item) =>
  LineHandoverItemObservation(
    faletSnapshotId: item.faletId, // WRONG: faletId is FaletCurrentState.id
    observedQuantity: item.quantity,
  )
).toList();
```

**ALSO WRONG (even using the handover response, but the wrong field):**
```dart
// Reading faletId off the handover response and sending it as snapshot id
final handover = await fetchPendingHandover(lineId, handoverId);
final observations = handover.faletItems.map((item) =>
  LineHandoverItemObservation(
    faletSnapshotId: item.faletId, // WRONG: still FaletCurrentState.id
    observedQuantity: userInput[item.faletId],
  ),
).toList();
```

**CORRECT:**
```dart
// Build from handover.faletItems using the new faletSnapshotId field
final handover = await ref.read(pendingHandoverProvider((lineId, handoverId)).future);
final observations = handover.faletItems.map((item) =>
  LineHandoverItemObservation(
    faletSnapshotId: item.faletSnapshotId, // LineHandoverFaletSnapshot.id
    observedQuantity: userInput[item.faletSnapshotId] ?? 0,
  ),
).toList();
```

---

## 9. UI Changes Needed

### Files to Update

1. **Handover models** — **add `faletSnapshotId` field** to the FALET item class; keep `faletId` (now treat as informational only).
2. **LineHandoverCard** — shows the pending handover summary; can still display `faletId` if useful, but reject flows must read `faletSnapshotId`.
3. **Reject dialog / bottom sheet** — collects rejection details; key inputs by `faletSnapshotId`.
4. **Repository reject method** — builds the HTTP request; map each row's `faletSnapshotId` (not `faletId`) into `itemObservations[].faletSnapshotId`.
5. **Provider pending handover state** — fetches and caches handover data.
6. **Error mapping** — localizes backend error codes.

### UI Details

#### A. Display Sender Declared Quantity

For each FALET snapshot, show the sender declared quantity so the receiver can compare:

```dart
// In reject dialog
for (final snapshot in handover.faletSnapshots) {
  ListTile(
    title: Text(snapshot.productTypeNameSnapshot),
    subtitle: Text("المصرح: ${snapshot.quantity}"), // "Declared: 10"
    trailing: TextFormField(
      decoration: InputDecoration(labelText: "المرصود"), // "Observed"
      onChanged: (value) {
        observations[snapshot.id] = int.parse(value);
      },
    ),
  );
}
```

#### B. For "عدد غير صحيح" (Quantity Input)

When user selects "incorrect quantity," show an input field for each snapshot's observed quantity:

```dart
if (incorrectQuantityFlag) {
  return ListView(
    children: handover.faletSnapshots.map((snapshot) =>
      TextFormField(
        decoration: InputDecoration(
          labelText: "${snapshot.productTypeNameSnapshot} - المرصود",
          hintText: "أدخل الكمية المرصودة",
        ),
        keyboardType: TextInputType.number,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "مطلوب";
          }
          final qty = int.tryParse(value);
          if (qty == null || qty < 0) {
            return "كمية غير صحيحة";
          }
          return null;
        },
        onChanged: (value) {
          observations[snapshot.id] = int.parse(value);
        },
      )
    ).toList(),
  );
}
```

#### C. For "لا يوجد فالت" (Auto-Zero)

When user selects "no FALET found," automatically set `observedQuantity = 0`:

```dart
onChanged: (value) {
  if (value == 'no_falet_found') {
    // Auto-fill all observations with 0
    for (final snapshot in handover.faletSnapshots) {
      observations[snapshot.id] = 0;
    }
    // Hide input fields, show summary: "الكمية المرصودة: 0"
  }
}
```

#### D. For Multiple Snapshots

If a handover has multiple FALET snapshots, collect observed quantity for every one:

```dart
if (handover.faletSnapshots.length > 1) {
  showDialog(
    title: "عدد غير صحيح",
    body: "يجب تحديد الكمية المرصودة لكل بند فالت",
    children: handover.faletSnapshots.map((snapshot) =>
      // Input field for each snapshot
    ),
  );
}
```

#### E. Validation Message for Generic Rejection

If user tries to reject with only a comment (otherReason), show a blocking message:

```dart
if (rejectionReasons.isEmpty) {
  showErrorDialog(
    title: "خطأ",
    message: "الملاحظات وحدها غير كافية. يجب تحديد مشكلة كمية أو فالت غير مصرح عنه.",
  );
  return; // Don't submit
}
```

---

## 10. Testing Checklist For Flutter Agent

### 0. Response Parsing (NEW — added after backend contract update)

- **Setup:** Open the handover review screen for any pending handover.
- **Verify in network logs:** The response body for `faletItems[]` now contains both `faletSnapshotId` (new) and `faletId` (existing).
- **Verify in app:** The Dart `HandoverFaletItem.fromJson` reads `faletSnapshotId` without throwing. Print/log the parsed `faletSnapshotId` and confirm it differs from `faletId`.
- **Sanity check:** `faletSnapshotId` should be the `LineHandoverFaletSnapshot.id` value (DB primary key); `faletId` should be the `FaletCurrentState.id`. They are intentionally different IDs.

### 1. Reject with Wrong Quantity

- **Setup:** Handover with snapshot ID `100`, sender declared `10` units.
- **User action:** Select "عدد غير صحيح", enter observed quantity `5`.
- **Expected payload:**
  ```json
  {
    "incorrectQuantity": true,
    "itemObservations": [{"faletSnapshotId": 100, "observedQuantity": 5}]
  }
  ```
- **Expected result:** Backend returns `200`, handover status changes to `REJECTED`, `FaletDispute` created.
- **UI feedback:** Show "تم الرفض بنجاح. سينتظر قرار المدير."

### 2. Reject with "لا يوجد فالت"

- **Setup:** Handover with snapshot ID `100`, sender declared `10` units.
- **User action:** Select "لا يوجد فالت".
- **Expected payload:**
  ```json
  {
    "incorrectQuantity": true,
    "itemObservations": [{"faletSnapshotId": 100, "observedQuantity": 0}]
  }
  ```
- **Expected result:** Backend returns `200`, handover status changes to `REJECTED`, `FaletDispute` created with operational quantity = 0.
- **UI feedback:** Show "تم الرفض. لم يتم العثور على فالت."

### 3. Reject with Stale Snapshot ID

- **Setup:** Handover #82 has snapshots `[100, 101]`. User closes and re-opens the dialog.
- **Handover changes (via SSE):** Handover #82 now has snapshots `[200, 201]`.
- **User action:** App still has old snapshot ID `100` in memory. User submits rejection.
- **Expected payload:**
  ```json
  {
    "incorrectQuantity": true,
    "itemObservations": [{"faletSnapshotId": 100, "observedQuantity": 5}]
  }
  ```
- **Expected result:** Backend returns `400 HANDOVER_OBSERVATION_SNAPSHOT_MISMATCH`.
- **UI feedback:** Show "بيانات التسليم قديمة، يرجى تحديث الصفحة والمحاولة مرة أخرى." + close dialog + refetch + optionally re-open with fresh data.

### 4. Reject otherReason Only

- **Setup:** Handover with snapshot ID `100`.
- **User action:** Select "سبب آخر" and enter a comment, but do NOT select quantity or FALET issues.
- **Expected payload:**
  ```json
  {
    "incorrectQuantity": false,
    "otherReason": true,
    "otherReasonNotes": "الخط لم يكن جاهزًا",
    "undeclaredFaletFound": false
  }
  ```
- **Expected result:** Backend returns `400 HANDOVER_REJECTION_REASON_INVALID`.
- **UI feedback:** App should block this locally before sending. Show "سبب الرفض غير كافٍ. يجب اختيار مشكلة كمية أو فالت."

### 5. Refresh Case — Incoming Operator Authorizes

- **Setup:** Line is ready for incoming op. Pending handover is cached in state.
- **User action:** Incoming operator scans PIN, authorizes.
- **Expected:** App fetches fresh pending handover, invalidates old dialog state.
- **Verify:** If user opens reject dialog, snapshot IDs are current (not stale from before authorization).

### 6. Multi-Snapshot Handover

- **Setup:** Handover with 3 snapshots: `[100, 101, 102]`, with declared quantities `[10, 8, 5]`.
- **User action:** User selects "عدد غير صحيح", enters observed quantities `[10, 4, 0]` (mismatch on snapshot 101 and 102).
- **Expected payload:**
  ```json
  {
    "incorrectQuantity": true,
    "itemObservations": [
      {"faletSnapshotId": 100, "observedQuantity": 10},
      {"faletSnapshotId": 101, "observedQuantity": 4},
      {"faletSnapshotId": 102, "observedQuantity": 0}
    ]
  }
  ```
- **Expected result:** Backend returns `200`, `FaletDispute` created with 3 items.
- **UI feedback:** "تم الرفض. تم إنشاء نزاع مع 3 بنود."

### 7. Confirm Flow Unaffected

- **Setup:** Same handover, user decides to accept (not reject).
- **User action:** User taps "استقبول الخط" (accept line).
- **Expected:** Handover status changes to `ACCEPTED` (or `CONFIRMED`), no dispute created, line continues.
- **Verify:** This flow is unchanged and still works.

### 8. Multiple Handovers on Same Line (Provider Keying)

- **Setup:** Line #1 has handover #82 (snapshots `[100, 101]`), then incoming op authorizes and handover #83 (snapshots `[200, 201]`) appears.
- **User action:** User was in reject dialog for #82, then rejects #83.
- **Expected:** App uses correct snapshot IDs for #83 (not #82's IDs).
- **Verify:** Provider is keyed by `(lineId, handoverId)`, not just `lineId`.

### 9. Backend Verification Query (Run Manually)

After successful rejection, verify the dispute was created:

```sql
SELECT
    h.id AS handover_id,
    h.status,
    h.dispute_id,
    d.id AS dispute_id,
    d.decision_status,
    COUNT(di.id) AS item_count
FROM line_handover h
LEFT JOIN falet_dispute d ON h.dispute_id = d.id
LEFT JOIN falet_dispute_item di ON di.dispute_id = d.id
WHERE h.id = 82
GROUP BY h.id, d.id;
```

**Expected output:**
```
handover_id=82, status=REJECTED, dispute_id=<ID>, decision_status=PENDING, item_count=1 (or more)
```

---

## 11. Backend Verification Queries

Use these SELECT-only queries to inspect the backend state. **Do NOT modify data.**

### Query 1: Get Valid Snapshot IDs for a Handover

Run this to see which snapshot IDs are valid for a specific handover:

```sql
SELECT
    s.id AS snapshot_id,
    s.handover_id,
    s.falet_current_state_id,
    s.product_type_id,
    s.product_type_name_snapshot,
    s.quantity AS sender_declared_quantity,
    s.observed_quantity,
    s.is_last_active_product
FROM line_handover_falet_snapshots s
WHERE s.handover_id = :handoverId
ORDER BY s.id;
```

**Replace `:handoverId`** with the actual handover ID (e.g., `82`).

**Use case:** After the error "Observation references unknown snapshot id 62", run this query to see what snapshot IDs are actually valid for the handover.

---

### Query 2: Get FALET State Details for a Handover

Run this to see the linked FALET state objects:

```sql
SELECT
    s.id AS snapshot_id,
    fcs.id AS falet_state_id,
    fcs.status,
    fcs.quantity,
    fcs.production_line_id,
    fcs.product_type_id,
    fcs.product_type_name_snapshot
FROM line_handover_falet_snapshots s
LEFT JOIN falet_current_states fcs
    ON fcs.id = s.falet_current_state_id
WHERE s.handover_id = :handoverId
ORDER BY s.id;
```

**Use case:** Verify that FALETs are in `OPEN` state (not already `RESOLVED`), which would fail with `FALET_STATE_NOT_AVAILABLE_FOR_REJECTION`.

---

### Query 3: Check Dispute Creation After Rejection

Run this after a successful rejection to verify the dispute was created:

```sql
SELECT
    h.id AS handover_id,
    h.status,
    h.dispute_id,
    d.id AS dispute_id,
    d.decision_status,
    COUNT(di.id) AS dispute_item_count
FROM line_handover h
LEFT JOIN falet_dispute d ON h.dispute_id = d.id
LEFT JOIN falet_dispute_item di ON di.dispute_id = d.id
WHERE h.id = :handoverId
GROUP BY h.id, d.id;
```

**Expected output (post-rejection):**
```
handover_id=82, status=REJECTED, dispute_id=<ID>, decision_status=PENDING, dispute_item_count=1 (or more)
```

---

### Query 4: Compare FALET IDs vs. Snapshot IDs

To understand the difference between `faletId` and `faletSnapshotId`:

```sql
-- FALET items (from the FALET lifecycle)
SELECT
    f.id AS falet_id,
    f.scanned_value,
    pt.name AS product_type_name,
    f.quantity,
    f.status
FROM falet_current_states f
INNER JOIN product_type pt ON f.product_type_id = pt.id
WHERE f.production_line_id = :lineId
  AND f.status = 'OPEN'
LIMIT 10;

-- FALET snapshots (from a specific handover)
SELECT
    s.id AS snapshot_id,
    s.falet_current_state_id AS falet_id,
    s.handover_id,
    s.product_type_name_snapshot,
    s.quantity AS sender_declared_quantity
FROM line_handover_falet_snapshots s
WHERE s.handover_id = :handoverId;
```

**Observation:** A snapshot row has `snapshot_id` (its own ID) and `falet_id` (the FALET it references). The reject request must use `snapshot_id`, not `falet_id`.

---

## 12. Final Instruction To Frontend Agent

This handoff document is the specification. **Do not weaken the backend validation.** The validation exists to prevent the production bug (handover #79) from happening again.

### What to Do

1. **Add `faletSnapshotId` to the Dart handover FALET item model** and parse it from `faletItems[].faletSnapshotId` in the response JSON.
2. **Switch the reject flow to send `faletSnapshotId`** — the new field — into `itemObservations[].faletSnapshotId`. Stop sending `faletId`.
3. **Ensure `observedQuantity` is sent correctly** — never `null`, use `0` for "لا يوجد فالت".
4. **Restructure state management** to key pending handovers by `(lineId, handoverId)`, not just `lineId`.
5. **Refresh handover data** after incoming operator authorization and after line state changes.
6. **Validate locally** before submitting to provide immediate user feedback.
7. **Handle the 7 backend error codes** with user-friendly Arabic messages.
8. **Test all scenarios** in the testing checklist (including the new Test 0).

### What NOT to Do

- Do not ask the backend to allow `otherReason=true` alone.
- Do not send `faletId` (FaletCurrentState.id) in `itemObservations[].faletSnapshotId`. Use the new `faletSnapshotId` field.
- Do not remove `faletId` from the model — it's still useful for FALET screen / reconciliation views and is preserved for backward compatibility.
- Do not reuse snapshot IDs from previous handovers.
- Do not build observations from the FALET screen endpoint.
- Do not cache handover data without `handoverId` in the cache key.
- Do not send `null` for `observedQuantity`; use `0` for "no FALET".
- Do not weaken validation — it's there to prevent disputes without a manager-actionable surface.

### Deliverable

Update the Flutter app so that:
1. Rejection requests always use snapshot IDs from the current pending handover.
2. `observedQuantity` is always a number (including 0 for "لا يوجد فالت").
3. No duplicate snapshot IDs are sent.
4. All snapshots in the handover have observations (when `incorrectQuantity=true`).
5. `otherReason` is never submitted alone.
6. All 9 test scenarios pass.

**Status:** Ready for integration testing after Flutter changes are merged. The backend is ready and awaiting Flutter app updates.
