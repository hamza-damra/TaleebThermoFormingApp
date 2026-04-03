# Handover Processing Runtime Fix

## 1. Problem Summary

When the operator completes the per-line handover flow:

1. Operator enters PIN successfully for a line → line is authorized
2. Operator presses "تسليم المناوبة" → handover card/table appears
3. Operator fills in the handover and creates it → `POST /lines/{lineId}/handover` succeeds
4. Frontend shows the pending handover UI with a "معالجة التسليم" action
5. User presses "معالجة التسليم" → backend returns **403 Forbidden**:
   - Error code: `LINE_NOT_AUTHORIZED`
   - Message: `"No active authorization on line {lineId}"`
   - Arabic: `"خط الإنتاج غير مفوض. يرجى إدخال رمز المشغل"`

The backend log confirms:

```
BusinessException: No active authorization on line 1
```

---

## 2. Root Cause

**Frontend flow bug** — the frontend is not following the backend `lineUiMode` state machine.

The backend **intentionally releases** the outgoing operator's authorization at the moment a handover is created. This is by design: the outgoing operator is done, and the line must wait for an incoming operator to authorize via PIN before any further action (including confirm/reject of the handover).

The frontend is skipping the incoming-operator PIN step and immediately trying to call confirm/reject endpoints, which require an active authorization that no longer exists.

### Exact Code Path

1. `LineHandoverService.createHandover()` (line 93–96) releases the outgoing auth:

   ```java
   auth.setStatus(AuthorizationStatus.RELEASED);
   auth.setReleasedAt(clockProvider.nowUtc());
   auth.setReleaseReason("HANDOVER_CREATED");
   authorizationRepository.save(auth);
   ```

2. After this, `LineStateService.getLineState()` computes:
   - `authorized = false` (no ACTIVE auth exists)
   - `pendingHandover = present` (PENDING handover exists)
   - `lineUiMode = "PENDING_HANDOVER_NEEDS_INCOMING"`

3. `LineHandoverService.confirmHandover()` (line 101) and `rejectHandover()` (line 138) both call:

   ```java
   lineAuthorizationService.requireActiveAuthorization(lineId);
   ```

   This throws `LINE_NOT_AUTHORIZED` (403) because no ACTIVE authorization exists.

4. The frontend calls confirm/reject without first requiring the incoming operator to enter their PIN → error.

---

## 3. Backend Behavior After Handover Creation

### Complete State Machine

| Step | Trigger                            | `lineUiMode`                      | `authorized` | `pendingHandover` | `canInitiateHandover` | Frontend Should Show                                                |
| ---- | ---------------------------------- | --------------------------------- | ------------ | ----------------- | --------------------- | ------------------------------------------------------------------- |
| 0    | Line loaded, no operator           | `NEEDS_AUTHORIZATION`             | `false`      | `null`            | `false`               | PIN dialog                                                          |
| 1    | Operator enters PIN                | `AUTHORIZED`                      | `true`       | `null`            | `true`                | Production UI + "تسليم مناوبة" button                               |
| 2    | Outgoing operator creates handover | `PENDING_HANDOVER_NEEDS_INCOMING` | **`false`**  | **present**       | `false`               | Handover summary (read-only) + PIN dialog for incoming operator     |
| 3    | Incoming operator enters PIN       | `PENDING_HANDOVER_REVIEW`         | `true`       | **present**       | `false`               | Handover details + confirm/reject buttons                           |
| 4a   | Incoming operator confirms         | `AUTHORIZED`                      | `true`       | `null`            | `true`                | Production UI (incoming operator is now active)                     |
| 4b   | Incoming operator rejects          | `AUTHORIZED`                      | `true`       | `null`            | `true`                | Production UI (incoming operator is now active, handover discarded) |

### Key Backend Behaviors

- **Authorization is released immediately** when handover is created (reason: `HANDOVER_CREATED`)
- **Line is blocked** for production operations (pallet creation, printing) while a PENDING handover exists
- **PIN authorization is NOT blocked** by pending handover — the `POST /lines/{lineId}/authorize-pin` endpoint does NOT use `LineProductionGuard`, so an incoming operator can always authorize via PIN
- **Confirm and reject both require** an active authorization from the incoming operator
- **Confirm transfers** loose balances from the outgoing operator's session to the incoming operator's session
- **Reject discards** the handover (no balance transfer)

### lineUiMode Computation Logic (LineStateService)

```
if (authorized AND no pending handover)     → "AUTHORIZED"
if (authorized AND pending handover exists)  → "PENDING_HANDOVER_REVIEW"
if (NOT authorized AND pending handover)     → "PENDING_HANDOVER_NEEDS_INCOMING"
if (NOT authorized AND no pending handover)  → "NEEDS_AUTHORIZATION"
```

