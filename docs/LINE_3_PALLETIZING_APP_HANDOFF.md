# LINE_3 Handoff — Palletizing App — Third Thermoforming Line (TF_LINE_3 → LINE_3)

## 0. Document status

| Item | Value |
|---|---|
| Audience | Flutter engineer / agent working on the **Palletizing App** (thermoforming palletizing tablet app, pubspec `taleeb_thermoforming`, repo `TaleebThermoFormingApp`). Assumes no backend knowledge. |
| Backend source read | `Taleeb-Warehouse-Backend`, branch `main`, HEAD `e47c2c15`, **plus uncommitted work in the tree**: the LINE_3 change (untracked `V191__provision_three_line_thermoforming_topology.java`, `DataSeeder`, `ProductionLineAdminService`, `LineStateResponse` javadoc, …) and owner WIP V189 / V190 (plan-item close handshake). |
| Generated | 2026-09-15 |
| Flutter source read (read-only) | `C:\Users\Hamza Damra\Documents\TaleebThermoFormingApp`, branch `main`, HEAD **`b936b3d66dba1d17314d1d53e5c7300e6561e485`** (2026-09-13, "test: remove obsolete Flutter counter template test"). Working copy is **dirty (27 entries: label / printing / SSE WIP)**. Line numbers in §6 are from the working copy (WC). `palletizing_screen.dart` and `core/constants.dart` are clean (WC = HEAD). For `palletizing_provider.dart`, HEAD = WC − 1 for lines 17–1190. |
| Runtime verification | **None.** No backend boot, no Maven, no DB, no Flutter build or test. §4 is source reading only; see §7. |
| Companion handoff (do not duplicate) | `docs/frontend-handoffs/PALLETIZING_PLAN_ITEM_CLOSE_CONFIRMATION.md` in the backend repo (V190 close handshake, `X-Palletizer-Session-Token`, mandatory `expectedPlanItemId`). Ship it **in the same build** as this handoff. |
| Citation convention | Backend Java is under `src/main/java/ps/taleeb/taleebbackend/` and cited by file name (`LineStateService.java:93`). `V191__…java` is under `src/main/java/db/migration/`. SQL migrations are under `src/main/resources/db/migration/`. Flutter paths are relative to the repo root. |
| Secrets | None in this file. The device key is referred to only as header `X-Device-Key`, property `app.device-api-key`, env `DEVICE_API_KEY`. PINs and session tokens are never shown. |

---

## 1. Executive Summary

**What changed in the backend**

- Flyway **V191** creates palletizing line **LINE_3 'خط ج'** (`line_number` 3) **inactive**, and makes sure machine **TF_LINE_3 'خط التشغيل ج'** exists, is active and `OPERATIONAL`, and is mapped to LINE_3 (`V191__…java:67-76`, `:194-197`, `:205-209`).
- **Go-live = an administrator enables LINE_3.** API: `PATCH /api/v1/admin/production-lines/{id}/enable` (`ProductionLineAdminController.java:69-74`). Web: `POST /web/admin/production-lines/{id}/enable` (`WebAdminProductionLinesController.java:129`). No further migration or release is needed.
- Enabling or disabling now publishes `LineStateChangedEvent(productionLineId)`, only when the flag actually changes (`ProductionLineAdminService.java:137-156`, `:169-171`). This app receives it as SSE event **`palletizing-lines-changed`** on `GET /api/v1/palletizing-line/app-events`.
- **No palletizing endpoint, DTO field, enum or error code was added or removed for LINE_3.** Once LINE_3 is active, `GET /api/v1/palletizing-line/bootstrap` returns a **third `lines[]` entry** (`PalletizingBootstrapService.java:26-31`).

**Why this app must change (BLOCKER)**

1. The UI is hard-wired to two lines:
   - `TabController(length: 2)` (`palletizing_screen.dart:44`)
   - two hard-coded tabs 'ماكنة 1' / 'ماكنة 2' (`:245-286`)
   - `lineNumber == 1` / `== 2` filters (`:602-607`)
   - two `TabBarView` children or two panes (`:625-690`)
   - an enum that only knows `line1` / `line2` (`lib/core/constants.dart:3-42`)

   LINE_3 would never be drawn, so the 'خط ج' station could not register pallets.
2. The provider polls and alerts for **every** line in bootstrap, including lines it does not draw (`palletizing_provider.dart:488-491`, `:533`, `:843-850`, `:1273-1277`). A line 3 with no operator would keep every tablet on the **6 s "urgent" poll** (`:61`). A line-3 takeover would **ring every tablet with no dialog**, because the dialog loop checks only `const [1, 2]` (`palletizing_screen.dart:71`).
3. An SSE frame **never re-fetches bootstrap** (`palletizing_provider.dart:564-577`). An enabled line therefore never appears live. `loadBootstrap` never prunes per-line state (`:618-631`), so a disabled line is never removed and keeps being polled.
4. The printed label side band is `lineNumber == 1 ? 'A' : 'B'`, so a line-3 label would read **'B'**. WC: `lib/domain/entities/pallet_label_content.dart:67-68` (untracked). HEAD: `pallet_success_dialog.dart:392`, `reprint_by_id_dialog.dart:149,467`, `session_drilldown_dialog.dart:535`.

**Required before enabling LINE_3?** **Yes.** Install the updated build on **every** palletizing tablet and pass the §6.11 checkpoint first. Only then may the administrator enable LINE_3.

**Also required before this backend release is deployed at all, independent of LINE_3.** V190 makes `expectedPlanItemId` mandatory on every pallet (`ThermoformingProductionPlanGuard.java:96-102`). The current build never sends it (`lib/data/repositories/palletizing_repository_impl.dart:149-153`). Every pallet on LINE_1 and LINE_2 would fail with `400 PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED`.

---

## 2. Affected App & Impact Matrix

| App | Affected? | Reason (source) | Handoff |
|---|---|---|---|
| Warehouse App | No | Does not use palletizing or thermoforming line endpoints. It shows backend `lineName` as-is. Source: client audit; not re-read for this document. | — |
| Admin App | Yes (verify) | Overview cards and plan reference data list only commissioned machines (`ThermoformingOverviewCardBuilder.java:77`, `AdminAppProductionPlanReferenceService.java:85`). For THERMOFORMING, the `lineId` in the SSE `admin-app-overview-invalidated` frame (`AdminAppSseBroker.java:58`) is a ProductionLine id. | Admin App LINE_3 handoff (sibling file in this folder) |
| **Palletizing App** | **Yes — BLOCKER** | Draws exactly two lines. The refresh path never re-bootstraps. The label letter is A/B only. See §1. | **this file** |
| Roll Worker App | Yes | Bootstrap lists only commissioned machines (`RollWorkerBootstrapService.java:80`). SSE `roll-worker-lines-changed` (`RollWorkerLineEventsSseBroker.java:77`). | Roll Worker App LINE_3 handoff (sibling file) |
| Roll Production App | No | Works only with roll production lines; no thermoforming or palletizing line references. Source: client audit. | — |
| Operator App | Yes | Pickers list TF_LINE_3 as not selectable with `PALLETIZING_LINE_INACTIVE` (`ThermoformingLineAssignmentOptionService.java:61,402`). Claiming it is refused with `PRODUCTION_LINE_INACTIVE` (`ThermoformingShiftLineService.java:163-169`). SSE `operator-line-assignment-changed` (`OperatorLineAssignmentSseBroker.java:82`). | Operator App LINE_3 handoff (sibling file) |

---

## 3. Business Context

**On the floor**

- The factory adds a third thermoforming machine, **'خط التشغيل ج'**. Its output is stacked at a third palletizing station, **'خط ج'**.
- **Staged go-live.** After the deploy, 'خط ج' exists but is switched off, and tablets show nothing new. Once every app is updated and accepted, an administrator switches 'خط ج' on. Tablets must then show a third tab within seconds, with no restart.
- A machine is *commissioned* when the machine is active **and** its palletizing line is active. This app sees only the palletizing-line flag: bootstrap lists **active production lines only** (`ProductionLineRepository.java:12`, used at `PalletizingBootstrapService.java:26`).
- Order of events before the first pallet on 'خط ج':
  1. The admin enables LINE_3.
  2. The admin adds a 'خط ج' plan item.
  3. The operator claims the machine in the Operator App. This opens the line authorization.
  4. The palletizer logs in with PIN on the 'خط ج' tab.
  5. Pallets can be registered.
- One tablet shows **all** active lines. There is no per-device line binding. `X-Device-Key` is one shared secret with no line identity (`DeviceApiKeyFilter.java:57,93-101`).

**Id domains — never mix them**

| Id as it appears to this app | Entity | Where you see it | LINE_3 in production |
|---|---|---|---|
| `lineId`, `palletizingLineId`, `productionLine.id`, `productionLineId`, `?lineId=` | ProductionLine (`production_lines`) | bootstrap `lines[].lineId`; every `/lines/{lineId}/…` path; SSE `palletizingLineId`; create-pallet response; label payload; announcements query | **3** (expected) |
| `thermoformingLineId` | ThermoformingLine (`thermoforming_lines`) | only in SSE takeover and close-request frames, and in the V190 close-request DTO | **4** (expected) |
| `thermoformingShiftLineId`, `thermoformingShiftId` | Operator shift claim | palletizer auth and session responses | unrelated id space |
| `currentPlanItemId` / `expectedPlanItemId` | Plan item | line state / create-pallet request | — |

**Why the ids skew (3 ↔ 4).** On production `thermoforming_lines` already used id 3, so TF_LINE_3 gets id 4 while LINE_3 gets id 3 (`V191__…java:47-48`). For lines 1 and 2 the two ids happen to match, which hides id-kind mistakes. Line 3 is the first place they differ.

Rules for this app:

- Use `lineId` exactly as bootstrap delivers it. Never compute it, never assume `lineId == lineNumber`, and never use `thermoformingLineId` to find a tab or build a path.
- The palletizing API has **no business `code` field** (`LineStateResponse.java`), so the app never sees "LINE_3". Do not invent a code. The current client fabricates `code: 'L${lineNumber}'` (`bootstrap_response_model.dart:65`).
- `line_number` is **not unique** in the database (`V11__palletizing_module.sql:13,19`: only `code` is unique). Do not use it as a map key.

---

## 4. CONFIRMED FROM BACKEND CODE

### 4.1 Topology and id domains

| Business code | Arabic name | `line_number` | Initial state after V191 | Maps to | Source |
|---|---|---|---|---|---|
| LINE_1 | خط أ | 1 | active (unchanged) | — | `V88__unify_production_line_display_names.sql:33` |
| LINE_2 | خط ب | 2 | active (unchanged) | — | V88 |
| **LINE_3** | **خط ج** | **3** | **INACTIVE** | — | `V191__…java:69-71,194-197` |
| TF_LINE_1 | خط التشغيل أ | — | active, OPERATIONAL | LINE_1 | `V191__…java:74,205-209` |
| TF_LINE_2 | خط التشغيل ب | — | active, OPERATIONAL | LINE_2 | `V191__…java:75` |
| **TF_LINE_3** | **خط التشغيل ج** | — | **active, OPERATIONAL** | **LINE_3** | `V191__…java:76` |

- V191 resolves every row **by business code**. It adopts existing rows untouched (`V191__…java:50,119,126`), so an environment where LINE_3 already exists keeps its current flag.
- Dev and H2 seeding mirror this: LINE_3 inactive, TF_LINE_3 active (`DataSeeder.java:195-213,241`).
- At most one active machine per palletizing line (`V62__…sql:50,59-60`). At most one ACTIVE palletizer session per palletizing line (`V63__…sql:44,51`).
- The palletizing chain converts ProductionLine → ThermoformingLine only through that mapping, never by equal ids (`ThermoformingLineOperationalGuard.java:48-67`, `LineStateService.java:239-244`, `PalletizingService.java:224-227`).

