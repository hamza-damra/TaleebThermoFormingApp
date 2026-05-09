# Palletizing App Frontend Update Requirements

> **Audience:** the Frontend AI Agent (or human Flutter engineer) who will modify the **existing** Flutter Palletizing App to align with the Thermoforming + Roll Worker backend.
>
> **Backend version this targets:** the `feature/thermoforming-backend-module` branch, after Tasks 0–44 are committed (Roll Worker App amendment included).
>
> **Companion docs (read alongside this one — same source of truth, different audience):**
> - [`PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md`](PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md) — earlier "what changed in the backend" handoff (the backend reference).
> - [`THERMOFORMING_APP_BACKEND_HANDOFF.md`](THERMOFORMING_APP_BACKEND_HANDOFF.md) — what the operator side now owns.
> - [`ROLL_WORKER_APP_BACKEND_HANDOFF.md`](ROLL_WORKER_APP_BACKEND_HANDOFF.md) — what the Roll Worker side now owns.
>
> This document is **practical** — endpoint payloads come from the actual backend DTOs (`PalletizerAuthRequest`, `PalletizerAuthResponse`, `PalletizerSessionResponse`, `PalletizerLogoutRequest`, `LineStateResponse`, `CreatePalletLineRequest`).

---

## 1. Purpose of this update

The factory operations now span three Flutter apps with three roles:

| Role | Arabic | App | Owns |
|---|---|---|---|
| Thermoforming Operator | المشغّل | **Thermoforming App** (new) | start/end the parent shift, assign Thermoforming lines, supervise. Opens the linked Palletizing line authorization automatically via the backend bridge. |
| Roll Worker | عامل الرولات | **Roll Worker App** (new) | physical roll handling: scan, mount, previous-roll resolution, return / grinding, label reprint, product switch with current-roll-weight entry. |
| Palletizer Employee | المُشَتِّح / موظف الطبليات | **Palletizing App** (this app) | authenticate with PIN after the operator has opened the line, then physically stack / register pallets. |

What this means for the **Palletizing App**:

- **Operator authorization is gone.** The Palletizing App no longer opens the production line by asking for an operator PIN. The line is now opened automatically by the backend when the Thermoforming operator adds the Thermoforming shift-line in the Thermoforming App.
- **Product switching is gone.** The product is fixed by the Thermoforming/Roll Worker flow; the Palletizing App only displays it (read-only).
- **Roll handling is gone.** Scan-roll / previous-roll close / reprint label / product switch all live in the Roll Worker App.
- **The Palletizing App now focuses on the palletizer-employee** (المُشَتِّح): a smaller, simpler PIN auth that identifies who physically stacked each pallet. Pallet creation requires this session.