---

## 4. Backend Changes Made

**No backend changes were needed.**

The backend state machine, DTOs, guard logic, and endpoint semantics are all correct and well-designed:

- `LineHandoverService` correctly releases outgoing auth on handover creation
- `LineHandoverService` correctly requires active auth for confirm/reject (this is the incoming operator's auth)
- `LineStateService` correctly computes all 4 `lineUiMode` values
- `LineStateResponse` exposes `lineUiMode`, `authorized`, `pendingHandover`, and `canInitiateHandover` — everything the frontend needs
- `authorize-pin` endpoint works during pending handover (not gated by `LineProductionGuard`)

---

## 5. Frontend Prompt

> **To: Frontend AI Agent**
>
> ---
>
> ### Issue: "No active authorization on line" error during handover processing
>
> **The backend is correct.** The frontend has a flow gap in the per-line handover state machine.
>
> ---
>
> ### What's happening
>
> After the outgoing operator creates a handover (`POST /lines/{lineId}/handover`), the backend **immediately releases** the outgoing operator's authorization. The line enters the `PENDING_HANDOVER_NEEDS_INCOMING` state, meaning:
>
> - `authorized = false`
> - `pendingHandover` is present
> - `lineUiMode = "PENDING_HANDOVER_NEEDS_INCOMING"`
>
> The frontend is currently showing confirm/reject actions immediately after handover creation and calling those endpoints. Both `confirmHandover` and `rejectHandover` endpoints **require an active authorization** (from the incoming operator). Since no authorization exists after creation, the backend returns **403 `LINE_NOT_AUTHORIZED`**.
>
> ---
>
> ### What must change in the frontend
>
> The frontend must follow the `lineUiMode` state machine exactly. After creating a handover, the frontend must:
>
> 1. **Refresh line state** — call `GET /api/v1/palletizing-line/lines/{lineId}/state` to get the updated `lineUiMode`
> 2. **Render based on `lineUiMode`** — use the value as the single source of truth for what UI to show:
>
> | `lineUiMode`                      | What to render                                                                                                                                                                                    |
> | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
> | `NEEDS_AUTHORIZATION`             | PIN entry dialog (no operator on line)                                                                                                                                                            |
> | `AUTHORIZED`                      | Normal production UI + "تسليم مناوبة" button (visible when `canInitiateHandover = true`)                                                                                                          |
> | `PENDING_HANDOVER_NEEDS_INCOMING` | **Read-only** handover summary (from `pendingHandover` field) + **PIN entry dialog** for the incoming operator. Do **NOT** show confirm/reject buttons. Do **NOT** call confirm/reject endpoints. |
> | `PENDING_HANDOVER_REVIEW`         | Handover details + confirm ("تأكيد") and reject ("رفض") buttons. The incoming operator is now authorized and may act.                                                                             |
>
> ---
>
> ### Correct flow step by step
>
> **Step 1 — Outgoing operator is authorized (`lineUiMode = "AUTHORIZED"`)**
>
> - Show production UI
> - Show "تسليم مناوبة" button (only when `canInitiateHandover = true`)
>
> **Step 2 — Outgoing operator creates handover**
>
> - Call `POST /api/v1/palletizing-line/lines/{lineId}/handover`
> - On success: immediately refresh line state via `GET /api/v1/palletizing-line/lines/{lineId}/state`
> - The response will have `lineUiMode = "PENDING_HANDOVER_NEEDS_INCOMING"`
>
> **Step 3 — Waiting for incoming operator (`lineUiMode = "PENDING_HANDOVER_NEEDS_INCOMING"`)**
>
> - Show a read-only handover summary card with the outgoing operator's name and handover details (from `pendingHandover` in line state)
> - Show the PIN entry dialog so the **incoming operator** can authorize
> - Do **NOT** show confirm/reject buttons
> - Do **NOT** call `POST /lines/{lineId}/handover/{id}/confirm` or `/reject`
>
> **Step 4 — Incoming operator enters PIN**
>
> - Call `POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin` with the incoming operator's PIN
> - On success: refresh line state
> - The response will have `lineUiMode = "PENDING_HANDOVER_REVIEW"`, `authorized = true`
>
> **Step 5 — Incoming operator reviews (`lineUiMode = "PENDING_HANDOVER_REVIEW"`)**
>
> - Show handover details (get full details from `GET /api/v1/palletizing-line/lines/{lineId}/handover/pending` if needed)
> - Show confirm ("تأكيد") and reject ("رفض") buttons
> - **Now** the frontend may call:
>   - `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm` — accepts the handover, transfers loose balances
>   - `POST /api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject` — rejects the handover, no transfer
> - On success: refresh line state → `lineUiMode = "AUTHORIZED"`, incoming operator is now the active operator
>
> ---
>
> ### API endpoints reference
>
> | Endpoint                                                        | Method | When to call                                       | Requires active auth? |
> | --------------------------------------------------------------- | ------ | -------------------------------------------------- | --------------------- |
> | `/api/v1/palletizing-line/lines/{lineId}/authorize-pin`         | POST   | Any time (works during pending handover)           | No                    |
> | `/api/v1/palletizing-line/lines/{lineId}/state`                 | GET    | After any state-changing action                    | No                    |
> | `/api/v1/palletizing-line/lines/{lineId}/handover`              | POST   | When `canInitiateHandover = true`                  | Yes (outgoing)        |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/pending`      | GET    | To get full pending handover details               | No                    |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/confirm` | POST   | Only when `lineUiMode = "PENDING_HANDOVER_REVIEW"` | **Yes (incoming)**    |
> | `/api/v1/palletizing-line/lines/{lineId}/handover/{id}/reject`  | POST   | Only when `lineUiMode = "PENDING_HANDOVER_REVIEW"` | **Yes (incoming)**    |
>
> ---
>
> ### How to avoid the error
>
> The error `"No active authorization on line"` (`LINE_NOT_AUTHORIZED`, 403) occurs when calling confirm/reject without an active authorization. The fix is:
>
> 1. **Never call confirm/reject when `lineUiMode = "PENDING_HANDOVER_NEEDS_INCOMING"`**
> 2. **Always require incoming operator PIN first** — this creates a new ACTIVE authorization
> 3. **Only call confirm/reject when `lineUiMode = "PENDING_HANDOVER_REVIEW"`** — this guarantees an active authorization exists
> 4. **Always refresh line state** after handover creation and after PIN authorization to get the correct `lineUiMode`
>
> ---
>
> ### Key fields in `LineStateResponse` to use
>
> ```json
> {
>   "lineUiMode": "PENDING_HANDOVER_NEEDS_INCOMING", // ← single source of truth
>   "authorized": false, // ← no active auth
>   "pendingHandover": {
>     // ← handover summary
>     "handoverId": 42,
>     "outgoingOperatorName": "أحمد",
>     "status": "PENDING",
>     "looseBalanceCount": 3,
>     "hasIncompletePallet": true,
>     "createdAtDisplay": "...",
>     "notes": "..."
>   },
>   "canInitiateHandover": false, // ← cannot create another handover
>   "blocked": true,
>   "blockedReason": "PENDING_HANDOVER"
> }
> ```

---

## 6. Verification

### Code Inspection

| What was inspected                         | File                                   | Finding                                                                                                                                  |
| ------------------------------------------ | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Handover creation releases auth            | `LineHandoverService.java` L93–96      | `auth.setStatus(RELEASED)` + `releaseReason = "HANDOVER_CREATED"` — confirmed                                                            |
| Confirm requires active auth               | `LineHandoverService.java` L101        | `requireActiveAuthorization(lineId)` — first line of method — confirmed                                                                  |
| Reject requires active auth                | `LineHandoverService.java` L138        | `requireActiveAuthorization(lineId)` — first line of method — confirmed                                                                  |
| `lineUiMode` computation                   | `LineStateService.java` L80–88         | 4-way branch based on `authorized` × `pendingHandover` — confirmed correct                                                               |
| PIN auth works during pending handover     | `LineAuthorizationService.java` L49–90 | `authorizeLineByPin()` has no pending-handover guard — confirmed                                                                         |
| PIN endpoint not gated by production guard | `PalletizingLineController.java`       | `authorize-pin` endpoint calls `lineAuthorizationService.authorizeAndRespond()` directly, does not use `LineProductionGuard` — confirmed |
| Production guard only for production ops   | `LineProductionGuard.java`             | Used only by `PalletizingService` for create-pallet and print-attempt — confirmed                                                        |
| DTOs expose all needed state               | `LineStateResponse.java`               | `lineUiMode`, `authorized`, `pendingHandover`, `canInitiateHandover`, `blocked`, `blockedReason` — all present — confirmed               |

### Conclusion

The backend correctly implements a 4-state line lifecycle for handovers. The error is caused by the frontend skipping the `PENDING_HANDOVER_NEEDS_INCOMING` state and calling confirm/reject before the incoming operator has authorized. No backend changes are required.