### 4.2 Endpoints this app uses that involve lines

**Common to every endpoint below**

- Base path `/api/v1/palletizing-line` (`PalletizingLineController.java:49`). Header `X-Device-Key: <device key>` (`DeviceApiKeyFilter.java:57,93-101`). The chain requires `ROLE_DEVICE`; SSE async dispatch is permitted (`SecurityConfig.java:231-248`).
- Missing or wrong key → `401` `AUTH_INVALID_CREDENTIALS` "Authentication required" (`SecurityAuthEntryPoint.java:28-29`). Access denied → `403` `FORBIDDEN` (`SecurityAccessDeniedHandler.java:28-29`).
- **There is no error code named `DEVICE_KEY_INVALID` in the backend.** The client makes it up itself.
- Envelope (`ApiResponse.java:13-18,44-48`): `{"success":true,"data":…}` or `{"success":false,"error":{"code":"…","message":"…","details":{…}}}`. Null fields are omitted.
- `BusinessException` messages are **English developer text** (for example `LineProductionGuard.java:59`). **Never show `error.message`.** Map `error.code` to Arabic (§6.8).
- Instants are ISO-8601 UTC `…Z`. Display them in `Asia/Hebron`, never in the device timezone.

---

#### 4.2.1 `GET /api/v1/palletizing-line/bootstrap`

Code: `PalletizingLineController.java:64-68` → `PalletizingBootstrapService.java:24-41`.

- **Which lines:** every `production_lines` row with `is_active = true`. **Order:** `line_number` ascending (`ProductionLineRepository.java:12`). If two rows share a `line_number` the order is undefined (no tie-breaker), so treat the returned order as authoritative. The list is **not cached**; each line is built live via `LineStateService.getLineState(line.getId())` (`PalletizingBootstrapService.java:29-31`).
- **Response DTO:** `BootstrapResponse{productTypes: List<ProductTypeItem>, lines: List<LineStateResponse>}` (`BootstrapResponse.java:15-16`).
  - `ProductTypeItem`: `id, name, productName, prefix, color, packageQuantity (int), packageUnit, description, imageFilename` (`BootstrapResponse.java:21-29`).
  - **There is no `productionLines` field.**
- **Line label fields** (`LineStateResponse.java:16-35`; built at `LineStateService.java:348-352`):

| Field | Type | Value | Use |
|---|---|---|---|
| `lineId` | Long | `ProductionLine.id` | **key** + path id |
| `lineName` | String | `ProductionLine.name` | label fallback #2 |
| `lineDisplayName` | String | `ProductionLine.name` (always equal to `lineName` on this server) | **label source #1** |
| `lineNumber` | int (always present) | `production_lines.line_number` | sort echo, ordinal fallback, print letter |

- **Label fallback rule** (backend javadoc, `LineStateResponse.java:18-33`):
  1. Use `lineDisplayName` when it is non-blank.
  2. Otherwise use `lineName` when it is non-blank.
  3. Otherwise derive the Arabic ordinal from `lineNumber` in abjad order: 1 → `خط أ`, 2 → `خط ب`, **3 → `خط ج`**, 4 → `خط د`, 5 → `خط هـ`, 6 → `خط و`, 7 → `خط ز`, 8 → `خط ح`. Beyond 8 (or below 1), use `خط <n>`. The letters come from `LocalizedLineName.java:51`.
  4. **Never derive a label from `lineId`.**
- Other `LineStateResponse` fields the app already consumes are unchanged, and the class is `NON_NULL` (`LineStateResponse.java:13`):
  - Always present: `authorized` (:36), `sessionTable` (:38, `[]` when unauthorized, from `LineStateService.java:105`), `blocked` (:39), `lineUiMode` (:52: `NEEDS_AUTHORIZATION` | `AUTHORIZED` | `PENDING_HANDOVER_REVIEW` | `PENDING_HANDOVER_NEEDS_INCOMING`), `hasOpenFalet` (:76), `openFaletCount` (:81), `defaultPackageQuantitySource` (:127: `PLAN_ITEM` | `PRODUCT_TYPE`), `productionPlanBlocked` (:145), `waitingForOperator` (:171), and all `can*` booleans plus the `*RemainingSeconds` longs.
  - Present only when non-null: `authorization`, `blockedReason` (only `PENDING_HANDOVER`, `LineStateService.java:122`), `currentPlanItem*`, `productionPlanBlockedReason` (`NO_PLAN_ITEM`), `waitingForOperatorReason` (`NO_ACTIVE_THERMOFORMING_OPERATOR`), `waitingForOperatorMessageTitle`, `waitingForOperatorMessage`, `pendingTakeoverRequest` (:204).
  - **There is no `active` flag.** A line's presence in bootstrap *is* the active signal.

**Example A — before enable (LINE_3 inactive)**

`lines` contains `lineNumber` 1 and 2 only:

```json
{
  "success": true,
  "data": {
    "productTypes": [
      {"id": 31, "name": "…", "productName": "…", "prefix": "031", "color": "…", "packageQuantity": 40, "packageUnit": "…"}
    ],
    "lines": [
      {"lineId": 1, "lineName": "خط أ", "lineDisplayName": "خط أ", "lineNumber": 1, "authorized": true, "…": "…"},
      {"lineId": 2, "lineName": "خط ب", "lineDisplayName": "خط ب", "lineNumber": 2, "authorized": true, "…": "…"}
    ]
  }
}
```

**Example B — after enable, LINE_3 just switched on**

No operator has claimed the machine yet, and a 'خط ج' plan item exists on TF_LINE_3 (TF id 4). The palletizing API never shows the TF id. `lineId` is the **ProductionLine id 3**:

```json
{
  "lineId": 3,
  "lineName": "خط ج",
  "lineDisplayName": "خط ج",
  "lineNumber": 3,
  "authorized": false,
  "sessionTable": [],
  "blocked": false,
  "lineUiMode": "NEEDS_AUTHORIZATION",
  "canInitiateHandover": false,
  "canConfirmHandover": false,
  "canRejectHandover": false,
  "hasOpenFalet": false,
  "openFaletCount": 0,
  "hasMountedRoll": false,
  "currentPlanItemPackagesPerPallet": 40,
  "currentPlanItemId": 912,
  "defaultPackageQuantitySource": "PLAN_ITEM",
  "currentPlanItemProductTypeId": 31,
  "currentPlanItemProductName": "…",
  "productionPlanBlocked": false,
  "waitingForOperator": true,
  "waitingForOperatorReason": "NO_ACTIVE_THERMOFORMING_OPERATOR",
  "waitingForOperatorMessageTitle": "بانتظار استلام الخط",
  "waitingForOperatorMessage": "تم إنهاء مناوبة مشغّل التشكيل أو لا يوجد مشغّل حالي على هذا الخط. لا يمكن تكوين طبلية جديدة حتى يستلم مشغّل التشكيل الخط من تطبيقه.",
  "takeoverRemainingSeconds": 0,
  "takeoverHandoverRemainingSeconds": 0,
  "canRequestTakeover": false,
  "canAcceptTakeover": false,
  "canRejectTakeover": false,
  "canCompleteTakeoverAcceptance": false,
  "canRegisterUndeclaredFaletAndAccept": false
}
```

The waiting texts come from `LineStateService.java:64-69`, applied at `:341-346`.

- If there is **no** plan item for TF_LINE_3 (enforcement is on by default: `application.properties:336`, `ThermoformingProductionPlanProperties.java:37`), all `currentPlanItem*` keys are omitted. The line then carries `"productionPlanBlocked": true, "productionPlanBlockedReason": "NO_PLAN_ITEM"` and `productionPlanBlockedMessage` (`LineStateService.java:256-260`).
- **Empty case:** with no active lines the response is `"lines": []` (a list, never null). Keep the existing "لا توجد خطوط إنتاج متاحة" surface (`palletizing_screen.dart:465-533`).

---

#### 4.2.2 `GET /api/v1/palletizing-line/lines/{lineId}/state` — per-line state / poll

Code: `PalletizingLineController.java:120-125` → `LineStateService.java:91-395`.

- The response is the same `LineStateResponse` as one bootstrap entry.
- `{lineId}` is **`ProductionLine.id`**.
- An unknown id → `404 PRODUCTION_LINE_NOT_FOUND` (`LineStateService.java:93-98`).
- **This endpoint does not check `is_active`.** It returns `200` for an **inactive** line such as a disabled LINE_3. Polling `/state` therefore **cannot** tell you a line was disabled; only bootstrap can.

---

#### 4.2.3 `POST /api/v1/palletizing-line/lines/{lineId}/palletizer-auth` — palletizer PIN login

Code: `PalletizerSessionController.java:37-44` → `PalletizerSessionService.java:94-200`.

- **Request:** `{"pin": "<4 digits>"}`. `pin` is `@NotBlank` (`PalletizerAuthRequest.java:9-10`); a blank pin → `400 VALIDATION_ERROR` (`GlobalExceptionHandler.java:63-78`).
- **Check order.** This decides which error you see:

| Step | Check | Failure | Source |
|---|---|---|---|
| 1 | Locks the machine mapped to `lineId`. No active machine mapped. | `404 THERMOFORMING_LINE_MAPPING_NOT_FOUND` | `ThermoformingLineOperationalGuard.java:61-67` |
| 1 | Machine is `PAUSED`. | `409 THERMOFORMING_LINE_PAUSED` | `ThermoformingLineOperationalGuard.java:118-124` |
| 2 | Production line exists. | `404 PRODUCTION_LINE_NOT_FOUND` | `PalletizerSessionService.java:97-102` |
| 3 | **Production line is active.** | **`400 PRODUCTION_LINE_INACTIVE`** | `PalletizerSessionService.java:104-110` |
| 4 | An ACTIVE operator shift-line exists on this palletizing line. | `409 NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` | `PalletizerSessionService.java:116-123` |
| 5 | PIN format. | `400 INVALID_PIN_FORMAT` | `PinCredential.validateFormat` |
| 5 | PIN matches an operator. Locked operators are skipped, so a locked PIN also gets this. | `401 OPERATOR_PIN_INVALID` | `OperatorPinService.java:159-163` |
| 6 | Operator is allowed to stack pallets. | `403 PALLETIZER_NOT_ALLOWED` | `PalletizerSessionService.java:131-137` |

- **Success `200`** (`PalletizerAuthResponse.java:17-26`). LINE_3 example:

```json
{"success": true, "data": {
  "sessionId": 501, "sessionToken": "<returned once — store in secure storage, never log>",
  "palletizerOperatorId": 77, "palletizerName": "…",
  "palletizingLineId": 3, "palletizingLineName": "خط ج",
  "thermoformingShiftId": 9001, "thermoformingShiftLineId": 12345,
  "startedAt": "2026-09-15T05:10:00.123Z", "startedAtDisplay": "…"}}
```

- A successful login replaces any ACTIVE session on the same line (`PalletizerSessionService.java:152-164`).
- It publishes a per-line refresh; see §4.4.

#### 4.2.4 `GET /api/v1/palletizing-line/lines/{lineId}/palletizer-session/current`

- Code: `PalletizerSessionController.java:46-56`.
- `200 PalletizerSessionResponse{sessionId, palletizerOperatorId, palletizerName, palletizingLineId, palletizingLineName, thermoformingShiftId, thermoformingShiftLineId, status, startedAt, startedAtDisplay, lastUsedAt, lastUsedAtDisplay}` (`PalletizerSessionResponse.java:15-26`).
- No ACTIVE session → `404 PALLETIZER_SESSION_REQUIRED`.
- It does not check `is_active`.