The end-state user flow (from the floor's perspective):

1. **Thermoforming operator** starts a shift in the Thermoforming App and adds a Thermoforming line. Backend opens the Palletizing line authorization automatically.
2. **Roll worker** logs in to the Roll Worker App and mounts a roll on the line.
3. **Palletizer employee** logs in to the Palletizing App with their PIN. The line is already open and a product is already set. They start creating pallets.

The Palletizing App is the third step of three. Its job is now simpler.

---

## 2. What must NOT change visually

> **Critical constraint.** The visual style of the existing Palletizing App must remain the same. This is a **flow refactor, not a redesign.**

Keep:
- The same general layout / screen structure.
- The same color palette, spacing, card style, button style, dialog style, loading states.
- The same Arabic RTL direction and the same production-floor-friendly large controls (large touch targets, bold legible numbers, sticky CTAs).
- The same iconography and the same brand identity.
- The same way the home screen presents the line, the current product, and the "create pallet" CTA — only the data behind those widgets changes.

Do **not**:
- Redesign the app from scratch.
- Introduce a new visual identity, new typography system, new color tokens, or a new component library.
- Move buttons / cards "for clarity" — workers know the existing layout by muscle memory.
- Change the pallet creation form's visible fields beyond what's required by the new auth flow.

The app should feel like the same Palletizing App workers already know — **only the flow and the information shown change.**

---

## 3. Required role separation in the UI

The frontend must clearly distinguish three identities. Use the exact Arabic labels below.

| Concept | Arabic label | Where it comes from | Editable in Palletizing App? |
|---|---|---|---|
| Thermoforming operator on duty | **المشغّل** | The active Thermoforming shift / shift-line authorization. Read from `LineStateResponse.authorization` (existing field). | ❌ Read-only display |
| Palletizer employee using this device | **المُشَتِّح** (or **موظف الطبليات** in longer form) | New `PalletizerSession` created by `POST /lines/{lineId}/palletizer-auth`. | ✅ Authenticated here |
| Current product on the line | **المنتج الحالي** | `LineStateResponse.currentProductTypeName` (existing field). | ❌ Read-only display, with subtitle "**المنتج مُدار من تطبيق التشكيل الحراري**" |

Other Arabic strings the frontend will need:

- **بانتظار بدء المناوبة من المشغّل** — main message on the "no active shift-line" waiting screen.
- **سيتم فتح الخط تلقائيًا بعد بدء المناوبة من تطبيق التشكيل الحراري** — subtitle on the same screen.
- **تسجيل دخول المُشَتِّح** — title on the palletizer PIN screen.
- **سجّل دخولك كموظف طبليات للبدء بتسجيل الطبليات** — subtitle on the same screen.
- **دخول** — primary button on the PIN screen.
- **تسجيل خروج المُشَتِّح** — palletizer-logout label/CTA in the menu.
- **المنتج الحالي** / **مثبّت** / **لا يمكن تغييره من هذا التطبيق** — current-product card labels.

Render these as exact strings; do not translate them via auto-translation.

---

## 4. Old Palletizing flows that must be removed

The following backend endpoints have been **hard-removed** from the backend (Tasks 17, 22.6, 40 — see [PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md §2](PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md) and the implementation report's §6). Calling them returns **HTTP 404** — there is no fallback, no feature flag, no shim.

| Removed endpoint | Removal commit |
|---|---|
| `POST /api/v1/palletizing-line/lines/{lineId}/authorize-pin` | `0cbe119` (Task 17) |
| `POST /api/v1/palletizing-line/lines/{lineId}/select-product` | `4e3b8dc` (Task 22.6) |
| `POST /api/v1/palletizing-line/lines/{lineId}/product-switch` | `4e3b8dc` (Task 22.6) |

The Flutter app must:

- **Stop calling all three.** Search the codebase for `authorize-pin`, `select-product`, `product-switch` and delete the call sites.
- **Remove the operator PIN overlay** that historically blocked the line until the operator authorized it.
- **Remove the line authorization PIN flow** entirely — including any "force release" / "switch operator" buttons that depend on it.
- **Remove the product selection UI** — the dropdown / search / list-of-products screen used to pick the line's product on first authorization.
- **Remove the product-switch dialog** — including the "switch product" entry point (button or menu item).
- **Remove product-switch providers / state / events / API client methods.** Riverpod providers, Bloc events, Stream subscriptions — all of it.
- **Remove any local logic that assumes the Palletizing App can change the current product.** No "if no product → ask user to pick one" path.

Old builds of the Palletizing App that still call any of these endpoints will fail in production with 404s. **Backend + updated Palletizing App must be deployed in lock-step** (see §14).

---

## 5. New Palletizing runtime states

The home screen (or whatever screen normally hosts the line state) must drive the UI from **three** explicit states. The state is computed from two backend calls:

- `GET /api/v1/palletizing-line/lines/{lineId}/state` → `LineStateResponse` (existing endpoint).
- `GET /api/v1/palletizing-line/lines/{lineId}/palletizer-session/current` → `PalletizerSessionResponse` (new endpoint, see §6).

State decision tree:

```
LineStateResponse.authorized == false
  → State A — Waiting for Thermoforming line opening

LineStateResponse.authorized == true
  AND palletizer-session/current returns 404 ROLL_WORKER_SESSION_REQUIRED... wait, PALLETIZER_SESSION_REQUIRED
  → State B — Line open, palletizer not authenticated

LineStateResponse.authorized == true
  AND palletizer-session/current returns 200 with an ACTIVE session
  → State C — Active palletizing work
```

### State A — Waiting for Thermoforming line opening

**Condition:** `LineStateResponse.authorized == false` (no active line authorization, which now means the Thermoforming operator has not yet added a shift-line for this Palletizing line).

**UI:**
- Centered waiting card / illustration in the same Palletizing visual style.
- Title: **بانتظار بدء المناوبة من المشغّل**
- Subtitle: **سيتم فتح الخط تلقائيًا بعد بدء المناوبة من تطبيق التشكيل الحراري**
- A small "تحديث" (refresh) button or a passive auto-poll (every 10–15s) to re-fetch line state.
- **Disable** any pallet-creation entry points.
- **Do NOT** show the old operator PIN input. There is no operator PIN flow on this app anymore.

### State B — Line open, palletizer not authenticated

**Condition:** `LineStateResponse.authorized == true` AND `GET .../palletizer-session/current` returns **404 PALLETIZER_SESSION_REQUIRED** (no active palletizer session).

**UI:**
- Palletizer employee PIN screen.
- Title: **تسجيل دخول المُشَتِّح**
- Subtitle: **سجّل دخولك كموظف طبليات للبدء بتسجيل الطبليات**
- Numeric PIN keypad (same component used by the old operator PIN screen — re-skinned, not redesigned).
- Primary button: **دخول**
- Errors render under the PIN input per §11.

### State C — Active palletizing work

**Condition:** `LineStateResponse.authorized == true` AND `GET .../palletizer-session/current` returns **200** with an ACTIVE `PalletizerSessionResponse`.

**UI:**
- The normal pallet-creation home screen (existing layout).
- Top section shows three identity / context cards:
  - **المنتج الحالي** + product name (from `LineStateResponse.currentProductTypeName`) + small subtitle "**المنتج مُدار من تطبيق التشكيل الحراري**"
  - **المشغّل** + operator name (from `LineStateResponse.authorization.operatorName` if available)
  - **المُشَتِّح** + palletizer name (from `PalletizerSessionResponse.palletizerName`)
- The line name / line number / line status remain where they are today.
- The "create pallet" CTA is enabled.
- Add **تسجيل خروج المُشَتِّح** to the menu / drawer (calls the logout endpoint, transitions back to State B).
- The current product is **read-only** — no edit affordance, no switch button.

If the backend returns `PALLETIZER_SESSION_REQUIRED` on any subsequent call (the session can be ended by the Thermoforming operator ending the shift-line, or by another device replacing the auth), the app must drop back to **State B** and clear the locally-stored session token.

---

## 6. New palletizer auth endpoints

All three endpoints sit under the existing `/api/v1/palletizing-line/**` chain — same `X-Device-Key` transport auth as before. **No JWT, no Bearer token.**

### 6.1 `POST /api/v1/palletizing-line/lines/{lineId}/palletizer-auth`

```http
POST /api/v1/palletizing-line/lines/{lineId}/palletizer-auth
X-Device-Key: <device-key>
Content-Type: application/json

{
  "pin": "1234"
}
```

**Validation (in order):**
1. Line exists / is active → otherwise `PRODUCTION_LINE_NOT_FOUND` (404) / `PRODUCTION_LINE_INACTIVE` (400).
2. An ACTIVE Thermoforming shift-line exists for this line → otherwise `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` (409). _(This is the same condition that drives State A; the frontend usually catches it via `LineStateResponse.authorized == false` before even reaching the PIN screen, but the backend re-validates as a safety net.)_
3. PIN matches an active operator → otherwise `OPERATOR_PIN_INVALID` (401), `OPERATOR_PIN_LOCKED` (423).
4. Operator has `palletizer_stacking_enabled = true` → otherwise `PALLETIZER_NOT_ALLOWED` (403).

**Replace-existing pattern:** if a different palletizer already had an ACTIVE session on this line, the existing session is moved to `REPLACED` (`end_reason=REPLACED_BY_NEW_AUTH`) before the new one is persisted.

**Success response (200):**
```json
{
  "success": true,
  "data": {
    "sessionId": 999,
    "sessionToken": "raw-uuid-token-shown-once",
    "palletizerOperatorId": 42,
    "palletizerName": "Ahmad",
    "palletizingLineId": 10,
    "palletizingLineName": "Line-1",
    "thermoformingShiftId": 700,
    "thermoformingShiftLineId": 800,
    "startedAt": "2026-05-07T10:00:00.000+03:00",
    "startedAtDisplay": "2026-05-07، 10:00 صباحاً"
  }
}
```

**`sessionToken` is the raw token, returned ONCE.** Only its SHA-256 hash is persisted server-side. Store the token in encrypted local storage (e.g. `flutter_secure_storage`); do not log it.

### 6.2 `GET /api/v1/palletizing-line/lines/{lineId}/palletizer-session/current`

```http
GET /api/v1/palletizing-line/lines/{lineId}/palletizer-session/current
X-Device-Key: <device-key>
```

**Returns 200 with the active session if one exists, or 404 `PALLETIZER_SESSION_REQUIRED` if not.**

**Success response (200):**
```json
{
  "success": true,
  "data": {
    "sessionId": 999,
    "palletizerOperatorId": 42,
    "palletizerName": "Ahmad",
    "palletizingLineId": 10,
    "palletizingLineName": "Line-1",
    "thermoformingShiftId": 700,
    "thermoformingShiftLineId": 800,
    "status": "ACTIVE",
    "startedAt": "2026-05-07T10:00:00.000+03:00",
    "startedAtDisplay": "2026-05-07، 10:00 صباحاً",
    "lastUsedAt": "2026-05-07T10:42:18.512+03:00",
    "lastUsedAtDisplay": "2026-05-07، 10:42 صباحاً"
  }
}
```

**No `sessionToken` field** — the raw token is only ever exposed at auth time.

App behaviour:
- Call this on app start, on app foreground / resume, and after any navigation back to the home screen.
- On 200 → State C.
- On 404 with `PALLETIZER_SESSION_REQUIRED` → clear locally-stored token, transition to State B.

### 6.3 `POST /api/v1/palletizing-line/lines/{lineId}/palletizer-logout`

```http
POST /api/v1/palletizing-line/lines/{lineId}/palletizer-logout
X-Device-Key: <device-key>
Content-Type: application/json

{
  "sessionToken": "raw-uuid-token"
}
```

**Success response (200):**
```json
{ "success": true, "data": null }
```

Idempotent. Logging out an already-ended session is a no-op (200, no error). After a successful logout, clear the locally-stored token and transition back to State B.

Errors:
- `PALLETIZER_SESSION_REQUIRED` (400 missing/blank token / 404 unknown / 403 wrong line) — see §11.

### 6.4 Cascading end (no client action required)

When the Thermoforming operator ends the shift-line via the Thermoforming App, the backend automatically transitions every ACTIVE `PalletizerSession` for that shift-line to `ENDED` with reason `SHIFT_LINE_ENDED`. The next call from the device will return `PALLETIZER_SESSION_REQUIRED`. Treat that consistently per §11 — drop to State B.

---

## 7. Pallet creation behavior

The pallet-creation endpoint is unchanged in shape but its **preconditions** are different:

```http
POST /api/v1/palletizing-line/lines/{lineId}/pallets
X-Device-Key: <device-key>
Content-Type: application/json

{
  "productTypeId": 5,
  "quantity": 50
}
```

**New precondition:** the backend looks up the active `PalletizerSession` on the line. If none exists, the call is rejected with `PALLETIZER_SESSION_REQUIRED` (HTTP 409). The Flutter app must then transition to State B (palletizer PIN screen).

**Important — do NOT send palletizer identity in the request body.** The backend reads palletizer identity exclusively from the active session. Specifically, the backend stamps the new `pallete` row with:

| Pallet column | Source |
|---|---|
| `palletizer_operator_id` | active `PalletizerSession.operator.id` |
| `palletizer_session_id` | active `PalletizerSession.id` |
| `palletizer_name_snapshot` | `PalletizerSession.operatorNameSnapshot` |
| `thermoforming_shift_id` | session's bound shift-line's parent shift |
| `thermoforming_shift_line_id` | session's bound shift-line |
| `operator_id` (existing) | the supervising Thermoforming operator (from the line authorization) |

If the Flutter app today sends an `operatorId` or any "who am I" field in the create-pallet body, **remove it** — the backend ignores it and could surface a security weakness if the body said "X" but the session said "Y".

**Existing pallet-creation errors** (`FALET_MUST_BE_CONSUMED_FIRST`, `PRODUCT_TYPE_NOT_FOUND`, `PRODUCT_TYPE_INACTIVE`, etc.) keep their existing behaviour. The new auth flow only adds the `PALLETIZER_SESSION_REQUIRED` case at the top.

---

## 8. Current product display requirement

The current product is **read-only** in the Palletizing App. Treat it as data, never as a control.

**Where to read it from:** `LineStateResponse.currentProductTypeName` and `currentProductTypeId` (existing fields on the existing `GET /lines/{lineId}/state` endpoint).

**UI rules:**
- Render the current product in the same area where it's rendered today (the line state header, or wherever the existing layout puts product info). **Do not move it.**
- Use a card or badge consistent with the existing Palletizing visual style.
- Add a small read-only hint underneath:
  - **المنتج مُدار من تطبيق التشكيل الحراري**
  - Optionally also: **مثبّت** or **لا يمكن تغييره من هذا التطبيق**
- **Do NOT** show the product as editable (no inline pencil, no on-tap "change" affordance).
- **Do NOT** show a "switch product" button anywhere — not in the header, not in the menu, not in pallet creation.
- **Do NOT** show a product selection screen.

Suggested copy for the card:
- Title: **المنتج الحالي**
- Body (large): the product name (e.g. "طبق 700")
- Subtitle (small, muted): **المنتج مُدار من تطبيق التشكيل الحراري**

If `currentProductTypeId` is `null` (no product set on the line), still suppress any "select a product" affordance — show a passive empty state instead. Setting the product is a Roll Worker / Thermoforming responsibility, not a Palletizing one.

---

## 9. Show operator and palletizer names

Both identities must be visible when available — they are different people doing different jobs, and the manager view shows both.

| Identity | Backend source | UI |
|---|---|---|
| **المشغّل** | `LineStateResponse.authorization.operatorName` (existing field — populated when `authorized=true`) | Compact info card / badge in the top section. Read-only. |
| **المُشَتِّح** | `PalletizerSessionResponse.palletizerName` (new — from §6.2) | Compact info card / badge in the top section, next to or under the operator card. Authenticated identity for this device. |

**Layout guidance:**
- Use the existing Palletizing card / badge style. **No new visual primitives.**
- Compact top section, three rows (one per identity / product):

```
المنتج الحالي : طبق 700        ← read-only
المشغّل      : محمد أحمد       ← read-only
المُشَتِّح    : خالد سمير       ← authenticated here
```

- Avoid overcrowding the main pallet creation screen — these three cards belong in a top "context strip", not interleaved with the create-pallet form.
- If a value is missing (e.g., `LineStateResponse.authorization` is null because the line just got opened by an automated bridge call without an `operatorName`):
  - Display **—** as a placeholder, OR
  - If the entire state implies "wait" (line not authorized), show the State A waiting screen instead of partial info.

---

## 10. Bootstrap / line state usage

The Palletizing App's existing bootstrap and line-state endpoints stay in place. The Flutter app should drive its UI from these existing fields plus the new palletizer-session endpoint.

### 10.1 `GET /api/v1/palletizing-line/lines/{lineId}/state` — `LineStateResponse`

Existing fields the frontend will use:

| Field | Type | Used for |
|---|---|---|
| `lineId`, `lineName`, `lineNumber` | numeric / string | line header |
| `authorized` | boolean | **drives State A vs B/C** — `false` ⇒ waiting screen |
| `authorization` (`LineAuthorizationResponse`) | object | shift operator name display in State C |
| `currentProductTypeId`, `currentProductTypeName` | Long / String | read-only current product card (§8) |
| `lineUiMode` | enum string | existing handover UI continues to use it |
| `pendingHandover`, `canInitiateHandover`, `canConfirmHandover`, `canRejectHandover` | various | existing per-line handover flow (unchanged) |
| `hasOpenFalet`, `openFaletCount` | boolean / int | existing FALET button warning (unchanged) |
| `blocked`, `blockedReason` | boolean / string | existing blocked-line UI (unchanged) |

> **Note on `lineUiMode`:** the legacy value `NEEDS_AUTHORIZATION` previously triggered the operator PIN overlay. Under the new model the same condition (`authorized=false`) instead means "no Thermoforming shift-line for this line yet — show the waiting screen". Frontend mapping:
>
> | `lineUiMode` | New Palletizing App behaviour |
> |---|---|
> | `NEEDS_AUTHORIZATION` | Show **State A** waiting screen — NOT the old PIN overlay. |
> | `AUTHORIZED` | Proceed to State B / State C decision based on palletizer session presence. |
> | `PENDING_HANDOVER_NEEDS_INCOMING` | Existing handover incoming UI (unchanged). |
> | `PENDING_HANDOVER_REVIEW` | Existing handover review UI (unchanged). |

### 10.2 `GET /api/v1/palletizing-line/lines/{lineId}/palletizer-session/current` — new

See §6.2. Use this to decide State B vs State C, and to render the **المُشَتِّح** card in State C.

### 10.3 `GET /api/v1/palletizing-line/bootstrap` — existing

Continues to provide device + line list. The Flutter app keeps using it for the device-startup handshake; nothing structural to change here. (If the existing bootstrap already returns line state inline, that field continues to work and can replace the per-line `state` call on first load.)

### 10.4 Things that are NOT in current responses

The frontend should **not** invent fields. If you find yourself wanting:
- A "current Roll Worker name" card (the person who mounted the roll), OR
- A "current mounted roll" card on the Palletizing App,

these are **NOT exposed** today. File a backend follow-up request rather than assuming a field exists.

---

## 11. Error handling

Map backend error codes to UI behaviour. The frontend must branch on the **error code** (not the HTTP status alone), because `PALLETIZER_SESSION_REQUIRED` returns 400/403/404 by call site.

| Error code | Where it fires | UI action |
|---|---|---|
| `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` | palletizer-auth | Show **State A** waiting screen. Toast: **بانتظار بدء المناوبة من المشغّل**. |
| `PALLETIZER_SESSION_REQUIRED` | get-current (404), logout (any), pallet creation, any future palletizer-bound endpoint | Clear locally-stored token. Drop to **State B** palletizer PIN screen. |
| `PALLETIZER_NOT_ALLOWED` | palletizer-auth | Stay on PIN screen. Show: **هذا الموظف غير مصرح له بتسجيل الطبليات**. |
| `OPERATOR_PIN_INVALID` | palletizer-auth | Stay on PIN screen. Show generic "PIN غير صحيح" feedback (use existing copy if any). |
| `OPERATOR_PIN_LOCKED` | palletizer-auth | Show "تم قفل رقم التعريف، حاول لاحقًا" with the existing locked-PIN UX from before. |
| `LINE_NOT_AUTHORIZED` | any line-scoped action that requires authorization | Refresh `LineStateResponse`. If `authorized=false`, show State A. |
| `THERMOFORMING_SHIFT_NOT_ACTIVE` | indirect (parent shift went away mid-session) | Refresh state. Treat as State A. |
| `PRODUCT_TYPE_NOT_FOUND` / `PRODUCT_TYPE_INACTIVE` | pallet creation | Show existing "product unavailable" message. Refresh `LineStateResponse` to pick up the new product. |
| `FALET_MUST_BE_CONSUMED_FIRST` | pallet creation | Existing FALET-first behaviour — unchanged. |
| **HTTP 404** on any of `/authorize-pin`, `/select-product`, `/product-switch` | client bug | This means the Flutter app still has a legacy call. Fix the source code; do not show this to the user. |

For any error code not explicitly listed: show a generic "حدث خطأ، حاول مرة أخرى" with the raw error code in a debug overlay (matches the existing app-wide error pattern).

---

## 12. State management guidance

Backend is the source of truth. Local state is a cache, not a contract.

**Recommended Riverpod / Bloc structure** (adapt to the app's existing pattern — don't introduce a new framework):

| Provider / state | Lifetime | Source |
|---|---|---|
| `lineIdProvider` | persistent | device config / line picker |
| `lineStateProvider` | reactive, refreshed on resume | `GET .../lines/{id}/state` |
| `palletizerSessionTokenProvider` | encrypted secure storage, persistent | `POST .../palletizer-auth` response, **once** |
| `palletizerSessionProvider` | reactive, refreshed on resume | `GET .../palletizer-session/current` |
| `uiStateProvider` (computed) | derived | maps `(lineState, palletizerSession)` → State A / B / C per §5 |

**Hard rules:**
- **Never fake `AUTHORIZED` locally.** Render strictly based on the backend response.
- **Never assume the current product can be changed locally.** Don't optimistic-update `currentProductTypeName` from any local action.
- **Refresh `lineState` AND `palletizerSession` on app resume** (Flutter's `WidgetsBindingObserver.didChangeAppLifecycleState == resumed`).
- **On palletizer logout (success or any flavour of `PALLETIZER_SESSION_REQUIRED`):** clear the locally-stored token, drop to State B.
- **Do not retry on `PALLETIZER_NOT_ALLOWED`** — it's a permission decision, not a transient failure. Re-prompt for a different PIN.
- **Throttle refreshes.** State A should poll at ~10–15s intervals, not aggressively. State C only refreshes on user action / on resume.

---

## 13. UI/UX acceptance criteria

The Palletizing App update is "done" when **all** of the following are true:

- [ ] App no longer shows the operator PIN line-opening screen anywhere.
- [ ] App no longer calls `POST .../authorize-pin`.
- [ ] App no longer shows any product selection screen.
- [ ] App no longer calls `POST .../select-product` or `POST .../product-switch`.
- [ ] App shows the **بانتظار بدء المناوبة من المشغّل** waiting state when `LineStateResponse.authorized == false`.
- [ ] App shows the **تسجيل دخول المُشَتِّح** PIN screen when the line is open but no palletizer session exists.
- [ ] App calls `POST .../palletizer-auth` on PIN entry; stores the raw `sessionToken` in encrypted local storage; does not log it.
- [ ] App allows pallet creation **only** when an ACTIVE palletizer session is present.
- [ ] App displays the current product as **read-only** with the **المنتج مُدار من تطبيق التشكيل الحراري** subtitle.
- [ ] App displays the shift operator name (**المشغّل**) when available.
- [ ] App displays the current palletizer name (**المُشَتِّح**).
- [ ] App keeps the same existing Palletizing visual style (no redesign, no new color tokens).
- [ ] App handles `PALLETIZER_SESSION_REQUIRED` from any endpoint by clearing local token + returning to palletizer PIN.
- [ ] App handles `PALLETIZER_NOT_ALLOWED` by staying on the PIN screen with the **هذا الموظف غير مصرح له بتسجيل الطبليات** message.
- [ ] App handles palletizer logout cleanly (calls `POST .../palletizer-logout`, clears local state, returns to State B).
- [ ] App refreshes line state + palletizer session on app foreground / resume.
- [ ] Pallet creation does NOT include any palletizer / operator identity in the request body.
- [ ] Created pallets show the palletizer name (**المُشَتِّح**) on the web admin per-pallet table — sanity-check the manager view after first end-to-end test.

---

## 14. Deployment warning

This is a **hard-cut** backend change. Old Palletizing App builds will:
- Get HTTP 404 from the deleted `authorize-pin`, `select-product`, `product-switch` endpoints.
- Be unable to create pallets (the backend now demands an ACTIVE `PalletizerSession`).
- Be unable to set or switch product (no replacement endpoint exists on the Palletizing App side).

**The updated Palletizing App must ship in lock-step with:**
- The backend branch `feature/thermoforming-backend-module` (this work).
- The new Flutter Thermoforming Operator App (per [`THERMOFORMING_APP_BACKEND_HANDOFF.md`](THERMOFORMING_APP_BACKEND_HANDOFF.md)).
- The new Flutter Thermoforming Roll Worker App (per [`ROLL_WORKER_APP_BACKEND_HANDOFF.md`](ROLL_WORKER_APP_BACKEND_HANDOFF.md)).

**Do NOT deploy the backend alone while the old Palletizing App is still on the floor** — the floor will be unable to create pallets. The deployment runbook must coordinate all four pieces (backend + 3 Flutter apps) into a single release window.

After the lock-step deploy, also flip the operator capability flags per the implementation report's §11.2:
```sql
UPDATE operators SET palletizer_stacking_enabled = TRUE WHERE id IN (...);
```
Without that flip, palletizer auth will reject every operator with `PALLETIZER_NOT_ALLOWED`.

---

## 15. What the Palletizing App does NOT do anymore

Explicit list — useful for code-review and PR descriptions:

- **Does NOT** open the line with an operator PIN. (Line is opened by the backend bridge when the Thermoforming operator adds a shift-line.)
- **Does NOT** switch the current product. (Product is set / switched by the Roll Worker App.)
- **Does NOT** scan rolls, mount rolls, return roll remainders, or send roll remainders to grinding. (All Roll Worker App.)
- **Does NOT** reprint roll labels. (Roll Worker App.)
- **Does NOT** authenticate the Thermoforming operator. (Thermoforming App.)
- **Does NOT** create or end Thermoforming shifts. (Thermoforming App.)
- **Does NOT** create or end Thermoforming shift-lines. (Thermoforming App.)
- **Does NOT** show or modify the supervising operator's identity beyond a read-only display. (No "switch operator" affordance.)

What the Palletizing App **DOES** do:
- Authenticate the palletizer employee (المُشَتِّح) with a PIN.
- Display the current product, current operator, and current palletizer.
- Create pallets — the only mutating action this app still owns.
- Continue to handle the existing per-line **handover** flow between palletizer-employee shifts (unchanged).
- Continue to handle the existing **FALET** entry points (unchanged) per `LineStateResponse.hasOpenFalet`.

---

## 16. Frontend implementation checklist

Practical step-by-step for the Frontend AI Agent. Tackle in order — do not parallelize early steps with later steps that depend on State C UI.

**Search-and-remove (legacy code cleanup):**
- [ ] Search the Flutter codebase for `authorize-pin` and remove every API client method, every call site, every Riverpod / Bloc reference.
- [ ] Search for `select-product` and remove API client methods, screens, providers, dialogs.
- [ ] Search for `product-switch` and remove API client methods, dialogs, providers, state.
- [ ] Search for the operator PIN screen widget(s) used to authorize the line and delete or repurpose for palletizer PIN (carefully — preserve the visual style, retitle).
- [ ] Search for "operator authorization" / "AUTHORIZED" local-state booleans driven by the old PIN flow and delete; the only AUTHORIZED signal now is `LineStateResponse.authorized`.

**Add (new auth flow):**
- [ ] Add API client methods for: `palletizer-auth`, `palletizer-session/current`, `palletizer-logout` (signatures per §6).
- [ ] Add a secure-storage layer for the raw `sessionToken`.
- [ ] Add a Riverpod/Bloc provider for the palletizer session.
- [ ] Add session refresh on app start AND on app resume (`AppLifecycleState.resumed`).
- [ ] Add a logout entry in the menu / drawer (calls logout endpoint, clears local state).

**Update (existing screens):**
- [ ] Update the home screen to render State A / State B / State C per §5.
- [ ] Update the top context strip (or wherever current product appears today) to render: المنتج الحالي / المشغّل / المُشَتِّح.
- [ ] Make the product display read-only and add the **المنتج مُدار من تطبيق التشكيل الحراري** subtitle.
- [ ] Update pallet creation to drop any client-supplied palletizer / operator identity from the request body.
- [ ] Update the global error interceptor to map `PALLETIZER_SESSION_REQUIRED` → clear token + drop to State B.
- [ ] Update the global error interceptor to map `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` → State A waiting screen.

**Test (manual + automated):**
- [ ] Restart the app with no token → should fetch state and either show State A or State B.
- [ ] Resume the app from background → state should refresh; if backend ended the session in the meantime, app should drop to State B.
- [ ] Authenticate as a palletizer-employee with `palletizer_stacking_enabled = true` → State C visible, pallet creation works.
- [ ] Authenticate as an operator without `palletizer_stacking_enabled` → State B with **PALLETIZER_NOT_ALLOWED** message.
- [ ] Try pallet creation while in State B (manually invoke if the UI doesn't allow it) → backend returns 409 PALLETIZER_SESSION_REQUIRED → app drops back to State B cleanly.
- [ ] End the Thermoforming shift-line from the Thermoforming App while the Palletizing App is in State C → next refresh / next call returns `PALLETIZER_SESSION_REQUIRED` → app drops to State A or State B per `LineStateResponse.authorized`.
- [ ] Verify in the web admin / per-pallet table that newly-created pallets show the palletizer name (**المُشَتِّح**) — confirms backend stamping wired correctly through the new app flow.
- [ ] Grep the production build for the strings `authorize-pin`, `select-product`, `product-switch` — should return zero hits in the Flutter source.
- [ ] Capture network traffic in dev mode for one full session — confirm zero 404s from the backend.

**Out of scope for this update (do NOT do):**
- Don't rebuild the visual identity.
- Don't add any roll-handling UI to this app — that lives in the Roll Worker App.
- Don't add any product-switching UI — that lives in the Roll Worker App.
- Don't try to expose the Roll Worker's name or the currently-mounted roll on this app — those fields aren't on `LineStateResponse` today; file a backend follow-up if the floor asks.

---

## Appendix — Backend version reference

Tracked under "Roll Worker App Amendment" in [`docs/backend/THERMOFORMING_BACKEND_MASTER_PLAN.md`](../backend/THERMOFORMING_BACKEND_MASTER_PLAN.md), Tasks 35–44. Implementation report: [`docs/backend/THERMOFORMING_BACKEND_IMPLEMENTATION_REPORT.md`](../backend/THERMOFORMING_BACKEND_IMPLEMENTATION_REPORT.md). Sibling frontend handoffs:
- [`THERMOFORMING_APP_BACKEND_HANDOFF.md`](THERMOFORMING_APP_BACKEND_HANDOFF.md) — operator app.
- [`ROLL_WORKER_APP_BACKEND_HANDOFF.md`](ROLL_WORKER_APP_BACKEND_HANDOFF.md) — roll-worker app.
- [`PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md`](PALLETIZING_APP_AUTH_AND_PRODUCT_SWITCH_HANDOFF.md) — earlier backend-change reference for this app.