#### 4.2.5 `POST /api/v1/palletizing-line/lines/{lineId}/palletizer-logout`

- Code: `PalletizerSessionController.java:58-64` → `PalletizerSessionService.java:221-274`.
- **Request:** `{"sessionToken": "…"}` (`PalletizerLogoutRequest.java:9-10`, `@NotBlank`).
- **Success:** `{"success":true}`. Already ended → success (idempotent).
- **Errors:** unknown token → `404 PALLETIZER_SESSION_REQUIRED`. A token that belongs to another line → `403 PALLETIZER_SESSION_REQUIRED` (`:248-254`).
- It does not check `is_active`.

---

#### 4.2.6 `POST /api/v1/palletizing-line/lines/{lineId}/pallets` — create pallet (incl. V190 `expectedPlanItemId`)

Code: `PalletizingLineController.java:150-160` → `PalletizingService.java:167-355`.

**Request** (`CreatePalletLineRequest.java:11-65`):

| Field | Type | Required | Notes |
|---|---|---|---|
| `productTypeId` | Long | yes (`@NotNull`) | must equal the line's current plan-item product |
| `quantity` | Integer | yes (`@NotNull`, `@Min(1)`) | full pallet quantity |
| `confirmOverproduction` | boolean | no (default false) | resend `true` only after `PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED` |
| **`expectedPlanItemId`** | Long | **always (service-enforced)** | `currentPlanItemId` from the **latest** state of **this** line |
| `firstPalletFaletConsumption` | `{expectedFaletQuantity ≥1, faletId?}` | no | unchanged first-pallet FALET path |

LINE_3 example:

```http
POST /api/v1/palletizing-line/lines/3/pallets
X-Device-Key: <device key>
Content-Type: application/json

{"productTypeId": 31, "quantity": 40, "confirmOverproduction": false, "expectedPlanItemId": 912}
```

**`201` response** (`CreatePalletResponse.java:13-127`, built at `PalletizingService.java:503-507`):

```json
{"success": true, "data": {
  "palletId": 88123, "scannedValue": "031000004512",
  "operator": {"id": 14, "name": "…"},
  "productType": {"id": 31, "name": "…", "productName": "…", "prefix": "031", "color": "…", "packageQuantity": 40, "packageUnit": "…"},
  "productionLine": {"id": 3, "name": "خط ج", "lineNumber": 3},
  "quantity": 40, "currentDestination": "PRODUCTION",
  "createdAt": "2026-09-15T05:31:07.412Z", "createdAtDisplay": "…"}}
```

**Check order** (nothing is created and no serial is consumed on any failure; the guards run before `PalletizingService.java:253`):

1. Machine lock + not paused: `404 THERMOFORMING_LINE_MAPPING_NOT_FOUND` / `409 THERMOFORMING_LINE_PAUSED` (`LineProductionGuard.java:131`).
2. Line exists / **active**: `404 PRODUCTION_LINE_NOT_FOUND` / **`400 PRODUCTION_LINE_INACTIVE`** (`LineProductionGuard.java:48-64`, called at `:132`).
3. Line authorization: `403 LINE_NOT_AUTHORIZED` (`LineAuthorizationService.java:88-94`).
4. Pending handover: `409 LINE_BLOCKED_BY_PENDING_HANDOVER` (`LineHandoverGuardSupport.java:26-31`).
5. ACTIVE palletizer session on the line: `409 PALLETIZER_SESSION_REQUIRED` (`PalletizingService.java:181-187`). The caller's token is **not** checked; the pallet is attributed to the line's active session.
6. Product: `404 PRODUCT_TYPE_NOT_FOUND` / `400 PRODUCT_TYPE_INACTIVE` (`:190-203`).
7. Plan item, resolved with the **machine id taken from the palletizer session**, never the path id (`PalletizingService.java:224-227`):
   - `400 PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED` (`ThermoformingProductionPlanGuard.java:96-102`)
   - `409 PRODUCTION_PLAN_CURRENT_ITEM_CHANGED` with `details {expectedPlanItemId, currentPlanItemId|null}` (`:103-115`)
   - `409 PRODUCTION_PLAN_ITEM_CLOSED` (`:121-126`)
   - `409 PRODUCTION_PLAN_PRODUCT_MISMATCH` (`:127-133`)
   - `409 PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED` (`:143-150`)
8. FALET path: `400 FALET_CONSUMPTION_EXCEEDS_PALLET_QUANTITY` (`PalletizingService.java:242-248`) and the existing FALET codes.

The full V190 semantics (never auto-retry with the new id, the close-request interplay) are in the companion handoff §14–15. They are not repeated here.

#### 4.2.7 `POST /api/v1/palletizing-line/lines/{lineId}/pallets/{palletId}/print-attempts`

- Code: `PalletizingLineController.java:190-198` → `PalletizingService.java:362-367`.
- **Request:** `{printerIdentifier, status, failureReason}`.
- **Same write guard as pallet creation** (`LineProductionGuard.java:130-136`), so a disabled LINE_3 gets `400 PRODUCTION_LINE_INACTIVE`.
- A pallet on another line → `400 PALLET_LINE_MISMATCH` (`LineProductionGuard.java:83-99`).

#### 4.2.8 `GET /api/v1/palletizing-line/lines/{lineId}/first-pallet-context`

- Code: `PalletizingLineController.java:314-319` → `FaletService.java:495-496`.
- Read guard order: **line active first** (`400 PRODUCTION_LINE_INACTIVE`), then authorization, then handover, then machine operational (`LineProductionGuard.java:113-119`).

#### 4.2.9 `GET /lines/{lineId}/falet`, `/lines/{lineId}/falet/exists`, `/lines/{lineId}/session-production-detail`

- Code: `PalletizingLineController.java:271-297` and `:141-146`.
- These check **only** that an active authorization exists (`FaletService.java:258-259`, `LineSessionTableService.java:92-93`). `falet/exists` has no gate (`FaletService.java:925`).
- **None of them checks `is_active`.**

#### 4.2.10 `GET /api/v1/palletizing-line/pallets/{scannedValue}/label` — reprint (not line-scoped)

- Code: `PalletizingLineController.java:181-186`.
- `PalletLabelPayload` includes `productionLineId` (ProductionLine id of the pallet's origin) and `productionLineName` (live name, or the snapshot) (`PalletLabelPayload.java:45-48`, `PalletLabelPayloadFactory.java:64-65`).
- **There is no `lineNumber` in the payload.**

#### 4.2.11 Urgent announcements

- **Pending:** `GET /api/v1/palletizing-line/urgent-announcements/pending?lineId={ProductionLine.id}` (`PalletizingLineUrgentAnnouncementController.java:41-51`).
- **Ack:** `POST /api/v1/palletizing-line/urgent-announcements/{id}/ack?lineId={ProductionLine.id}` (`:54-66`).
- Response items: `ManagerAnnouncementGenericResponse{id, targetDomain, title, message, createdAt, createdAtDisplay, expiresAt, expiresAtDisplay, priority}`. The title and message are fixed generic Arabic text (`ManagerAnnouncementGenericResponse.java:32-48`).
- **Announcements are not line-targeted.** `lineId` is only the ack identity. `pending` excludes notices this `lineId` has already acked (`RollManagerAnnouncementRepository.java:69-88`), and the ack key is `line:<lineId>` (`RollManagerAnnouncementService.java:437`).
- `lineId` is not validated.
- Unknown announcement id on ack → `404 ROLL_ANNOUNCEMENT_NOT_FOUND` (`RollManagerAnnouncementService.java:479-485`).
- No notices → `"data": []`. Successful ack → `{"success":true}`.

#### 4.2.12 V190 close-request endpoints (reference only)

- `GET /lines/{lineId}/plan-item-close-request`, `POST /lines/{lineId}/plan-item-close-requests/{closeRequestId}/more-pallets-remain`, and `POST …/confirm-all-pallets-registered` (`PalletizingPlanItemCloseRequestController.java:39,47,57`).
- They need the extra header `X-Palletizer-Session-Token` (`:34`).
- Path `lineId` is the ProductionLine id. The response `thermoformingLineId` is the **TF id (4 for LINE_3)**; display it only, never use it as a key.
- Full contract: companion handoff.

#### 4.2.13 Not used by this app (do not add)

- `GET /api/v1/palletizing-line/lines/{lineId}/operator-dashboard/events` (event `operator-dashboard-changed`, `OperatorDashboardSseBroker.java:74`). It accepts any id without validation; a TF id silently gets an empty stream.
- `GET /api/v1/palletizing-line/events` (`PalletizingLineEventsController.java:46-48`, `ProductionPlanSseBroker`).
- Client paths `/palletizing/operators|product-types|production-lines` (`palletizing_repository_impl.dart:43-59`): there is **no backend controller** at `/api/v1/palletizing`. Never use them for the line list.

### 4.3 Error codes

These are the codes this app can meet on line-scoped paths. The **Arabic** column is the text the app must show; the backend message is English and must not be displayed.

| Code | HTTP | When | User meaning | Recoverable? | UI pattern | Arabic message |
|---|---|---|---|---|---|---|
| `PRODUCTION_LINE_INACTIVE` | 400 | palletizer-auth, create pallet, print-attempt, first-pallet-context on a switched-off line (`PalletizerSessionService.java:104-110`, `LineProductionGuard.java:56-62`) | Management switched this line off | Not by the worker | Close any dialog on that line. Silently re-fetch bootstrap (the tab disappears). Show a notice. | `{label} غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.` |
| `PRODUCTION_LINE_NOT_FOUND` | 404 | stale or unknown `lineId` (`LineStateService.java:93-98`, `LineProductionGuard.java:49-54`, `PalletizerSessionService.java:97-102`) | The app's line list is out of date | Yes | Silent bootstrap re-fetch; notice if the user was acting | `خط الإنتاج غير موجود. تم تحديث قائمة الخطوط.` |
| `THERMOFORMING_LINE_MAPPING_NOT_FOUND` | 404 | no active machine is mapped to this palletizing line (`ThermoformingLineOperationalGuard.java:48-53,61-67`). Checked **before** the active flag on auth and writes. | Configuration problem | No (admin) | Blocking card on that tab + Refresh button | `لا توجد ماكينة تشكيل مفعّلة مرتبطة بهذا الخط. راجع الإدارة.` |
| `THERMOFORMING_LINE_PAUSED` | 409 | machine paused by management (`ThermoformingLineOperationalGuard.java:118-124`). Wins over `PRODUCTION_LINE_INACTIVE`. | Machine is paused | Wait | Inline error + refresh the line | `الماكينة متوقفة مؤقتاً من الإدارة.` |
| `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` | 409 | PIN login before the operator has claimed the machine (`PalletizerSessionService.java:116-123`) | Waiting for the operator | Yes, after the claim | Keep the PIN screen; show the message | `بانتظار بدء المناوبة من المشغّل` (existing, `api_exception.dart:158-159`) |
| `OPERATOR_PIN_INVALID` | **401** | wrong or locked PIN (`OperatorPinService.java:159-163`) | Wrong PIN | Yes | Clear the PIN field, shake, keep the screen | `رمز المشغل غير صحيح` (existing) |
| `INVALID_PIN_FORMAT` | 400 | PIN is not 4 digits | Format | Yes | Inline | `صيغة الرمز غير صحيحة. يجب أن يكون 4 أرقام` (existing) |
| `PALLETIZER_NOT_ALLOWED` | **403** | operator cannot stack pallets (`PalletizerSessionService.java:131-137`) | Not permitted | No (admin) | Inline on the PIN screen | `هذا الموظف غير مصرح له بتسجيل الطبليات` (existing) |
| `LINE_NOT_AUTHORIZED` | **403** | no operator authorization on the line (`LineAuthorizationService.java:88-94`) | Operator has not claimed the line | Yes, after the claim | Refresh line state; the waiting card shows | `لا يوجد مشغل مصرح على هذا الخط` (existing) |
| `LINE_BLOCKED_BY_PENDING_HANDOVER` | 409 | pending handover (`LineHandoverGuardSupport.java:26-31`) | Handover in progress | Wait | Refresh line state | `الخط محظور بسبب تسليم معلق` (existing) |
| `PALLETIZER_SESSION_REQUIRED` | 409 (create) / 404 (current, logout) / 403 (logout on another line) / 400 (blank) | `PalletizingService.java:181-187`, `PalletizerSessionController.java:49-54`, `PalletizerSessionService.java:223-254` | Palletizer is not logged in on this line | Yes | Drop to the PIN screen for **that line only** | `انتهت جلسة موظف الطبليات، يرجى تسجيل الدخول مجددًا` (existing) |
| `PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED` | 400 | `expectedPlanItemId` missing (`ThermoformingProductionPlanGuard.java:96-102`) | App bug | — | Should never happen; log it | `تعذّر تحديد بند الإنتاج. حدّث الخط ثم حاول مجدداً.` |
| `PRODUCTION_PLAN_CURRENT_ITEM_CHANGED` | 409 | item changed in flight (`:103-115`) | Plan moved on | Yes, **never auto-retry** | Refresh the line; ask the worker to check the product | see companion handoff §14 |
| `PRODUCTION_PLAN_ITEM_CLOSED` / `PRODUCTION_PLAN_PRODUCT_MISMATCH` / `PRODUCTION_PLAN_TARGET_EXCEEDED_CONFIRMATION_REQUIRED` | 409 | `:121-150` | unchanged | — | unchanged (existing mappings `api_exception.dart:186-191`) | existing |
| `AUTH_INVALID_CREDENTIALS` | 401 | missing or wrong `X-Device-Key` (`SecurityAuthEntryPoint.java:28-29`) | Device key problem | Admin/settings | Existing device-key screen | `مفتاح الجهاز غير صحيح أو غير مفعّل` (existing) |
| `FORBIDDEN` | 403 | security layer denied (`SecurityAccessDeniedHandler.java:28-29`) | Device key problem | Admin/settings | Existing device-key screen | same |
| `VALIDATION_ERROR` | 400 | bean validation (`GlobalExceptionHandler.java:63-78`) | App bug | — | Log; generic error | existing |
| `ROLL_ANNOUNCEMENT_NOT_FOUND` | 404 | ack for a deleted notice (`RollManagerAnnouncementService.java:479-485`) | Notice is gone | Yes | Drop it locally; re-fetch pending | (silent) |

> **Client defect to fix alongside.** The app maps **any** 401 or 403 on `/palletizing-line/` to its own `DEVICE_KEY_INVALID` (`lib/data/datasources/api_client.dart:45-46,243-246`). The table above shows four **business** 401/403 codes on this chain. With that mapping, a wrong PIN on 'خط ج' shows "مفتاح الجهاز غير صحيح" instead of "رمز المشغل غير صحيح". See §6.1 row 27.

### 4.4 SSE / polling / refresh contract

**Stream:** `GET /api/v1/palletizing-line/app-events`

- Header `X-Device-Key` (`PalletizingAppLineEventsController.java:34-42`). No PIN and no session are required.
- **One global stream for all lines.**
- Emitter timeout is 5 minutes (`PalletizingAppLineEventsSseBroker.java:100`). The client must reconnect.
- Heartbeat is an SSE comment `ping` every 25 s (`:350`, `SseInfrastructureProperties.java:30`).

**Event names on this stream (complete list)**

| `event:` | Data | Source |
|---|---|---|
| `connected` | `{"status":"connected"}` | `PalletizingAppLineEventsSseBroker.java:106,173-175` |
| `palletizing-lines-changed` | refresh-trigger JSON (below) | `:103,327` |

**This stream carries nothing else.** In particular it never carries `urgent-manager-announcement`; the backend sends that event only on `/api/v1/palletizing-line/events` (`ProductionPlanSseBroker.java:87,258-300`).

**`palletizing-lines-changed` payload** (`PalletizingAppLineEventsSseBroker.java:401-414`):

| Key | Type | Meaning |
|---|---|---|
| `type` | String | always `"LINE_STATE_CHANGED"` (`:109`) |
| `reason` | String | hint only; list below. **Unknown values must be handled like any other.** |
| `palletizingLineId` | Long | ProductionLine id. **The only routing key.** |
| `version` | long | per-line, in-memory counter that restarts at 1 after a backend restart. Ordering hint only. |
| `eventId` | String (UUID) | dedupe key; the backend already dedupes the last 64 (`:112,376-390`) |
| `occurredAt` | ISO-8601 UTC `…Z` | display or logging only |
| `thermoformingLineId` | Long, **optional** | TF id. Present only on `LINE_TAKEOVER_*` and `PLAN_ITEM_CLOSE_*` frames (`:265-266,305-306`). **Never use it as a key.** |

**Reasons you can receive**

- Pass-through of `OperatorDashboardChangedEvent.Reason` (`OperatorDashboardChangedEvent.java:72-162`): `PALLET_CREATED`, `PALLET_QUANTITY_UPDATED`, `PALLET_VOIDED`, `ROLL_CONSUMED`, `ROLL_MOUNTED`, `PALLETIZING_EMPLOYEE_CHANGED`, `ROLLS_EMPLOYEE_CHANGED`, `PRODUCT_CHANGED`, `FALET_CHANGED`, `HANDOVER_CHANGED`, `SESSION_CHANGED`, `ROLL_CONSUMPTION_SEGMENT_RECORDED`, `ROLL_CONTINUED_WITH_NEW_PRODUCT`, `ROLL_RETURNED_REMAINING`, `MACHINE_ROLL_STATE_UPDATED`, **`LINE_STATE_CHANGED`**, `OPERATOR_SESSION_ENDED`, `HANDOVER_CHECKLIST_CHANGED`.
- `LINE_TAKEOVER_*` from `LineTakeoverEventType.java:11-53`: `REQUESTED`, `ACCEPTED`, `REJECTED`, `TIMEOUT_AUTO_RELEASED`, `POST_ACCEPT_TIMEOUT_AUTO_RELEASED`, `HANDOVER_SUBMITTED`, `COMPLETED`, `RESERVATION_EXPIRED`, `CANCELLED`.
- `PLAN_ITEM_CLOSE_REQUESTED`, `PLAN_ITEM_CLOSE_PALLETIZER_COMPLETING_PALLETS`, `PLAN_ITEM_CLOSE_CONFIRMED`, `PLAN_ITEM_CLOSE_REQUEST_CANCELLED`, `PLAN_ITEM_CLOSE_REQUEST_INVALIDATED` (`ThermoformingPlanItemCloseRequestChangedEvent.java:25-29`).

**How enable and disable reach you**

1. `ProductionLineAdminService.toggleActive` or `update` publishes `LineStateChangedEvent(plId)` only when the active flag changes (`ProductionLineAdminService.java:113,130-132,139,152-154,169-171`).
2. After commit, `OperatorDashboardLegacyFallbackListener` turns it into an `OperatorDashboardChangedEvent` with reason `LINE_STATE_CHANGED` (`OperatorDashboardLegacyFallbackListener.java:64-88`).
3. The broker forwards it (`PalletizingAppLineEventsSseBroker.java:191-228`, `fallbackExecution = true`).

LINE_3 enable, as received:

```
event: palletizing-lines-changed
data: {"type":"LINE_STATE_CHANGED","reason":"LINE_STATE_CHANGED","palletizingLineId":3,"version":1,"eventId":"5c0f2b7e-4c1a-4a3b-9d7e-2f1b6c9a0e11","occurredAt":"2026-09-15T05:00:02.431Z"}
```

**A disable produces the identical frame.** Nothing in the payload says "enabled", "disabled" or "list changed". Only a bootstrap re-fetch tells you.

- **Creating** a production line (`ProductionLineAdminService.java:55-81`) or **renaming** one without changing its flag publishes **no** event.

LINE_3 takeover, showing the id skew:

```
event: palletizing-lines-changed
data: {"type":"LINE_STATE_CHANGED","reason":"LINE_TAKEOVER_REQUESTED","palletizingLineId":3,"version":7,"eventId":"…","occurredAt":"…Z","thermoformingLineId":4}
```

**What the app must re-fetch** (required behaviour; today's code does not do this, see §6.1)

| Trigger | Required action |
|---|---|
| Frame whose `palletizingLineId` is **not** a rendered line | **Re-fetch bootstrap** (silent, debounced). This is how an enabled line appears. |
| Frame with `reason == "LINE_STATE_CHANGED"` (also used for enable and disable of a rendered line) | **Re-fetch bootstrap** (silent). It supersedes the per-line `/state` for all lines. |
| Any other frame for a rendered line | Refresh that line's `/state`. Re-fetching bootstrap instead is also acceptable and simpler; it costs one line-state build per active line. See §7. |
| `PLAN_ITEM_CLOSE_*` for a rendered line | Additionally follow companion handoff §6 |
| `connected` (every (re)connect) | **Re-fetch bootstrap** (frames may have been missed; the broker is in-memory and single-instance) |
| App resume | **Re-fetch bootstrap** |
| Periodic safety poll (SSE up, nothing urgent; today 50 s, `palletizing_provider.dart:73`) | **Re-fetch bootstrap** at least at this cadence, so a missed enable or disable frame is recovered |
| Urgent / fallback cadence (6 s / 12 s) | Poll `/state` for **rendered lines only**; still re-bootstrap at the safety cadence |
| Pull-to-refresh / Refresh button | Re-fetch bootstrap |

Debounce about 250 ms and dedupe by `eventId`; the existing `RefreshCoordinator` already does both (`refresh_coordinator.dart:128-154`). Coalesce concurrent bootstrap requests into one in-flight call.

### 4.5 Staged behaviour: before enable vs after enable

| Aspect | LINE_3 inactive (after deploy, before go-live) | LINE_3 active (after admin enables) |
|---|---|---|
| `GET /bootstrap` `lines[]` | `lineNumber` 1, 2 | `lineNumber` 1, 2, **3** (`lineId` 3 expected in production, `lineName`/`lineDisplayName` 'خط ج') |
| Tabs / panes (updated build) | 2 | **3**, right-to-left: خط أ · خط ب · خط ج |
| Lines polled / announcements fetched (updated build) | 1, 2 | 1, 2, 3 |
| `GET /lines/3/state` | `200` if called (no active check); the app must not call it | `200`: waiting for operator until the machine is claimed |
| `POST /lines/3/palletizer-auth` | `400 PRODUCTION_LINE_INACTIVE` (or `409 THERMOFORMING_LINE_PAUSED` if TF_LINE_3 is paused) | `409 NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` until the operator claims TF_LINE_3, then `200` |
| `POST /lines/3/pallets` | `400 PRODUCTION_LINE_INACTIVE` | normal guards: `403 LINE_NOT_AUTHORIZED` → `409 PALLETIZER_SESSION_REQUIRED` → plan checks → `201` |
| `GET /lines/3/first-pallet-context` | `400 PRODUCTION_LINE_INACTIVE` | normal |
| SSE frames with `palletizingLineId: 3` | Possible, for example from machine pause-schedule publishers (`ThermoformingPauseScheduleRefreshPublisher.java:131`). Bootstrap re-fetch yields no change. | Normal traffic. The enable itself is one `LINE_STATE_CHANGED` frame. |
| Line 3 right after enable | — | `waitingForOperator: true`. `productionPlanBlocked: true` / `NO_PLAN_ITEM` if no 'خط ج' plan item exists yet. |
| Current build `b936b3d6` (for reference) | No visible change (but V190 breaks pallet creation on every line, §8) | Line 3 never drawn. Polled at 6 s urgent cadence. Takeover sound with no dialog. Label letter 'B'. |
| Disable after go-live | — | Frame `LINE_STATE_CHANGED`, `palletizingLineId: 3`. Bootstrap drops line 3. Writes on 3 get `400 PRODUCTION_LINE_INACTIVE`. `/state`, `/falet`, `/session-production-detail` on 3 still return `200`. The palletizer session is **not** ended by the disable. |

---

## 5. IMPLEMENTED IN THIS TASK

**Backend changes relevant to this app** (uncommitted, in the working tree at `e47c2c15`)

| Change | File | Effect on Palletizing App |
|---|---|---|
| V191 provisions LINE_3 'خط ج' (`line_number` 3, **inactive**) and TF_LINE_3 → LINE_3, by business code | `src/main/java/db/migration/V191__provision_three_line_thermoforming_topology.java` (untracked) | Nothing visible until an admin enables LINE_3; then a third bootstrap entry |
| Enable/disable (and update when the flag flips) publishes `LineStateChangedEvent` | `ProductionLineAdminService.java:113,130-132,139,152-154,169-171` | New `palletizing-lines-changed` frame at go-live and rollback |
| `hasDependencies` checks mapped machines first | `ProductionLineAdminService.java:197+` | None (admin only). LINE_3 is never deletable once TF_LINE_3 exists. |
| Client fallback label rule now covers 3+ (javadoc only) | `palletizing/dto/LineStateResponse.java:18-33` | Documents the ordinal rule in §4.2.1 |
| Dev and H2 seeding: LINE_3 'خط ج' inactive; TF_LINE_1/2/3 'خط التشغيل أ/ب/ج' | `config/DataSeeder.java:195-213,239-241` | Dev environments get the same topology |

**Additive-only statement.** For `/api/v1/palletizing-line/**` the LINE_3 work added or removed **no** endpoint, request field, response field, enum value, error code or SSE event name. The only new observable behaviour for this app:

- a third `lines[]` entry once LINE_3 is active;
- a `palletizing-lines-changed` frame when a line's active flag flips.

**What did NOT change (verified untouched by the LINE_3 work)**

- `PalletizingBootstrapService`: same query, not in the diff.
- `LineStateService` and the `LineStateResponse` fields: only javadoc changed.
- `LineProductionGuard`, `ThermoformingLineOperationalGuard`, `PalletizingAppLineEventsSseBroker` line-state and takeover listeners, `DeviceApiKeyFilter`, `SecurityConfig` device chain, urgent-announcement endpoints, and `PRODUCTION_LINE_INACTIVE` (already existed).
- The modifications in `PalletizingLineController`, `PalletizingService`, `CreatePalletLineRequest`, `PalletizerSessionService`, `PalletizingAppLineEventsSseBroker` (close-request listener) and `ErrorCode` belong to **owner WIP V190**. They are covered by the companion handoff, not by LINE_3.

---

## 6. FRONTEND MUST VERIFY

> Everything in this section is a **candidate site** read from the Flutter source (HEAD `b936b3d6` + dirty WC). It is not proof of runtime behaviour. Verify each before changing it.

### 6.1 Candidate code sites in the Flutter repo

| # | File:line | What it does today | Why it breaks LINE_3 | Required change | Severity |
|---|---|---|---|---|---|
| 1 | `lib/core/constants.dart:3-42` | `enum ProductionLine { line1, line2 }` with `color`, `lightColor`, `arabicLabel`, `number` | Line 3 cannot be represented. Every per-line widget takes this enum. | Replace with a runtime line model built from bootstrap (`lineId`, `lineNumber`, resolved label, accent). Keep a colour palette indexed by `lineNumber` (or render position); no labels from the enum. | BLOCKER |
| 2 | `lib/presentation/screens/palletizing_screen.dart:44-45` | `TabController(length: 2)` created once in `initState` | Only 2 tabs | Length = number of rendered lines. Recreate the controller when the count changes; keep the selected tab by `lineId`. | BLOCKER |
| 3 | `palletizing_screen.dart:68-87` | `for (final n in const [1, 2])` → `TakeoverDialog(lineNumber: n)` | A line-3 takeover never opens a dialog, though the sound plays | Iterate rendered lines in server order; key the dialog by `lineId` | BLOCKER |
| 4 | `palletizing_screen.dart:194-204` | `activeLineNumber = _activeTabIndex == 1 ? 2 : 1`; app-bar colour ternary | Tab index 2 maps to line 1 | Use the selected rendered line | BLOCKER |
| 5 | `palletizing_screen.dart:245-286` | Two literal tabs 'ماكنة 1' / 'ماكنة 2' | No third tab; labels are not the server names | One tab per rendered line, labelled with the resolved label (§4.2.1). `isScrollable` only when N > 3. | BLOCKER |
| 6 | `palletizing_screen.dart:535-548`; `lib/presentation/widgets/shimmer/palletizing_shimmer.dart:296-310` | Loading skeleton with two `TabBarView` children / `PalletizingShimmerDualPane` | Skeleton disagrees with a 3-line layout | Skeleton count = last known rendered count (2 on first ever launch) | LOW |
| 7 | `palletizing_screen.dart:602-607` | `productionLines.where((l) => l.lineNumber == 1)` / `== 2` | Drops line 3 | Iterate the rendered list | BLOCKER |
| 8 | `palletizing_screen.dart:609-616,636-653` | "switch line" jumps to the *other* tab | Assumes exactly 2 | Offer the next usable line (active or needs-PIN) in server order; hide the button if none | MEDIUM |
| 9 | `palletizing_screen.dart:625-690` | `TabBarView` with 2 children / `Row` with 2 `Expanded` panes | Only 2 | N children / N panes (§6.7) | BLOCKER |
| 10 | `palletizing_screen.dart:169-171`; `lib/core/responsive.dart:3-6` | Tabs when width < 1200 dp, dual pane otherwise | 3 panes at 1200 dp are ~400 dp each | Use panes only when `width / N ≥` minimum pane width (§6.7), otherwise tabs | MEDIUM |
| 11 | `lib/presentation/providers/palletizing_provider.dart:128-153,165,177` | ~20 per-line maps keyed by `lineNumber` ("keyed by UI lineNumber: 1, 2") | `line_number` is not unique in the DB; the key must survive renumbering | Key every per-line map by **`lineId`** | HIGH |
| 12 | `palletizing_provider.dart:463-468,581-590` | `getLineIdForNumber` falls back to stale `_lineStates` | Resolves ids for lines no longer in bootstrap | Delete once maps are keyed by `lineId` | HIGH |
| 13 | `palletizing_provider.dart:475-479` | `knownOperatingLineIds` = union of cached and bootstrap lines → announcements notifier (`lib/main.dart:59`) | Fetches and acks announcements for lines not drawn | Return **rendered** ids only | MEDIUM |
| 14 | `palletizing_provider.dart:488-491` | `_allLineNumbers` = cached `_lineStates.keys` ∪ bootstrap | A disabled line stays in the set forever | Rendered ids only; prune on every bootstrap | BLOCKER |
| 15 | `palletizing_provider.dart:533,539-544` (HEAD :532) | Urgent cadence over all known lines | A hidden or removed line forces the 6 s poll | Rendered lines only | BLOCKER |
| 16 | `palletizing_provider.dart:564-577` (HEAD :567) | `refreshFromSseEvent` refreshes `/state` for a known id; an unknown id → `pollLineMonitoring()`; "Never calls loadBootstrap" | An enabled line never appears; a disabled line never disappears | Re-fetch bootstrap per §4.4 (silent; no shimmer) | BLOCKER |
| 17 | `palletizing_provider.dart:618-631` | `loadBootstrap` sets `loading` (shimmer), replaces `_productionLines`, hydrates by `lineNumber`, **never prunes** | A full-screen shimmer on every SSE-driven reload; stale lines kept | Add a silent bootstrap refresh that diffs by `lineId`, adds or removes lines, prunes their state, keeps selection | BLOCKER |
| 18 | `palletizing_provider.dart:836-851` (HEAD :848) | `_applyTakeoverState` plays the alert for any hydrated line | Rings for lines not drawn | Only for rendered lines; prune `_pendingDialogLines` with the line | HIGH |
| 19 | `palletizing_provider.dart:1079-1102`; `lib/data/repositories/palletizing_repository_impl.dart:149-153` (HEAD :139-150) | `createPallet` / `createLinePallet` send `productTypeId`, `quantity`, `confirmOverproduction`, optional FALET block — **no `expectedPlanItemId`** | V190: every pallet on **every** line → `400 PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED` | Send `expectedPlanItemId = currentPlanItemId` of that line's latest state (companion handoff §14) | BLOCKER (release) |
| 20 | `palletizing_provider.dart:1270-1283` (HEAD :1257) | `pollLineMonitoring` over `_allLineNumbers` | Polls hidden or removed lines | Rendered lines only | BLOCKER |
| 21 | `lib/data/models/bootstrap_response_model.dart:20-21,48-69` | Reads a non-existent `productionLines` field, then backfills `name: 'خط ${lineNumber}'` (numeric) and `code: 'L${lineNumber}'` | Numeric fallback breaks the documented abjad rule; fabricated code looks like a business code | Build the line list directly from `lines` (server order). Drop the fabricated code. Apply the §4.2.1 label rule. | HIGH |
| 22 | `bootstrap_response_model.dart:165-168` | Parses `lineId`, `lineNumber`, `lineName`. **`lineDisplayName` is not parsed.** | Label source #1 ignored | Parse `lineDisplayName` (nullable String) | HIGH |
| 23 | `lib/domain/entities/pallet_label_content.dart:67-68` (untracked WC); HEAD `pallet_success_dialog.dart:392`, `reprint_by_id_dialog.dart:149,467`, `session_drilldown_dialog.dart:535` | Side band `lineNumber == 1 ? 'A' : 'B'` | Line 3 prints **'B'** | Latin letter from `lineNumber`: 1→A, 2→B, **3→C**, the same derivation as `ThermoformingMachineNameResolver.java:37` (`'A' + lineNumber - 1`). **Owner must confirm 'C' is the wanted print text (§7).** | BLOCKER |
| 24 | `lib/presentation/widgets/reprint_by_id_dialog.dart:236-247` (WC); HEAD `:67` `for (final lineNumber in [1, 2])` | WC resolves the pallet's line from bootstrap by `productionLineId`; falls back to `productionLineName` when not found | A line-3 pallet reprinted while LINE_3 is not in bootstrap prints 'خط ج' instead of 'C'; the payload has no `lineNumber` (§4.2.10) | Accept, or cache last-known `lineId → lineNumber`; confirm with the owner | LOW |
| 25 | `lib/presentation/widgets/production_line_section.dart:189`; `create_pallet_dialog.dart:55-65`; `summary_card.dart:26-31` | Label = entity `name` (`lineName`), else enum `arabicLabel` | No enum label for line 3; ignores `lineDisplayName` | Use the resolved label | HIGH |
| 26 | `thermoforming_waiting_card.dart:167`; `line_blocked_card.dart:148`; `takeover_dialog.dart:23,96` | `'ماكنة ${line.number}'` | Shows 'ماكنة 3' next to the server 'خط ج'; mixed naming | Show the resolved label | MEDIUM |
| 27 | `lib/data/datasources/api_client.dart:45-46,243-246` | Any 401/403 on a `/palletizing-line/` path → `DEVICE_KEY_INVALID` | Business 401/403 (`OPERATOR_PIN_INVALID`, `PALLETIZER_NOT_ALLOWED`, `LINE_NOT_AUTHORIZED`, `PALLETIZER_SESSION_REQUIRED`) show the device-key message. This is hit during the LINE_3 checkpoint PIN login. | Parse `error.code` first; only `AUTH_INVALID_CREDENTIALS` (401) or `FORBIDDEN` (403) mean a device-key problem | HIGH (pre-existing) |
| 28 | `lib/core/services/sse_client.dart:30,49-51`; `lib/core/di.dart:37-40` | Single stream `/palletizing-line/app-events`; also listens for `urgent-manager-announcement` | The backend never sends that event on `app-events` (§4.4). The nudge never fires; notices arrive only via fetch on bootstrap, resume or reconnect (`manager_announcement_notifier.dart:82-116`). | Not a LINE_3 blocker. Owner decision: accept, or also subscribe to `/palletizing-line/events` for the nudge. | LOW (pre-existing) |
| 29 | `lib/core/services/refresh_coordinator.dart:84-90,114-120` | Resume and `connected` → `_onEventRefresh(null)` → per-line polling only | A missed enable or disable frame is never recovered | Resume and `connected` → silent bootstrap re-fetch | BLOCKER |
| 30 | `palletizer_pin_screen.dart:57,69,71,191`; `falet_screen.dart:34,42-43,63`; `legacy_handover_info_card.dart:30`; `line_context_strip.dart:23-31,342`; `session_drilldown_dialog.dart:56,528,539`; `takeover_banner.dart:32,112`; `production_line_section.dart:50,151-153,233-285,367-574,616,713` | All call the provider with `line.number` | Tied to the enum and `lineNumber` keys | Pass the line model / `lineId` | BLOCKER (mechanical) |
| 31 | `lib/data/repositories/palletizing_repository_impl.dart:43-59` | Legacy `/palletizing/operators`, `/palletizing/product-types`, `/palletizing/production-lines` | No backend controller at `/api/v1/palletizing` | Do not use for the line list; delete if unused | LOW |
| 32 | `lib/data/datasources/auth_local_storage.dart:100-103` | Palletizer token key `palletizer_session_token_$lineId` | Already correct (keyed by `lineId`) | Keep | OK |
| 33 | Tests: `test/adaptive_polling_test.dart`, `no_operator_overlay_test.dart`, `pallet_label_content_test.dart`, `pallet_label_print_pipeline_test.dart`, `plan_product_enforcement_test.dart` | Fixtures use `lineNumber` 1/2 or `ProductionLine.line1` | Will not compile or cover 3 lines after the refactor | Update per §6.10 | — |

### 6.2 Required screens / dialogs

| Screen / dialog | Trigger | Title / content | Fields | Buttons | Loading / success / error |
|---|---|---|---|---|---|
| **Main screen — N line tabs** (narrow tablet / portrait) | Bootstrap loaded | App bar 'تكوين طبليات' (existing). One tab per rendered line with the resolved label (for example 'خط ج'). A tab dot shows attention state (waiting / takeover / blocked). | — | Refresh 'تحديث', Reprint 'إعادة طباعة ملصق', Settings 'الإعدادات' (existing) | Loading: skeleton × last known N. Error: existing retry surface. 0 lines: existing 'لا توجد خطوط إنتاج متاحة'. Device key: existing surface. |
| **Main screen — N panes** (wide tablet / landscape) | Same, when §6.7 width rule passes | N panes side by side; each pane header shows the resolved label | — | same | same |
| **Line switched off notice** | A rendered line disappears from a bootstrap re-fetch, **or** a write on it returns `PRODUCTION_LINE_INACTIVE` | Title 'تم إيقاف الخط'. Body '{label} غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.' | — | 'حسناً' | If the user was on that tab or had a dialog open for it: close its dialogs, show this dialog, then select the first rendered tab. Otherwise show a snackbar with the same body. |
| **New line available** (optional, recommended) | A new `lineId` appears in bootstrap | Snackbar 'تمت إضافة {label}' | — | — | Do not auto-switch tabs |
| **Takeover dialog** (existing, generalised) | Pending takeover on a rendered line | Existing texts; subtitle = resolved label (not 'ماكنة n') | — | existing 'حسناً' | One dialog at a time, lines in server order |
| **Waiting for operator card** (existing) | `waitingForOperator == true` | Title `waitingForOperatorMessageTitle`, body `waitingForOperatorMessage` from the server; line name = resolved label | — | 'تغيير الخط' only if another usable line exists | — |
| **Palletizer PIN screen** (existing) | Line authorized, no palletizer session | Shows the resolved label | 4-digit PIN (numeric pad) | existing | Errors per §4.3; `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` → 'بانتظار بدء المناوبة من المشغّل' |
| **Create pallet dialog** (existing) | 'إنشاء طبلية جديدة' | Title uses the resolved label | Quantity (defaults from `currentPlanItemPackagesPerPallet`) | existing | Sends `expectedPlanItemId`. On `PRODUCTION_LINE_INACTIVE` → close + "line switched off" notice. |
| **Success / print** (existing) | `201` | Label side band letter from `lineNumber` (3 → 'C', pending owner confirmation) | — | existing | — |

### 6.3 Models / DTOs

**`PalletizingLine`** (new client model, one per bootstrap `lines[]` entry, in server order)

| Field | Type | Nullable | Source | Notes |
|---|---|---|---|---|
| `lineId` | int | no | `lineId` | **Primary key** for maps, selection, tokens, paths, announcement `lineId` |
| `lineNumber` | int | no | `lineNumber` | Ordinal label fallback, print letter, colour index. **Not a key.** |
| `lineName` | String | yes (treat blank as null) | `lineName` | Label fallback #2 |
| `lineDisplayName` | String | yes (treat blank as null) | `lineDisplayName` | Label source #1 |
| `label` | String | no | computed | `lineDisplayName` → `lineName` → abjad ordinal from `lineNumber` (1..8) → `'خط $lineNumber'` |
| `state` | `BootstrapLineState` | no | the same entry | Existing model; add `lineDisplayName` |

**Fields that must NOT be used as keys or labels**

| Field | Why |
|---|---|
| `thermoformingLineId` (SSE, close request) | TF id: **4** for LINE_3, not 3 |
| `authorization.lineName` | Snapshot taken when the authorization opened (`LineAuthorizationService.java:116`); stale after a rename |
| `palletizingLineName` (palletizer auth/session) | Fine to display in session context; not the tab label source |
| fabricated `code` (`'L${lineNumber}'`) | Not a backend value |
| `version` (SSE) | In-memory counter; resets on backend restart |
| list index / tab index | Changes when a line is added or removed |
| `lineNumber` as a map key | Not unique in the DB |
| `productionLineName` (label payload) | Pallet's origin snapshot, not the current tab |

**Nullability reminders** (server omits nulls)

- `currentPlanItemId`, `currentPlanItemProductTypeId`, `currentPlanItemProductName`, `currentPlanItemPackagesPerPallet`: absent when there is no plan item.
- `authorization`, `pendingTakeoverRequest`, `blockedReason`, `waitingForOperator*` texts, `productionPlanBlocked*` texts: absent when not applicable.
- `sessionTable` is `[]`, not absent.

### 6.4 Repository / API client changes

1. `bootstrap()`
   - Return the lines in server order from `data.lines`.
   - Parse `lineDisplayName`.
   - Stop depending on `data.productionLines`.
   - Remove the `'خط ${n}'` numeric fallback and the fabricated `code`.
2. `createLinePallet({required int lineId, …, required int expectedPlanItemId})`: always send `expectedPlanItemId` (companion handoff).
3. `getLineState(lineId)`, `palletizerAuth`, `getCurrentPalletizerSession`, `palletizerLogout`, `getFirstPalletContext`, `getFaletItems`, `checkFaletExists`, `getSessionProductionDetail`, `logLinePrintAttempt`, announcements: keep the signatures; they already take the backend `lineId`. Callers must pass the `lineId` of a **rendered** line.
4. `api_client.dart` error classification: read `error.code` before the 401/403 device-key shortcut (§6.1 row 27).
5. Add `ApiException.displayMessage` mappings: `THERMOFORMING_LINE_MAPPING_NOT_FOUND`, `THERMOFORMING_LINE_PAUSED`, `PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED`, `PRODUCTION_PLAN_CURRENT_ITEM_CHANGED`. Change `PRODUCTION_LINE_INACTIVE` to include the line label where the caller knows it (§6.8).
6. No new endpoint. SSE path unchanged (`/palletizing-line/app-events`).

### 6.5 Provider / state changes

- **`renderedLines`** (`List<PalletizingLine>`): the last successful bootstrap, **server order**. It is the only source for tabs, panes, polling, takeover dialogs, announcements `lineIds`, and the "switch line" target.
- **Key all per-line state by `lineId`.** On each bootstrap:
  - add new ids;
  - **remove ids that disappeared** from every map (`_lineStates`, sessions, session tables, plan products, last pallet, errors, UI modes, FALET, takeovers, blocked flags, seq counters, session gate, `_pendingDialogLines`);
  - keep stored palletizer tokens: they are harmless and re-validated by `/palletizer-session/current` if the line comes back.
- **`refreshBootstrap({bool silent = true})`**
  - No loading state and no shimmer.
  - Single-flight: callers during an in-flight call join it.
  - Sequence-guarded, like `_lineStateSeq`, so an older response never overwrites a newer one.
  - The existing `loadBootstrap()` with shimmer stays for first launch and the manual Refresh button.
- **SSE event handler** (replaces `refreshFromSseEvent`):

```
onFrame(f):                                  // after 250 ms debounce + eventId dedupe
  if f.palletizingLineId == null
     or !renderedIds.contains(f.palletizingLineId)
     or f.reason == "LINE_STATE_CHANGED":
       refreshBootstrap(silent)
  else:
       refreshLineState(f.palletizingLineId)  // or refreshBootstrap(silent)
  if f.reason startsWith "PLAN_ITEM_CLOSE_": follow companion handoff
onConnected / onResume / safety tick: refreshBootstrap(silent)
```

- **Poll cadence:** `hasAnyUrgentLineState` over rendered lines only. The urgent and fallback polls hit `/state` for rendered lines. The safety tick (50 s) re-bootstraps.
- **Selection:** store the selected `lineId`.
  - If it disappears, select the first rendered line and show the notice.
  - If a line is added, keep the current selection. The `TabController` index is derived from `lineId`.
- **Stale in-flight writes:** if a line is removed while a create-pallet request is in flight, show the response result (success dialog or error), then the notice. Never re-send.

### 6.6 UX flows

| Flow | Steps |
|---|---|
| **Go-live, happy path** | 1. Tablet shows 'خط أ', 'خط ب'. 2. Admin enables LINE_3. 3. Frame `LINE_STATE_CHANGED` / `palletizingLineId: 3` arrives. 4. Silent bootstrap. 5. Third tab 'خط ج' appears at the left end (RTL), selection unchanged, optional snackbar 'تمت إضافة خط ج'. 6. The 'خط ج' tab shows the waiting card (`بانتظار استلام الخط`). 7. Operator claims TF_LINE_3 in the Operator App → frame → the tab shows the PIN screen. 8. Palletizer enters PIN → `200`. 9. Worker creates a pallet → `201`, success dialog, label side band 'C'. |
| **Business error** | Map `error.code` → Arabic per §4.3. Line-scoped errors stay on that line's tab. `PRODUCTION_LINE_INACTIVE` / `PRODUCTION_LINE_NOT_FOUND` → silent bootstrap plus notice. `PRODUCTION_PLAN_CURRENT_ITEM_CHANGED` → refresh the line, no auto-retry. |
| **Network failure** | Keep the last rendered lines. Show the existing per-line error or snackbar; do not clear tabs. Retry cadence 8 s (existing); re-bootstrap on reconnect. |
| **Retry / double tap** | Disable 'إنشاء طبلية' and PIN submit while in flight (existing `_lineCreating`). Never re-submit a create automatically. Bootstrap refreshes are single-flight. |
| **Cancel / back** | Closing a create dialog sends nothing. Back on the main screen keeps the existing app behaviour. |
| **App resume** | Resume → silent bootstrap → prune or add lines → per-line session re-sync (existing). The announcement notifier re-fetches for rendered ids. |
| **Rollback (disable) while app is open** | Frame → silent bootstrap → 'خط ج' removed → if selected, show 'تم إيقاف الخط' then select 'خط أ'. |

### 6.7 Arabic RTL 3-line layout requirements

1. The app locale is Arabic (`lib/main.dart:71-72`), so layout is **RTL**: the first child renders on the **right**. Render lines in **server order** without reversing. Tabs and panes read right to left: **خط أ · خط ب · خط ج**.
2. **Tabs mode.**
   - Use a `TabBar` with one tab per line, equal width while N ≤ 3; set `isScrollable: true` only if N > 3.
   - Tab content: status dot + resolved label, Cairo bold (existing style, `palletizing_screen.dart:246-264`).
   - The label is never truncated.
3. **Panes mode.**
   - N `Expanded` panes with 2 dp dividers (existing style, `palletizing_screen.dart:661-690`).
   - Use panes only when `screenWidth / N ≥ minPaneWidth`. The proposed value is **420 dp**; validate it on the real tablet (§7). Otherwise use tabs.
   - With 3 lines, the current 1200 dp breakpoint (`responsive.dart:3-6`) alone is not enough.
4. **Touch targets.** Primary actions stay large (≥ 56 dp high, as today). Tabs ≥ 48 dp. PIN entry by numeric pad, no free typing.
5. **Colour.**
   - Lines 1 and 2 keep blue and green (`constants.dart:7-23`).
   - Add a third distinct accent plus light background for `lineNumber` 3, meeting contrast for white text. Choose a palette by `(lineNumber - 1) % palette.length`; never by `lineId`.
   - The neutral grey for waiting or blocked states stays (`palletizing_screen.dart:618-623`).
   - The app-bar colour follows the **selected** line.
6. **Attention on hidden tabs.** When a non-selected line is urgent (waiting, takeover, blocked, close request), its tab dot changes colour. The blocking takeover dialog still pops for any rendered line.
7. **Numbers and letters.** Arabic labels come from the server. The printed side band uses a Latin letter ('A', 'B', 'C') as today. Keep `textDirection` explicit on mixed Arabic/Latin label strings.

### 6.8 Arabic UI text

| Key / use | Arabic |
|---|---|
| Tab / pane / dialog line label | resolved label from the server, for example `خط ج` (no literal in code) |
| Ordinal fallback, `lineNumber` 1…8 | `خط أ` · `خط ب` · `خط ج` · `خط د` · `خط هـ` · `خط و` · `خط ز` · `خط ح` |
| Ordinal fallback, other `n` | `خط {n}` |
| Line switched off — title | `تم إيقاف الخط` |
| Line switched off — body / `PRODUCTION_LINE_INACTIVE` | `{label} غير مفعّل حالياً. لا يمكن تسجيل طبليات عليه.` |
| Line switched off — button | `حسناً` |
| New line appeared (optional snackbar) | `تمت إضافة {label}` |
| `PRODUCTION_LINE_NOT_FOUND` | `خط الإنتاج غير موجود. تم تحديث قائمة الخطوط.` |
| `THERMOFORMING_LINE_MAPPING_NOT_FOUND` | `لا توجد ماكينة تشكيل مفعّلة مرتبطة بهذا الخط. راجع الإدارة.` |
| `THERMOFORMING_LINE_PAUSED` | `الماكينة متوقفة مؤقتاً من الإدارة.` |
| `PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED` | `تعذّر تحديد بند الإنتاج. حدّث الخط ثم حاول مجدداً.` |
| Waiting for operator (server-provided) | `بانتظار استلام الخط` / `waitingForOperatorMessage` as sent |
| `NO_ACTIVE_THERMOFORMING_SHIFT_FOR_LINE` (existing) | `بانتظار بدء المناوبة من المشغّل` |
| `OPERATOR_PIN_INVALID` (existing) | `رمز المشغل غير صحيح` |
| Device key (existing, only for `AUTH_INVALID_CREDENTIALS` / `FORBIDDEN`) | `مفتاح الجهاز غير صحيح أو غير مفعّل` |
| No lines (existing) | `لا توجد خطوط إنتاج متاحة` |
| Refresh / retry (existing) | `تحديث` / `إعادة المحاولة` |
| Switch line (existing) | `تغيير الخط` |

### 6.9 Edge cases

| Case | Expected behaviour |
|---|---|
| **LINE_3 disabled mid-session** (palletizer logged in, dialog open) | Frame → silent bootstrap → line removed → close its dialogs → 'تم إيقاف الخط' → select the first line. A create already sent returns `201` or `400 PRODUCTION_LINE_INACTIVE` (never both). A print-attempt log for a just-created pallet may get `400`; it is swallowed as today (`palletizing_provider.dart:1176-1178`). The backend does **not** end the palletizer session or the operator claim on disable (no such code in `ProductionLineAdminService.toggleActive`). The runbook ends the shift first. |
| **Stale bootstrap** (frame missed, broker restarted, second backend instance) | Recovered on the next `connected`, resume or safety tick (≤ 50 s with SSE up). Never trust `/state` 200 as "still active" (§4.2.2). |
| **SSE missed during enable** | The line appears at the next bootstrap trigger (reconnect, resume, safety tick, manual refresh). Acceptance must still observe near-instant appearance with SSE up. |
| **Ids skewed** (PL 3 ↔ TF 4) | Paths and keys use `lineId` 3. Frames with `thermoformingLineId: 4` are routed by `palletizingLineId: 3` only. Close-request DTO `thermoformingLineId` 4 is display-only. |
| **Frame for a line that is not rendered** (inactive LINE_3, for example from a pause-schedule publisher) | Bootstrap re-fetch; still 2 lines; no UI change; no alert sound. |
| **Rename** of a line by an admin | No SSE frame (§4.4). The label updates on the next `/state` or bootstrap. Use the label from the **latest** state, not a value cached at startup. |
| **Duplicate `lineNumber`** (admin error) | Rendering and state still work, because keys are `lineId`. Order follows the server. Ordinal fallback and print letter could collide; log it. |
| **All lines disabled** | `lines: []` → existing 'لا توجد خطوط إنتاج متاحة' surface; keep SSE and safety bootstrap running so lines return automatically. |
| **Urgent announcement after LINE_3 appears** | Pending is filtered per `lineId`, so a notice this tablet already acked on lines 1 and 2 is **pending again for line 3** (`RollManagerAnnouncementRepository.java:69-88`). It shows once more. Acking acks every rendered line (existing notifier). Acceptable; mention in operator training. |
| **Reprint of a line-3 pallet while LINE_3 is not in bootstrap** | The payload has no `lineNumber` → the WC prints `productionLineName` ('خط ج') as the side band. Owner to confirm, or cache `lineId → lineNumber`. |
| **Paused TF_LINE_3** | Auth and writes return `409 THERMOFORMING_LINE_PAUSED` even if LINE_3 is also inactive (the pause check runs first). |
| **4th line later** | Nothing is hard-coded: tabs scroll when N > 3; panes fall back to tabs by the width rule; ordinal 4 → 'خط د'; print letter 'D'; colour palette wraps. The backend needs a new migration for the machine: V191 covers 3, and there is no admin UI to create `thermoforming_lines`. Creating a production line publishes **no** SSE frame; it appears at the next bootstrap trigger. |
| **Backend restart** | SSE `version` restarts at 1; ignore ordering by version. Reconnect → bootstrap. |

### 6.10 Testing requirements

**Unit tests**

- Label resolver:
  - `lineDisplayName` 'خط ج' wins;
  - blank display name → `lineName`;
  - both blank + `lineNumber` 3 → 'خط ج', 4 → 'خط د', 8 → 'خط ح', 9 → 'خط 9', 0 → 'خط 0';
  - `lineId` is never consulted (use `lineId: 11, lineNumber: 3`).
- Print letter: 1→A, 2→B, 3→C; no ternary.
- Bootstrap model: 3 entries parsed in server order; `lineDisplayName` parsed; no fabricated code; `lines: []`.

**Provider tests**

Use **skewed fixtures**: bootstrap `lineId`s 11, 12, 13 with `lineNumber` 1, 2, 3; SSE frames with `thermoformingLineId` 1, 2, 4.

- 2-line bootstrap then frame `{palletizingLineId: 13, reason: LINE_STATE_CHANGED}` → silent bootstrap called once → 3 rendered lines, no loading state.
- 3-line bootstrap then `LINE_STATE_CHANGED` for 13 with a bootstrap without 13 → line 13 pruned from every map; poll set = {11, 12}; urgent cadence ignores 13.
- Takeover pending on 13 → dialog signal for 13; after pruning → signal removed; no alert for a non-rendered id.
- `connected` and resume → bootstrap; safety tick → bootstrap.
- `knownOperatingLineIds` == rendered ids.
- `createPallet` sends `expectedPlanItemId` equal to that line's `currentPlanItemId`.
- `PRODUCTION_LINE_INACTIVE` on create → bootstrap refresh + notice flag.
- Frame with `palletizingLineId: 4` while rendered ids are {1, 2, 3} → treated as unknown (bootstrap). **Never** routed to line 3.

**Widget tests**

- RTL: 3 tabs in order خط أ · خط ب · خط ج (right to left), labels from the server.
- 2 tabs when bootstrap has 2 lines.
- Tab count changes 2 → 3 → 2 without losing the selected `lineId`.
- Wide layout: 3 panes when width ≥ 3 × minPaneWidth, tabs otherwise.
- Waiting card, blocked card and takeover dialog show the resolved label (no 'ماكنة 3').
- Line switched off dialog when the selected line disappears.

**Repository / API client tests**

- `createLinePallet` body includes `expectedPlanItemId`.
- 401 with `error.code = OPERATOR_PIN_INVALID` on a `/palletizing-line/` path → `OPERATOR_PIN_INVALID`, not `DEVICE_KEY_INVALID`.
- 401 with `AUTH_INVALID_CREDENTIALS` → device-key screen.
- 403 `PALLETIZER_NOT_ALLOWED` → its own message.

**Manual smoke** (DEV or staging backend at Flyway V191 or later, LINE_3 enabled): run the §6.11 checklist.

**LINE_1 / LINE_2 regression checklist**

1. Cold start with LINE_3 **inactive**: exactly 2 tabs 'خط أ', 'خط ب'; no request to any id not in bootstrap (check logs).
2. PIN login, create pallet, print, reprint on LINE_1 and LINE_2 (label letters A / B unchanged).
3. First-pallet FALET dialog on LINE_1.
4. Takeover request on LINE_2 → sound + dialog + banner; accept flow unchanged.
5. Waiting-for-operator card on LINE_1 after the operator ends the shift.
6. Plan-blocked state (no plan item) on LINE_2.
7. SSE up → safety cadence 50 s when nothing is urgent (not stuck at 6 s).
8. Background → resume → state correct, no duplicate dialogs.
9. Device key wrong → device-key screen; correct → recovers.
10. V190 close request flow on LINE_1 (companion handoff checklist).

### 6.11 Acceptance checklist for the go-live CHECKPOINT

Run against a **staging or DEV backend** that contains this release (Flyway V191 applied, LINE_3 visible in `/web/admin/production-lines`), with the **new build** installed on the test tablet. Record pass or fail for each step.

| # | Step | Expected | Pass/Fail |
|---|---|---|---|
| 1 | Admin list shows LINE_3 'خط ج', `line_number` 3, **inactive**. Start the app. | 2 tabs: خط أ, خط ب. No `/lines/<LINE_3 id>/…` request in the app log. | |
| 2 | Leave the app open with SSE connected. Admin enables LINE_3 (web or `PATCH …/enable`). | A third tab 'خط ج' appears at the **left** end within ~5 s, **without** restart or manual refresh. Selected tab unchanged. | |
| 3 | Inspect the app log or network trace. | Frame `palletizing-lines-changed` with `palletizingLineId` = LINE_3's id and `reason` `LINE_STATE_CHANGED`, followed by a bootstrap call. Paths for 'خط ج' use that id (3 on a production-shaped DB), **not** TF_LINE_3's id. | |
| 4 | Open the 'خط ج' tab before any operator claim. | Waiting card 'بانتظار استلام الخط' with the server body. Tab and card label 'خط ج' (no 'ماكنة 3'). App bar uses the third accent colour, or neutral grey while waiting. | |
| 5 | Stay on 'خط أ' while 'خط ج' waits. | The tab dot for 'خط ج' shows attention. Poll cadence treats a waiting 'خط ج' exactly as a waiting 'خط أ' / 'خط ب' is treated today (urgent 6 s, `palletizing_provider.dart:61,520-525`). After step 16 the urgent cadence stops once no rendered line is urgent. | |
| 6 | Admin adds a 'خط ج' plan item. Operator claims 'خط التشغيل ج' in the Operator App. | The 'خط ج' tab switches to the PIN screen within seconds. | |
| 7 | Enter a **wrong** PIN on 'خط ج'. | 'رمز المشغل غير صحيح' — **not** the device-key message. | |
| 8 | Enter the correct palletizer PIN on 'خط ج'. | Logged in; palletizer name shown. | |
| 9 | Create a pallet on 'خط ج'. | `201`; request body contains `expectedPlanItemId` = the line's `currentPlanItemId`; response `productionLine` `{name: "خط ج", lineNumber: 3}`. | |
| 10 | Print the label. | Side band shows **'C'** (or the owner-approved text). QR / serial correct. | |
| 11 | Reprint that pallet by scanned value from the 'خط أ' tab. | Same side band as step 10. | |
| 12 | Trigger a takeover request on 'خط ج' from the Operator App while the tablet shows 'خط ب'. | Sound + blocking takeover dialog naming 'خط ج'. Banner on the 'خط ج' tab. | |
| 13 | Operator requests close of the 'خط ج' plan item (V190). | Close-request dialog on 'خط ج' only. The frame carries `thermoformingLineId` (4 on production-shaped data) but routing uses `palletizingLineId`. | |
| 14 | Tablet in portrait and in landscape. | Portrait: 3 equal tabs, readable labels. Landscape: 3 panes if the width rule passes, else tabs. No overflow. RTL order خط أ · خط ب · خط ج. | |
| 15 | Kill network for 60 s during idle, then restore. | Tabs kept during the outage. After reconnect: bootstrap refetch, state converges. | |
| 16 | Background the app. Admin **disables** LINE_3. Resume. | 'خط ج' tab gone after resume. No requests to LINE_3's id afterwards. | |
| 17 | With the app in the foreground on 'خط ج', admin disables LINE_3 (end the shift first per runbook, or test mid-shift in staging only). | 'تم إيقاف الخط' notice → first tab selected → no further polling of LINE_3's id. | |
| 18 | Try to create a pallet on 'خط ج' from a dialog opened just before the disable. | `400 PRODUCTION_LINE_INACTIVE` shown as '{label} غير مفعّل حالياً…'; nothing created; tab removed. | |
| 19 | Re-enable LINE_3. | Tab returns; palletizer session re-validated (PIN screen if the session ended). | |
| 20 | Run the §6.10 LINE_1/LINE_2 regression checklist. | All pass. | |

---

## 7. NOT VERIFIED

- **No runtime execution of any kind.** No backend boot, HTTP call, SSE subscription, MySQL query, Flutter build, `flutter test`, or device run. Every backend statement is from source reading of HEAD `e47c2c15` plus the uncommitted working tree.
- **Production ids** LINE_3 = 3 and TF_LINE_3 = 4 are taken from the V191 javadoc (`V191__…java:47-48`) and the audit inputs. They were not queried from any database. Treat all ids as opaque.
- **Enable → frame on `app-events`.** The chain `ProductionLineAdminService` → `LineStateChangedEvent` → `OperatorDashboardLegacyFallbackListener` → `PalletizingAppLineEventsSseBroker` was not observed live. In particular it was not confirmed that the fallback listener's re-published event (inside an AFTER_COMMIT callback) is delivered by the broker's `fallbackExecution = true` listener. A dev acceptance harness for this exists in the backend task but had not reported results when this file was written.
- **Wire omission of null fields** for `LineStateResponse` under Spring Boot 4 / Jackson 3 relies on the class-level `@JsonInclude(NON_NULL)`. Not observed on the wire.
- **`GET /lines/{inactiveId}/state` returning 200** is code-read only (`LineStateService.java:93-98` has no active check).
- **`urgent-manager-announcement` never arriving on `app-events`** is code-read only (the broker class sends only `connected` and `palletizing-lines-changed`).
- **Flutter findings** come from the dirty working copy (27 entries). It is unknown which commit is installed on the factory tablets. Old-build behaviour with LINE_3 active (hidden-line polling, alert without dialog, label 'B') is inferred from code, not reproduced.
- **Tablet hardware**: screen size, density, orientation and printer model are unknown. The 420 dp minimum pane width is a proposal. The label printer's rendering of 'C' or an Arabic side band was not tested. Whether the floor wants 'C' on the physical label is **an owner decision**.
- **Load:** the cost of re-fetching bootstrap on `LINE_STATE_CHANGED` frames and every safety tick, per tablet, was not measured. Bootstrap builds one full line state per active line.
- **Warehouse App / Roll Production App "not affected"** comes from the client audit, not re-read for this file.
- **Operator App, Roll Worker App, Admin App specifics** in §2 are from their backend entry points only. See their own handoffs.
- **Staging data readiness:** the DEV `DataSeeder` runs only under non-prod profiles and may be gated by scheduling configuration. The checkpoint environment must be verified to have LINE_3 (via V191) before step 1.

---

## 8. Backend Compatibility & Rollout Notes

| Backend state | Current build (HEAD `b936b3d6`) | Updated build (this handoff + V190 handoff) |
|---|---|---|
| This release deployed, LINE_3 **inactive** | **Broken on every line by V190**: pallet creation sends no `expectedPlanItemId` → `400 PRODUCTION_PLAN_EXPECTED_ITEM_REQUIRED`; close requests unanswered. The LINE_3 part alone is invisible. | Works: 2 tabs, identical to today plus V190 behaviour |
| This release deployed, LINE_3 **active** | V190 breakage, and in addition: line 3 never drawn; every tablet polls it; 6 s urgent cadence while it waits for an operator; line-3 takeover rings with no dialog; no way to register 'خط ج' pallets | Works: 3 tabs |
| Previous backend (before this release) | Works (today) | Not supported: needs V190 endpoints and field. Do not install before the backend. |

**Can the backend deploy first?** **Not for this release.**

- The LINE_3 part is additive and hidden while inactive, so on its own it could ship ahead.
- But V190 is in the same release and immediately breaks pallet creation for the current Palletizing build.
- The backend, the updated Palletizing App and the updated Operator App must go live in **one coordinated maintenance window**.

**Rollout order** (from the owner runbook)

1. Deploy the backend together with the updated Operator, Palletizing and Roll Worker apps (and the Admin App if its acceptance needs a change).
2. **CHECKPOINT:** all four apps pass their LINE_3 acceptance checklists (§6.11 for this app) on staging/DEV with LINE_3 enabled. Production LINE_3 stays **inactive** until this passes.
3. Admin enables LINE_3 at `/web/admin/production-lines`.
4. Add a 'خط ج' plan item on the web plan page (an open board refreshes itself on enable; reloading is harmless).
5. The operator claims TF_LINE_3.
6. The palletizer logs in on 'خط ج'.
7. The roll worker joins.

**Rollback**

1. Pause the line and end the shift first. This ends palletizer sessions through the shift-line teardown (`PalletizerSessionService.java:281-308`).
2. Then disable LINE_3.

There is **no in-use guard** on disable. Disabling mid-shift:

- blocks pallet creation (`400 PRODUCTION_LINE_INACTIVE`);
- hides 'خط ج' from bootstrap;
- leaves the palletizer session and the operator claim ACTIVE on the backend.

The updated app removes the tab on the frame, resume, or safety tick. A rollback of the app build alone is not possible in this release (V190), so roll back the backend and app together.

**Tablet fleet.** There is no per-device line binding; every tablet receives every active line. **All** palletizing tablets must run the updated build before LINE_3 is enabled in production. One old tablet is enough to reproduce the hidden-line polling and silent takeover alerts.

---

## 9. Final Acceptance Criteria

1. The app renders exactly the lines returned by `GET /api/v1/palletizing-line/bootstrap`, in server order, as tabs or panes in RTL. Nothing in the code limits it to two lines (no `length: 2`, `const [1, 2]`, `== 1 ? … : …`, or 2-value enum used for layout, polling, dialogs or labels).
2. Every label comes from `lineDisplayName` → `lineName` → abjad ordinal from `lineNumber` (3 → 'خط ج'). No label is derived from `lineId`.
3. Every path, map key, selection, token and announcement `lineId` uses the ProductionLine `lineId` from bootstrap. `thermoformingLineId` is never used for routing.
4. Only rendered lines are polled, alerted on, and used for announcements. A removed line is pruned from all state on the next bootstrap.
5. A `palletizing-lines-changed` frame for an unknown line or with reason `LINE_STATE_CHANGED`, every SSE `connected`, every resume, and every safety tick trigger a **silent** bootstrap re-fetch. Enabling LINE_3 shows 'خط ج' without restart; disabling removes it.
6. `PRODUCTION_LINE_INACTIVE`, `PRODUCTION_LINE_NOT_FOUND`, `THERMOFORMING_LINE_MAPPING_NOT_FOUND` and `THERMOFORMING_LINE_PAUSED` show the §6.8 Arabic texts and never the backend `message`. Business 401/403 codes are not shown as a device-key error.
7. Every pallet request carries `expectedPlanItemId`, and the V190 companion handoff is fully implemented in the same build.
8. A line-3 label side band prints the owner-approved text ('C' proposed).
9. §6.10 automated tests pass. The §6.11 checkpoint (20 steps) and the LINE_1/LINE_2 regression list pass on a staging/DEV backend with LINE_3 enabled.
10. The build is installed on **every** palletizing tablet before the administrator enables LINE_3 in production.
