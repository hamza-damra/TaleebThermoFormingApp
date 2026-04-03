# 1. Executive Summary

The current frontend is a Flutter app built with clean-architecture layers and `Provider`/`ChangeNotifier` state management. Today, the app has two different identity concepts:

- A global app-level PIN login at startup (`LoginScreen` -> `AuthProvider` -> `/auth/pin-login`).
- A separate manual operator selection inside the palletizing workflow (`PalletizingProvider` + operator dropdown UI).

The current pallet creation flow works like this:

1. The user passes a global 4-digit PIN login screen and enters the app.
2. The app loads operators, product types, production lines, and line summaries.
3. The user manually selects an operator for each line from a searchable dropdown.
4. The user manually selects a product type.
5. The user presses "Create pallet", and a second dialog appears that again asks for operator and product before confirming creation.
6. The frontend sends `operatorId`, `productTypeId`, `productionLineId`, and `quantity` to the backend.
7. After pallet creation, the UI shows a success dialog and allows label printing.

Operator selection currently appears in the UI in multiple places:

- The main line section (`ProductionLineSection`) has an operator dropdown.
- The create-pallet dialog (`CreatePalletDialog`) has another operator dropdown.
- The shift handover dialog and pending handover dialog also ask the user to manually pick an operator.

The biggest mismatch with the desired behavior is this:

- The current PIN is used for a global app session.
- The current pallet operator is still chosen manually from dropdowns.
- The desired behavior wants the opposite model: no manual operator selection, and operator identity should come from a line-specific PIN authorization flow.

There is a second major architectural mismatch:

- The current app already stores some line-specific data separately.
- But the async state that would matter for independent authorization is still mostly global (`isLoading`, `isCreating`, global error state, global refresh behavior).

In short:

- The current frontend is partially ready for per-line authorization because it already renders line-specific sections and stores some state per line.
- But it is not ready to treat operator authorization as an independent per-line state model.
- The current app also still has a root login gate, so if the product truly wants "no login screen for this workflow", the session/auth bootstrap strategy will need separate architectural treatment.

# 2. Current Screen Structure

## 2.1 Entry Flow Before Pallet Screen

The app entry point is `lib/main.dart`.

- `MyApp` registers four app-wide providers:
  - `AuthProvider`
  - `PalletizingProvider`
  - `PrintingProvider`
  - `ShiftHandoverProvider`
- `MaterialApp.home` is `AuthWrapper`.
- `AuthWrapper` decides whether to show:
  - loading spinner
  - `LoginScreen`
  - `PalletizingScreen`
  - `PalletizingScreen` with a full-screen blocking pending-handover overlay

Important current behavior:

- The palletizing workflow is not directly accessible without a prior global authentication state.
- `AuthWrapper` also performs pending handover checks and may block the entire app before palletizing can be used.

## 2.2 Main Pallet Screen Layout

The main pallet UI lives in `lib/presentation/screens/palletizing_screen.dart`.

### Mobile and Tablet

On mobile and tablet:

- The screen uses a `TabController(length: 2)`.
- The app bar contains a `TabBar` with:
  - `خط 1`
  - `خط 2`
- The active tab color changes based on the selected line color.
- The body uses a `TabBarView`.
- Each tab hosts one `ProductionLineSection`.

Current mobile/tablet details:

- The leading app-bar icon is a person icon with a `TODO` comment for operator info.
- There is no implemented current-line operator display in that app bar.
- Switching tabs only changes local widget state for app-bar color; it does not load separate data per tab.

### Desktop

On desktop:

- There are no tabs.
- Both lines are displayed simultaneously in a split view.
- The layout is a `Row` with two `Expanded` sections.
- The left pane is Line 2.
- The right pane is Line 1.

This is an important detail:

- Mobile/tab order is Line 1 then Line 2.
- Desktop order is visually reversed: Line 2 left, Line 1 right.

### Per-Line Section Layout

Each line is rendered by `lib/presentation/widgets/production_line_section.dart`.

Each `ProductionLineSection` contains:

- A scrollable content area.
- A form card.
- A summary card.
- A fixed bottom create button.

On desktop only, it also shows a large line header banner using the backend line name when available.

The line section structure is:

| Area | Current Behavior |
| --- | --- |
| Header | Desktop-only gradient header with backend line name or enum label |
| Form card | Operator field + product field |
| Summary card | Pallet count + derived package count |
| Bottom action | Large fixed "إنشاء مشتاح جديد" button |

## 2.3 How Lines Are Represented in Code

The current app represents a line in three separate ways:

1. Hardcoded UI enum in `lib/core/constants.dart`
   - `ProductionLine.line1`
   - `ProductionLine.line2`
   - Each has:
     - a color
     - a light background color
     - an Arabic label
     - a hardcoded numeric line number (`1` or `2`)

2. Backend entity in `lib/domain/entities/production_line.dart`
   - `id`
   - `name`
   - `code`
   - `lineNumber`

3. Provider state maps keyed by `line.number`
   - `1` or `2`

The screen currently resolves backend line entities by matching `lineNumber == 1` and `lineNumber == 2`, then passes those entities into each `ProductionLineSection`.

Current hardcoded assumptions:

- The UI only supports exactly two lines.
- The backend must return production lines whose `lineNumber` values match `1` and `2`.
- If a backend line entity is missing, pallet creation falls back to sending `line.number` as the `productionLineId`, which assumes line IDs may equal `1` or `2`.

## 2.4 Operator Dropdown

The operator dropdown is currently in the form card for each line:

- File: `lib/presentation/widgets/production_line_section.dart`
- Method: `_buildOperatorField`

Current behavior:

- It shows the label `اسم المشغل`.
- It opens `SearchablePickerDialog<Operator>`.
- It searches by operator name, operator code, and display label.
- It stores the selected operator through `PalletizingProvider.selectOperator(line.number, selected)`.

Current UX properties:

- The operator list is global, not line-filtered.
- Any operator can be chosen for either line in the frontend.
- The field is always interactive when operators exist.
- It is not blocked by missing authorization because no such concept exists yet.

If operators are not loaded:

- The line section shows a warning box:
  - `لا يوجد مشغلين - يرجى إضافتهم من لوحة الإدارة`

## 2.5 Product Type Dropdown

The product dropdown is also in the form card:

- File: `lib/presentation/widgets/production_line_section.dart`
- Method: `_buildProductField`

Current behavior:

- It shows the label `نوع المنتج`.
- It opens `SearchablePickerDialog<ProductType>`.
- It searches by:
  - name
  - product name
  - color
  - prefix
  - display label
- After choosing a product from the picker, the app shows a product confirmation dialog with image/details.
- Only after the confirmation dialog returns `true` does the provider store the product using `selectProductType`.

Important current UX detail:

- Product selection in the main form has an extra confirmation step.
- Product selection inside the create dialog does not have that extra confirmation step.
- So the same concept already has inconsistent UX across the screen.

If products are not loaded:

- The line section shows a warning box:
  - `لا يوجد أنواع منتجات - يرجى إضافتها من لوحة الإدارة`

## 2.6 Summary Cards

The summary card lives in `lib/presentation/widgets/summary_card.dart`.

Current displayed stats:

- `المشاتيح` = pallet count
- `العبوات` = package count

Where the values come from:

- `palletCount` comes from `PalletizingProvider.getPalletCount(line.number)`, which reads `todayPalletCount` from the line summary returned by the backend.
- `packageCount` is not returned by the backend.
- `packageCount` is calculated in the widget as:
  - `palletCount * selectedProductType.packageQuantity`

Important consequence:

- If no product is selected for a line, package count is `0`.
- If the line has already produced pallets today but the currently selected product does not match those pallets, the displayed package count may not represent reality.
- The summary is therefore partly backend-driven and partly derived from the currently selected UI state.

Also notable:

- The `LineSummary` model includes `lastPalletAt` and `lastPalletAtDisplay`.
- The current UI does not display those values.

## 2.7 Create Pallet Button

The create button is the large fixed bottom button in each line section:

- File: `lib/presentation/widgets/production_line_section.dart`
- Method: `_buildCreateButton`

Current behavior:

- It is only disabled while `provider.isCreating` is true.
- It is not disabled when:
  - no operator is selected
  - no product is selected
  - operators list is empty
  - products list is empty

So the current UX is:

- The user can always open the create dialog.
- Validation happens later inside the dialog.

## 2.8 Create Pallet Dialog

The dialog lives in `lib/presentation/widgets/create_pallet_dialog.dart`.

Current fields:

- operator dropdown
- product dropdown
- quantity stepper/input

Current behavior:

- It is seeded from the line's current selected operator and selected product.
- But the user can change both again inside the dialog.
- Confirmation is only enabled when:
  - operator is selected
  - product is selected

This means operator selection exists twice in the pallet flow:

- once in the line section
- again in the create dialog

That duplication is one of the biggest current UX mismatches with the desired design.

## 2.9 Success and Printing UI

After successful creation:

- `ProductionLineSection` shows `PalletSuccessDialog`
- File: `lib/presentation/widgets/pallet_success_dialog.dart`

Current success dialog behavior:

- Shows product details, quantity, line, operator, and creation time
- Displays the operator name from the pallet create response
- Allows `طباعة الملصق`
- Uses `PrintingProvider` for local printer selection and local printing
- Logs print attempts back to the backend after local printing

Important current behavior:

- Printing is tied to the newly created pallet success dialog.
- There is no separate line authorization check before printing.
- If the pallet was created, the print button is allowed as long as printing prerequisites are met.

## 2.10 Current Loading, Empty, and Error States

The current screen has several layers of loading/error behavior.

### Global auth/session states

- `AuthWrapper` shows a full-screen spinner while auth status is being checked.
- `AuthWrapper` shows `LoginScreen` when unauthenticated.

### Pending handover global states

- While pending handover is being checked, `AuthWrapper` can show a full-screen "checking handovers" loader.
- If pending handover check fails, `AuthWrapper` shows a full-screen retry state.
- If a blocking pending handover exists, `AuthWrapper` draws:
  - `PalletizingScreen`
  - a full-screen `ModalBarrier`
  - `PendingHandoverDialog`

This is a useful existing pattern, but it is global, not line-specific.

### Pallet data loading

- `PalletizingScreen` shows shimmer placeholders while `PalletizingProvider.isLoading` is true.
- Mobile/tab shimmer uses a tabbed shimmer.
- Desktop shimmer uses a dual-pane shimmer.

### Pallet data error

- `PalletizingScreen` shows a full-screen error state with retry if `provider.errorMessage != null`.

### Inline empty states inside line section

- Missing operators: warning box inside the operator field area
- Missing product types: warning box inside the product field area

# 3. Current State Management

## 3.1 State Management Style

The app uses:

- `Provider`
- `ChangeNotifier`
- local `StatefulWidget` / `setState` for dialog-local UI state

There is no:

- Bloc
- Cubit
- Riverpod
- Redux
- state machine library

The palletizing architecture is currently split across these providers:

| Provider | Current Responsibility |
| --- | --- |
| `AuthProvider` | global auth/session state |
| `PalletizingProvider` | palletizing data and most pallet workflow state |
| `PrintingProvider` | printer configuration and printing |
| `ShiftHandoverProvider` | shift handover state and app-wide blocking handover overlay |

## 3.2 Real Existing Palletizing State Shape

`PalletizingProvider` currently owns:

- global async state
  - `_state`
  - `_errorMessage`
- global reference data
  - `_operators`
  - `_productTypes`
  - `_productionLines`
- per-line maps keyed by line number
  - `_selectedOperators`
  - `_selectedProductTypes`
  - `_lastPalletResponses`
  - `_lineSummaries`

This is the most important current fact for the new feature:

- The provider already stores several things per line.
- But it does not store authorization per line.

## 3.3 Whether Line 1 and Line 2 Already Have Separate State Objects

Not as explicit objects.

There is no current `LineState` class or `LineViewModel` class.
Instead, the provider uses separate maps:

- `Map<int, Operator?> _selectedOperators`
- `Map<int, ProductType?> _selectedProductTypes`
- `Map<int, PalletCreateResponse?> _lastPalletResponses`
- `Map<int, LineSummary?> _lineSummaries`

So the current answer is:

- Yes, line state is partially separated.
- No, it is not modeled as a dedicated structured per-line object.

## 3.4 How Current Selected Operator Is Stored

Selected operator is stored in:

- `PalletizingProvider._selectedOperators[lineNumber]`

Important behavior:

- This is purely a UI-selected operator.
- It is not persisted locally.
- It is not restored from backend.
- It is cleared whenever `loadInitialData()` runs.

That last point is very important:

- `loadInitialData()` explicitly clears `_selectedOperators`.
- `PalletizingScreen.initState()` calls `loadInitialData()`.
- `_refreshData()` also calls `loadInitialData()`.
- Each line's `RefreshIndicator` triggers that same global refresh.

So current line operator selections are fragile and short-lived.

## 3.5 How Current Selected Product Is Stored

Selected product type is stored in:

- `PalletizingProvider._selectedProductTypes[lineNumber]`

It behaves similarly to operator selection:

- line-specific
- not persisted
- cleared on `loadInitialData()`

## 3.6 How Current Summary/Statistics State Is Stored

Current line summary state is stored in:

- `PalletizingProvider._lineSummaries[lineNumber]`

It is loaded by:

- fetching production lines first
- then calling `getLineSummary(line.id)` for each line

Summary refresh behavior:

- Initial load is done for all lines.
- After pallet creation, only the affected line summary is refreshed.
- If a summary refresh fails, the provider silently ignores the error.

## 3.7 How Current Pallet Creation State Is Stored

Pallet creation state currently has two forms:

1. Global async state in `_state`
   - `idle`
   - `loading`
   - `loaded`
   - `creating`
   - `error`

2. Last response per line in `_lastPalletResponses[lineNumber]`

Important limitation:

- `isCreating` is global, not per line.
- If one line is creating a pallet, both line sections see `provider.isCreating == true`.
- That means both create buttons become disabled.

This does not fully match the desired "line 1 and line 2 are independent" requirement.

## 3.8 How App-Level Auth State Is Stored

Global auth/session state is fully separate from line state:

- `AuthProvider._state`
- `AuthProvider._user`
- secure storage token and user info through `AuthLocalStorage`

This current session state is:

- app-wide
- single-user
- not line-specific

## 3.9 What Already Supports Independent Per-Line Authorization

The current architecture already has some strong foundations:

- `ProductionLineSection` is already rendered per line.
- `PalletizingProvider` already reads/writes line-specific values through `line.number`.
- The UI already visually separates lines on both mobile/tab and desktop.
- The app already uses overlay blocking patterns elsewhere (`PendingHandoverDialog` in `AuthWrapper`).

These parts are good for the new feature.

## 3.10 What Cannot Yet Support Independent Per-Line Authorization Cleanly

The following parts are not sufficient today:

- No dedicated authorization state per line
- No "authorization loading" state per line
- No "authorization error" state per line
- No current-authorized-operator model separate from selected operator
- No restore-authorized-operator flow on app start
- Global `isCreating`
- Global `errorMessage`
- Global refresh behavior that clears line selections for both lines
- Root auth/session model that is completely separate from line responsibility

Most importantly:

- Current `selectedOperator` should not be reused as the future authorization state.

Why that matters:

- `selectedOperator` currently means "what the user picked from the dropdown".
- Future authorization state must mean "which operator the backend has authorized for this line".
- Those are not the same concept.

# 4. Current API Integration

## 4.1 Common API Client Behavior

All backend requests go through `lib/data/datasources/api_client.dart`.

Current API client assumptions:

- Base URL is `https://taleeb.me/api/v1`
- Requests expect a JSON envelope with `success`
- Successful responses are parsed from `response.data['data']`
- A bearer token is automatically added from secure storage if present
- `401` becomes `ApiException.unauthorized()`

Important current limitation:

- `401` is converted to an exception message.
- But the app does not automatically clear the session or redirect back to login when a request returns `401`.

## 4.2 Current Endpoints Used by the Screen/Flow

| Endpoint | Triggered From | Request | Response Expected | Operator Handling | Current Frontend Assumption |
| --- | --- | --- | --- | --- | --- |
| `POST /auth/pin-login` | `LoginScreen` -> `AuthProvider.pinLogin()` -> `AuthRepositoryImpl.pinLogin()` | `{ "employeeCode": "1234" }` | `{ success: true, data: { token, user } }` | Not line operator; this becomes global app user | PIN authenticates the whole app session |
| `GET /palletizing/operators` | `PalletizingProvider.loadInitialData()` | no body | `data: List<Operator>` | Returns selectable operator list | Same operator list is valid for both lines |
| `GET /palletizing/product-types` | `PalletizingProvider.loadInitialData()` | no body | `data: List<ProductType>` | None | All product types are globally available |
| `GET /palletizing/production-lines` | `PalletizingProvider.loadInitialData()` | no body | `data: List<ProductionLine>` | None | Backend returns lines that map to UI line numbers 1 and 2 |
| `GET /palletizing/lines/{lineId}/summary` | `PalletizingProvider._loadAllLineSummaries()` and `refreshLineSummary()` | no body | `data: LineSummary` | None | Summary is line-specific and keyed by backend line id |
| `POST /palletizing/pallets` | `ProductionLineSection._showCreateDialog()` -> `PalletizingProvider.createPallet()` -> repository | `{ operatorId, productTypeId, productionLineId, quantity }` | `data: PalletCreateResponse` with nested `operator`, `productType`, `productionLine` | `operatorId` is injected manually from UI-selected operator | The frontend decides who the pallet operator is |
| `POST /palletizing/pallets/{palletId}/print-attempts` | `PalletSuccessDialog._handlePrint()` -> `PalletizingProvider.logPrintAttempt()` | `{ printerIdentifier, status, failureReason? }` | `data: PrintAttemptResult` | No operatorId sent | Print logging is detached from authorization state |
| `GET /shift-schedule/current-shift` | `PalletizingScreen.initState()` -> `ShiftHandoverProvider.fetchCurrentShift()` | no body | `data: ShiftInfo` | None | Used for handover context |
| `POST /shift-handover` | `PalletizingScreen._handleShiftHandover()` -> provider/repository | `{ operatorId, items }` | `data: Handover` | operator selected manually | Outgoing operator still comes from UI |
| `GET /shift-handover/pending-list` | `AuthWrapper` / `ShiftHandoverProvider.checkPendingHandover()` | no body | `data: List<Handover>` | None directly | The app may block globally before palletizing |
| `POST /shift-handover/{id}/confirm` | `PendingHandoverDialog` -> `ShiftHandoverProvider.confirmHandover()` | `{ incomingOperatorId }` | `data: Handover` | operator selected manually | Incoming operator identity also comes from UI |
| `POST /shift-handover/{id}/reject` | `PendingHandoverDialog` -> `ShiftHandoverProvider.rejectHandover()` | `{ incomingOperatorId }` | `data: Handover` | operator selected manually | Rejection identity also comes from UI |

## 4.3 Current Printing Integration

Printing itself is not a backend API call.

Current print flow:

1. `PalletSuccessDialog` calls `PrintingProvider.print(...)`
2. `PrintingProvider` uses `PrinterClient`
3. `PrinterClient` talks directly to the printer
4. Only after local print finishes does the app call the backend print-attempt logging endpoint

So from the frontend perspective:

- pallet creation is backend-backed
- actual printing is local-device/network behavior
- print auditing is backend-backed

## 4.4 Where `operatorId` Is Currently Passed

`operatorId` is currently injected manually in three different workflow families:

### Pallet creation

- `CreatePalletDialog` returns an `Operator`
- `ProductionLineSection._showCreateDialog()` extracts `operator.id`
- `PalletizingProvider.createPallet()` accepts `operatorId`
- `PalletizingRepositoryImpl.createPallet()` sends it in the POST body

### Shift handover creation

- `ShiftHandoverDialog` returns `operatorId`
- `PalletizingScreen._handleShiftHandover()` passes it to `createHandover`

### Pending handover confirm/reject

- `PendingHandoverDialog` requires selecting an operator
- That selected operator ID becomes `incomingOperatorId`

## 4.5 Current Frontend Assumptions About Operator Identity

The frontend currently assumes:

- operator identity comes from a user-driven dropdown selection
- the selected operator is trustworthy enough to send directly to the backend
- operator selection is not line-restricted in the frontend
- the backend will accept the sent operator for the chosen line, or reject it

This assumption is exactly what the new PIN flow is meant to remove.

# 5. Current Operator Selection Flow

## 5.1 Where the Operator Dropdown Is Shown

For the pallet creation workflow, operator selection appears in two places:

1. Main line form
   - `ProductionLineSection._buildOperatorField`
2. Create pallet dialog
   - `CreatePalletDialog._buildOperatorDropdown`

Adjacent operator-related flows also contain manual operator selection:

3. `ShiftHandoverDialog`
4. `PendingHandoverDialog`

## 5.2 When It Becomes Required

Current operator selection is not required at screen level.

What the user can do without selecting an operator:

- switch lines
- select product
- view summaries
- press the create button
- open the create dialog
- edit quantity inside the create dialog

Where it becomes required today:

- only at create dialog confirmation time
- because `_canConfirm()` requires both operator and product

This means:

- the line is not blocked before operator selection
- operator selection is late-stage validation, not an authorization gate

## 5.3 Whether It Is Validated Before Create Pallet

Yes, but only inside the dialog.

Validation path:

- `CreatePalletDialog._canConfirm()` returns true only when:
  - `_selectedOperator != null`
  - `_selectedProductType != null`

There is no earlier guard in:

- the line section itself
- the create button
- the screen routing

## 5.4 Whether It Is Stored Per Tab or Globally

Operator selection is currently stored per line/tab in memory:

- `PalletizingProvider._selectedOperators[lineNumber]`

So within the same provider lifecycle:

- Line 1 can have one selected operator
- Line 2 can have a different selected operator

But it is not truly durable because:

- a global refresh clears both
- initial data load clears both
- app restart clears both

## 5.5 How It Affects Later Requests

Current downstream effects:

- Selected operator becomes the `operatorId` sent to create pallet.
- The active line's selected operator becomes the initial operator in `ShiftHandoverDialog`.
- The create-pallet response overwrites the line's selected operator with the operator returned from the backend.

That last behavior exists so the dropdown keeps showing the operator echoed back by the backend.

## 5.6 What Happens When Switching Lines

Within the same session and without refresh:

- Line switching does not clear operator selection.
- Each line reads its own operator through `line.number`.
- On mobile/tab, switching tabs preserves the existing per-line selections.
- On desktop, both are visible at once anyway.

However:

- There is no dedicated "current responsible operator" display beyond the selected dropdown value.
- There is no lock state saying "this line is currently authorized for operator X".

## 5.7 What Happens on App Restart or Rebuild

### App restart

- Global app auth token may be restored from secure storage.
- Selected line operators are not restored.
- The app re-enters pallet screen authenticated, but line operator selection is empty again.

### Screen rebuild without provider recreation

- If only widgets rebuild and `PalletizingProvider` survives, selected operators remain in memory.

### Initial load / refresh / some lifecycle paths

- `loadInitialData()` clears selected operators and selected product types.
- So any flow that re-runs `loadInitialData()` wipes operator selection even if the user did not intend to reset it.

### Pull-to-refresh detail

Every line's `RefreshIndicator` calls the same `_refreshData()` method.

That means:

- refreshing one line currently refreshes both lines
- refreshing one line also clears operator selection for both lines

This is a very important current limitation when thinking about truly independent per-line authorization.

# 6. Analysis of the New PIN-Based Operator Authorization UX

## 6.1 Core Desired Behavioral Shift

The desired model changes the meaning of "operator" from:

- a manually selected UI field

to:

- a backend-verified line authorization state

That is a fundamental architectural change, not just a widget replacement.

## 6.2 Best Fit With the Existing Architecture

The safest fit with the current codebase is:

- keep using `Provider` and `ChangeNotifier`
- keep `PalletizingProvider` as the main owner of line workflow state
- add a dedicated per-line authorization model inside `PalletizingProvider`
- render a section-scoped blocking overlay inside each `ProductionLineSection`

This is better than trying to reuse `AuthProvider` because:

- `AuthProvider` is app-global and single-user
- `AuthProvider` stores only one `User`
- the desired feature needs two simultaneous independent line identities
- one tablet may have:
  - line 1 authorized under operator A
  - line 2 blocked
  - or line 2 authorized under operator B

That cannot be expressed cleanly through the current `AuthProvider`.

## 6.3 Why a Section-Scoped Overlay Fits Better Than a Global Dialog

The requirement says the block must apply to a specific line only.

The current app already has a global blocking overlay pattern in `AuthWrapper` for pending handover:

- screen
- modal barrier
- dialog above everything

That exact pattern should not be copied at the whole-screen level for operator PIN authorization, because:

- on desktop both lines are visible at the same time
- one line must be usable while the other remains blocked

So the better adaptation is:

- use the same visual language
- but scope it to each `ProductionLineSection`
- implement it as an in-section `Stack` overlay/card instead of a root `showDialog()`

This allows:

- Line 1 overlay visible only on Line 1 pane
- Line 2 fully usable
- or vice versa

## 6.4 What Should Change Conceptually

The app should separate these two concerns:

1. App/session authentication
   - used so API calls have a valid token
   - currently handled by `AuthProvider`

2. Line/operator authorization
   - used to determine who is responsible for pallet actions on a specific line
   - should live in palletizing state, not global auth state

That separation is critical.

The current code incorrectly blends business identity into UI selection.
The new design should:

- stop treating operator as a mutable dropdown choice
- start treating operator as verified state owned by the backend and mirrored by the frontend

## 6.5 How the Desired Behavior Maps Onto Current Screen Parts

### Current operator dropdown in form card

Best replacement:

- a read-only "current responsible operator" display
- optionally with a small "change operator" action

### Current create-pallet dialog

Best change:

- remove operator selection completely
- use the currently authorized operator from line state

### Current create request

Best change:

- stop sending free-form `operatorId`
- let backend infer operator from the line authorization state

### Current line sections

Best change:

- each section checks whether it is authorized
- if not authorized, it shows a blocking overlay inside that section

### Current app-root login

Important architectural note:

- If the product also wants to remove the root login screen entirely, that is a separate backend/session question.
- The current app cannot call any protected palletizing endpoint without a bearer token.
- So removing the root login screen requires an alternative session bootstrap strategy such as:
  - device token
  - kiosk token
  - backend-issued anonymous app session

That should not be silently conflated with line operator authorization.

## 6.6 What Can Be Reused Without Breaking the App Unnecessarily

The following existing patterns can be reused:

- `PalletizingProvider` as the owner of line workflow state
- per-line maps keyed by `line.number`
- `ProductionLineSection` as the UI boundary for one line
- overlay/blocking visual approach already used by pending handover
- existing `Operator` model for display after backend verification
- existing `ApiException` mechanism for mapping backend error codes

## 6.7 What Should Not Be Reused As-Is

The following current pieces should not become the new auth source of truth:

- `selectedOperator`
- `AuthProvider.user`
- `LoginScreen`
- create-dialog local operator state

Reason:

- all of them represent the wrong level of identity for this feature

# 7. Recommended Frontend UX

## 7.1 What Replaces the Operator Dropdown

Replace the current operator dropdown area in each line form with a read-only operator authorization card.

Recommended content:

- label: `المشغل المسؤول`
- operator name
- operator code if available
- optional `تم التفويض` / `نشط الآن`
- optional authorization time
- small secondary action:
  - `تغيير المشغل`

If the line is not authorized yet:

- the same area can show:
  - `لا يوجد مشغل مفوض لهذا الخط`

## 7.2 Where the Current Operator Name Should Appear

Best placement:

- exactly where the operator dropdown exists today in `ProductionLineSection`

Why this is the safest UX:

- users already expect operator information in that location
- layout change is minimal
- form structure stays familiar

Optional secondary placement:

- on mobile/tab, the app bar leading person icon could later show current tab operator
- but this should be secondary, not primary

Reason:

- on desktop both lines are visible, so the authoritative operator display must live inside each line section

## 7.3 When the Blocking Dialog/Overlay Should Appear

Recommended behavior:

- show the blocking overlay immediately when a line section becomes visible and has no authorized operator

That means:

- mobile/tab:
  - show it when entering the line tab
- desktop:
  - show it inside each unauthorized pane as soon as the screen loads

This is better than "show on first action" because the requirement says the line must be blocked before pallet operations can continue.

## 7.4 Recommended Overlay Design

Use a section-scoped overlay card, not a full-screen global route dialog.

Recommended contents:

- title such as `تفويض المشغل لهذا الخط`
- 4-digit PIN input
- confirm button
- inline error area
- loading state on confirm

Do not include:

- operator dropdown
- line selector
- extra fields

The line context is already known by the section itself.

## 7.5 Which Controls Must Be Disabled Before Authorization

Before a line is authorized, the frontend should disable or block:

- product selection
- create pallet button
- save/confirm in any create flow
- print label action
- any other pallet workflow action for that line

Recommended behavior for read-only items:

- allow summary card visibility
- allow viewing line name/theme
- keep the section visually present but blocked

This fits the business rule:

- read-only visibility is okay
- operational actions are not

## 7.6 Loading State During PIN Verification

Recommended UX while verifying PIN:

- disable PIN input
- disable confirm button
- show spinner inside confirm button or below the field
- keep the overlay in place

Because this is section-scoped:

- Line 1 can be authorizing while Line 2 remains usable

## 7.7 Error Handling UX

Recommended per-line inline error behavior:

| Error Type | UX Recommendation |
| --- | --- |
| Wrong PIN | show inline error under the PIN field, clear PIN, keep overlay open |
| Operator not assigned to this line | show specific inline message, keep overlay open |
| Inactive operator | show specific inline message, keep overlay open |
| Network error / timeout | show inline retry state, keep line blocked |
| Session expired | escalate to app-level re-auth/session recovery, not just inline line error |

Use inline line-scoped messaging rather than global snackbars for these cases.

Why:

- on desktop the user may be interacting with two lines
- a global snackbar is ambiguous about which line failed

## 7.8 Change Operator Later

Recommended future-safe behavior:

- add a small `تغيير المشغل` action on an authorized line
- pressing it reopens the same PIN overlay/card
- a successful PIN verification replaces the current authorized operator for that line

If there are backend restrictions:

- the backend should return a clear error or warning
- the UI should reflect that response

For example:

- open pallet exists
- line is currently locked
- shift/handover conflict exists

The frontend should not invent those rules on its own.

## 7.9 Recommended Create-Dialog UX After This Change

Safest frontend recommendation:

- remove operator selection from `CreatePalletDialog`
- keep the dialog focused on the remaining create inputs

Two options are reasonable:

### Minimal-risk option

- keep product + quantity in the dialog
- only remove operator

### Cleaner UX option

- keep product selection on the line section
- make the create dialog quantity-only

My recommendation:

- quantity-only dialog is cleaner
- but removing operator only is the smallest change if the team wants minimal churn

# 8. Independent Per-Line Authorization Model

## 8.1 Recommended State Shape

From the frontend perspective, each line should have an explicit authorization state object.

Recommended shape:

```ts
LineAuthorizationState {
  lineId: number
  lineNumber: number
  isAuthorized: boolean
  authorizedOperatorId: number | null
  authorizedOperatorName: string | null
  authorizedOperatorCode: string | null
  authorizedAt: DateTime | null
  isLoadingCurrentAuthorization: boolean
  isAuthorizing: boolean
  authorizationError: string | null
  authorizationErrorCode: string | null
}
```

This is better than storing only:

- `Operator?`
- or only `bool isAuthorized`

because the UI needs to handle:

- initial restore/loading
- wrong PIN
- network failure
- authorized display
- replacement/change operator

## 8.2 How It Should Be Keyed

To fit current UI patterns with minimal breakage:

- expose lookup by `line.number`
- store backend `lineId` inside the state object

Reason:

- current widgets already read all line-specific state by `line.number`
- current API calls still need backend `line.id`

## 8.3 Whether Current Architecture Already Supports This Shape

Partially, yes.

What already supports it:

- the provider already uses per-line maps
- the UI already asks for state by line number
- the screen already separates Line 1 and Line 2 clearly

What does not support it yet:

- there is no current authorization model
- there is no line-specific async status for authorization
- there is no restore-current-authorization flow
- there is no line-specific error surface for authorization

## 8.4 What Should Change in State Architecture

Recommended minimal structural change:

- add `Map<int, LineAuthorizationState> _lineAuthorizations` to `PalletizingProvider`

Recommended companion methods:

- `getLineAuthorization(int lineNumber)`
- `loadCurrentAuthorizationForLine(...)`
- `loadCurrentAuthorizationsForAllLines()`
- `authorizeLineWithPin(...)`
- `clearLineAuthorization(...)`

Recommended related cleanup:

- keep `selectedProductType` per line
- keep `lineSummary` per line
- stop using `selectedOperator` as the line identity source for pallet creation

## 8.5 Important Related Improvement

If line independence is a real requirement, the provider should also consider moving these from global to per-line state:

- create-in-progress
- create error

Current global `isCreating` means one line's create action disables both lines.

That is not strictly the same as PIN authorization, but it is part of the same "independent lines" architecture story.

# 9. Required Frontend Refactor Areas

## 9.1 Main Refactor Table

| File / Class | Current Responsibility | Required Change | Risk | Size |
| --- | --- | --- | --- | --- |
| `lib/presentation/providers/palletizing_provider.dart` | owns palletizing data, per-line selections, summaries, create pallet | add explicit per-line authorization state, restore/verify/clear methods, stop create flow from depending on manual selected operator | Medium to high | Large |
| `lib/presentation/widgets/production_line_section.dart` | renders per-line UI, operator/product fields, summary, create button | replace operator dropdown with read-only authorized operator display, add section-scoped blocking overlay, disable pallet actions before authorization | High | Large |
| `lib/presentation/widgets/create_pallet_dialog.dart` | collects operator, product, quantity before create | remove operator selector, consume authorized operator from provider, optionally simplify dialog further | Medium | Medium |
| `lib/presentation/screens/palletizing_screen.dart` | scaffold, tabs/split layout, initial load, refresh, handover entry | trigger authorization restoration after data load, ensure refresh does not incorrectly clear line auth, possibly surface current tab operator in app bar | Medium | Medium |
| `lib/data/repositories/palletizing_repository_impl.dart` | current palletizing API methods | add new line-authorization endpoints, remove manual operatorId from create-pallet request when backend is ready | Medium | Medium |
| `lib/domain/repositories/palletizing_repository.dart` | palletizing contract | extend contract with line authorization methods | Low to medium | Medium |
| `lib/data/models/operator_model.dart` and `lib/domain/entities/operator.dart` | operator parsing/display | likely reusable for authorized-operator responses; may need no change or a small extension | Low | Small |
| new authorization model/entity files | none today | add a frontend model for line authorization state or API responses | Low | Small |
| `lib/presentation/widgets/pallet_success_dialog.dart` | success + print action | guard printing against line unauthorized state if business requires print to be blocked too | Medium | Medium |
| `lib/core/exceptions/api_exception.dart` | maps backend codes to Arabic display text | add new error code mappings for PIN/authorization outcomes | Low | Small |
| `lib/main.dart` / `AuthWrapper` | app root auth gate + pending handover blocking | if the app should truly remove the root login screen, this root flow must be redesigned around a different session bootstrap | High | Large |
| `lib/presentation/providers/auth_provider.dart` / `lib/presentation/screens/login_screen.dart` / `lib/data/repositories/auth_repository_impl.dart` | global app login | only change if product removes root app login; otherwise keep separate from line authorization | High if touched | Large if touched |
| `lib/presentation/widgets/shift_handover_dialog.dart` | manual outgoing operator selection for handover | not required for first pallet auth phase, but remains inconsistent with PIN-derived operator identity | Medium | Medium |
| `lib/presentation/widgets/pending_handover_dialog.dart` | manual incoming operator selection for confirm/reject | same as above; likely follow-up review item | Medium | Medium |

## 9.2 Testing and Safety Note

Current automated UI coverage is effectively absent for this workflow.

`test/widget_test.dart` is still the default counter smoke test and does not cover:

- auth flow
- tabs
- palletizing provider
- dialogs
- printing
- handover

So refactor risk is higher than usual unless manual test coverage is planned carefully.

# 10. Current UI Logic That Must Be Removed or Reworked

## 10.1 Operator Dropdown Widgets

These pallet-flow widgets conflict directly with the new requirement:

- `ProductionLineSection._buildOperatorField`
- `CreatePalletDialog._buildOperatorDropdown`

They should not remain as editable operator selectors in the new flow.

## 10.2 Operator Loading Logic for Selection

These current assumptions are tied to dropdown-based operator selection:

- `PalletizingProvider.loadInitialData()` loading all operators for the pallet screen
- `PalletizingRepositoryImpl.getOperators()`
- `AuthWrapper._loadOperators()` fetching operators for pending handover support

Recommended nuance:

- remove operator loading from the pallet creation path
- keep it only where still required by other workflows if those workflows remain manual

## 10.3 Validation Logic Tied to Dropdown Selection

Current create validation is tied to UI selection:

- `CreatePalletDialog._canConfirm()`

This must be reworked so the source of truth is:

- line authorization state

not:

- selected operator from dialog UI

## 10.4 Request-Building Code That Injects `operatorId` Manually

These current layers explicitly pass manual operator identity:

- `ProductionLineSection._showCreateDialog()`
- `PalletizingProvider.createPallet(...)`
- `PalletizingRepositoryImpl.createPallet(...)`

This is one of the main logic chains that must be changed.

## 10.5 Assumptions That Selected Operator Comes From UI

These current assumptions should be removed:

- selected operator is a dropdown choice
- selected operator may be changed freely immediately before create
- operator may be chosen from the same global list for both lines
- operator identity is temporary UI state rather than verified backend state

## 10.6 App Bar Terminology That May Become Misleading

Current desktop app bar shows:

- `المناوب: {userName}`

This comes from `AuthProvider.user`, not from the line operator state.

If the product shifts to line-scoped operator responsibility, this wording may become misleading unless it is intentionally repurposed to mean:

- device user
- kiosk session user
- supervisor session

## 10.7 Adjacent Manual Operator Flows That May Need Follow-Up

Even if the first implementation phase only changes pallet creation, these flows still encode operator identity through dropdowns:

- shift handover creation
- pending handover confirm/reject

They do not have to be changed in the first pass unless business wants that scope now, but they should be explicitly reviewed.

# 11. Recommended API Contract From Frontend Perspective

## 11.1 General Contract Principles

From the frontend perspective, the ideal contract is:

- line-scoped
- backend-authoritative
- compatible with current `{ success, data, error }` envelope
- explicit about error codes

The frontend should not have to:

- look up operator by dropdown
- guess whether that operator belongs to the line
- attach manual `operatorId` to create-pallet requests

## 11.2 Verify PIN for Line

### Recommended endpoint

`POST /palletizing/lines/{lineId}/authorize-pin`

### Request

```json
{
  "pin": "1234"
}
```

### Success response

```json
{
  "success": true,
  "data": {
    "lineId": 7,
    "lineNumber": 1,
    "authorized": true,
    "authorizedAt": "2026-04-01T10:15:00Z",
    "operator": {
      "id": 12,
      "name": "أحمد خالد",
      "code": "1042",
      "displayLabel": "أحمد خالد (1042)"
    }
  }
}
```

### Frontend reaction

- mark line as authorized
- close overlay/card
- show operator name in line UI
- enable product and pallet actions

## 11.3 Get Current Authorized Operator for Line

### Recommended endpoint

`GET /palletizing/lines/{lineId}/authorized-operator`

### Authorized response

```json
{
  "success": true,
  "data": {
    "lineId": 7,
    "lineNumber": 1,
    "authorized": true,
    "authorizedAt": "2026-04-01T10:15:00Z",
    "operator": {
      "id": 12,
      "name": "أحمد خالد",
      "code": "1042",
      "displayLabel": "أحمد خالد (1042)"
    }
  }
}
```

### No-authorization response

```json
{
  "success": true,
  "data": {
    "lineId": 7,
    "lineNumber": 1,
    "authorized": false,
    "authorizedAt": null,
    "operator": null
  }
}
```

### Frontend reaction

- call this on startup or after production lines load
- hydrate per-line authorization state
- keep unauthorized lines blocked

## 11.4 Clear or Replace Authorized Operator for Line

Two backend styles are acceptable.

### Option A: Explicit clear

`DELETE /palletizing/lines/{lineId}/authorized-operator`

### Success response

```json
{
  "success": true,
  "data": {
    "lineId": 7,
    "authorized": false
  }
}
```

### Option B: Replace implicitly by verifying a new PIN

`POST /palletizing/lines/{lineId}/authorize-pin`

If a line already has an operator and a new valid PIN is entered:

- backend replaces the current authorized operator
- response returns the new operator

From the frontend point of view, implicit replace is simpler.

## 11.5 Create Pallet Without Free Manual Operator Selection

### Recommended request

`POST /palletizing/pallets`

```json
{
  "productionLineId": 7,
  "productTypeId": 19,
  "quantity": 20
}
```

### Success response

Keep the current response style and still return the resolved operator:

```json
{
  "success": true,
  "data": {
    "palletId": 912,
    "scannedValue": "....",
    "qrCodeData": "....",
    "operator": {
      "id": 12,
      "name": "أحمد خالد",
      "code": "1042"
    },
    "productType": {
      "id": 19,
      "name": "....",
      "productName": "....",
      "prefix": "....",
      "color": "....",
      "packageQuantity": 20,
      "packageUnit": "BAG",
      "packageUnitDisplayName": "كيس",
      "imageUrl": "...."
    },
    "productionLine": {
      "id": 7,
      "name": "خط 1",
      "code": "LINE_1",
      "lineNumber": 1
    },
    "quantity": 20,
    "currentDestination": "....",
    "createdAt": "2026-04-01T10:17:00Z",
    "createdAtDisplay": "...."
  }
}
```

Returning operator info remains useful because:

- it confirms which operator backend resolved
- success dialog still needs to display the responsible operator

## 11.6 Expected Error Responses and UI Reaction

Recommended backend error codes:

| Error Code | Meaning | Frontend Reaction |
| --- | --- | --- |
| `INVALID_PIN` | wrong 4-digit PIN | inline error, clear PIN, keep line blocked |
| `OPERATOR_NOT_FOUND` | PIN not tied to operator | inline error |
| `OPERATOR_INACTIVE` | operator inactive | inline error |
| `OPERATOR_NOT_ASSIGNED_TO_LINE` | operator cannot work on this line | inline error |
| `LINE_AUTH_REQUIRED` | create/print attempted without authorization | keep controls blocked, optionally reopen overlay |
| `LINE_AUTH_CONFLICT` | backend refuses replacing current operator without additional action | show blocking message / confirm flow if later supported |
| `PRODUCTION_LINE_INACTIVE` | line inactive | disable section and show non-retryable warning |
| `UNAUTHORIZED` | app session expired | app-level session recovery |
| `NETWORK_ERROR` / `TIMEOUT_ERROR` | connectivity problem | inline retry state |

## 11.7 Optional but Highly Useful Backend Addition

An optional bulk endpoint would improve startup performance:

`GET /palletizing/line-authorizations`

Example:

```json
{
  "success": true,
  "data": [
    {
      "lineId": 7,
      "lineNumber": 1,
      "authorized": true,
      "authorizedAt": "2026-04-01T10:15:00Z",
      "operator": {
        "id": 12,
        "name": "أحمد خالد",
        "code": "1042",
        "displayLabel": "أحمد خالد (1042)"
      }
    },
    {
      "lineId": 8,
      "lineNumber": 2,
      "authorized": false,
      "authorizedAt": null,
      "operator": null
    }
  ]
}
```

This is not required, but it fits the current screen well because the screen always loads both hardcoded lines together.

## 11.8 Important Session Architecture Note

If the app should truly open directly to the pallet screen with no root login screen at all, then from frontend perspective the backend must also provide a replacement for current bearer-token login.

Examples:

- device-bound token
- kiosk session endpoint
- bootstrap session for the installed tablet

Without that, the current `ApiClient` and all protected palletizing endpoints still require the existing global auth flow.

# 12. Edge Cases

| Case | Recommended Frontend Handling |
| --- | --- |
| Line 1 blocked, Line 2 working | show authorization overlay only on Line 1; Line 2 remains interactive |
| Operator authorized on one line only | store state independently; do not mirror to the other line |
| Same operator on both lines | allow if backend allows; frontend should not invent a restriction |
| App restart and restoring authorized state | after line data loads, fetch current authorization for each line and hydrate state from backend |
| Switching tabs repeatedly | do not re-prompt if the line is already authorized; do show the overlay every time an unauthorized tab becomes active |
| Pull-to-refresh on one line | do not clear the other line's authorization; current shared refresh behavior should be reworked |
| Open pallet exists and operator changes | frontend should defer to backend; if backend rejects replacement, show the returned message and keep existing authorization |
| Wrong PIN | inline error, clear PIN field, stay on overlay |
| Correct PIN but operator not assigned to this line | inline line-specific error, keep overlay open |
| Network timeout during authorization | show retry state in the same overlay; do not unlock the line |
| Session expired | treat as app-level problem, not just line problem; session recovery must happen before line authorization can continue |
| Pallet create pressed while unauthorized | button should already be disabled; if backend still returns `LINE_AUTH_REQUIRED`, keep overlay visible and show error |
| Summary visible but create button disabled | acceptable and recommended; summary is read-only information |
| Printing attempted while unauthorized | print button should be disabled or guarded; current dialog will need a line-auth check if this rule must hold strictly |
| One line authorization loading while other line is used | fully acceptable; loading state must be per line |
| Desktop with both lines unauthorized on first load | each pane can show its own authorization overlay/card simultaneously |
| Mobile tab switched to unauthorized line | overlay appears immediately when tab becomes visible |
| Backend returns no authorization info yet | line remains blocked until authorization state is explicitly known |
| Production line entity missing from initial load | frontend should avoid silently trusting `line.number` as `productionLineId` for authorization-critical actions; this should be treated as a data integrity issue |

# 13. Suggested Migration Strategy

The safest migration sequence, based on the current codebase, is:

## Step 1: Add explicit per-line authorization state

In `PalletizingProvider`:

- add a dedicated authorization map keyed by line number
- add loading/error fields per line
- add methods to restore authorization and verify PIN

Do not remove existing operator dropdowns yet.

Why first:

- this establishes the correct state model before touching UI behavior

## Step 2: Add backend integration for line authorization

Extend:

- `PalletizingRepository`
- `PalletizingRepositoryImpl`

Add:

- verify PIN for line
- get current authorized operator for line
- clear/replace authorized operator for line

Hydrate authorization state after production lines are loaded.

## Step 3: Introduce section-scoped blocking overlay

In `ProductionLineSection`:

- add the line-specific blocking overlay/card
- block product/create actions when unauthorized
- keep summary visible

Why here:

- this matches the current per-line UI boundary
- this avoids global blocking

## Step 4: Replace operator dropdown with read-only operator display

Still in `ProductionLineSection`:

- remove interactive operator picker from pallet flow
- show authorized operator display instead
- add optional `change operator` action

## Step 5: Update create-pallet flow

Change:

- `CreatePalletDialog`
- `ProductionLineSection._showCreateDialog()`
- `PalletizingProvider.createPallet()`
- `PalletizingRepositoryImpl.createPallet()`

Goal:

- create request no longer accepts manual operator selection
- backend determines operator from line authorization

## Step 6: Guard printing by line authorization if business requires strict blocking

Update `PalletSuccessDialog` so that:

- printing is not allowed when the line is unauthorized

This may require:

- passing line number or line authorization into the dialog
- or resolving it from the pallet response line data

## Step 7: Remove old pallet-flow operator selection logic

After the new flow is stable:

- delete obsolete operator dropdown logic from pallet creation
- remove selection-specific validation
- remove `selectedOperator` as a create-pallet dependency

Important nuance:

- keep operator loading only where still needed for handover flows, unless those flows are also migrated

## Step 8: Decide separately whether to remove the root app login screen

This should be a separate architectural decision.

Why:

- the current global login screen is tied to API bearer-token auth
- line PIN authorization does not automatically replace that

Recommended approach:

- first finish line authorization inside the existing session architecture
- only then remove/replace the root login screen if backend provides a kiosk/device session model

# 14. Exact Code References

| File | Key Symbols / Areas | Why It Matters |
| --- | --- | --- |
| `lib/main.dart` | `MyApp`, `AuthWrapper` | app root, provider wiring, login gate, global pending-handover blocking |
| `lib/presentation/providers/auth_provider.dart` | `checkAuthStatus()`, `pinLogin()`, `logout()` | current global auth/session state |
| `lib/presentation/screens/login_screen.dart` | `_handleLogin()`, `_buildPinInput()` | current root 4-digit PIN login UI |
| `lib/data/repositories/auth_repository_impl.dart` | `pinLogin()` | current `/auth/pin-login` integration and token persistence |
| `lib/data/datasources/auth_local_storage.dart` | token/user storage helpers | explains why app auth survives restart while line operator selection does not |
| `lib/data/datasources/api_client.dart` | bearer token injection, `401` mapping, request envelope parsing | shared HTTP behavior and session assumptions |
| `lib/presentation/screens/palletizing_screen.dart` | `initState()`, `_buildBody()`, `_refreshData()`, `_handleShiftHandover()` | initial pallet data load, tab/split layout, shared refresh, handover entry |
| `lib/core/constants.dart` | UI `ProductionLine` enum | hardcoded two-line UI model, line number mapping, colors, labels |
| `lib/presentation/widgets/production_line_section.dart` | `_buildOperatorField()`, `_buildProductField()`, `_buildSummaryCard()`, `_buildCreateButton()`, `_showCreateDialog()` | the main per-line workflow UI and the best place for a line-scoped auth overlay |
| `lib/presentation/widgets/create_pallet_dialog.dart` | `_buildOperatorDropdown()`, `_buildProductDropdown()`, `_canConfirm()` | current duplicate operator/product selection and create validation |
| `lib/presentation/widgets/pallet_success_dialog.dart` | `_handlePrint()`, print action button, operator display | current post-create printing UI and where print authorization may need guarding |
| `lib/presentation/providers/palletizing_provider.dart` | `loadInitialData()`, `selectOperator()`, `selectProductType()`, `createPallet()`, maps keyed by line number | main state layer that should own per-line authorization next |
| `lib/data/repositories/palletizing_repository_impl.dart` | `getOperators()`, `getProductTypes()`, `getProductionLines()`, `getLineSummary()`, `createPallet()` | current screen API integration and manual `operatorId` injection |
| `lib/domain/repositories/palletizing_repository.dart` | current repository contract | must be extended for line authorization endpoints |
| `lib/domain/entities/operator.dart` | `Operator` shape | reusable display model for authorized operator info |
| `lib/domain/entities/production_line.dart` | backend line entity | needed to relate UI line number to backend line id |
| `lib/domain/entities/line_summary.dart` | current summary shape | shows what summary data already exists and what the UI ignores |
| `lib/domain/entities/pallet_create_response.dart` | create response shape | confirms backend already returns operator info on success |
| `lib/presentation/providers/shift_handover_provider.dart` | pending handover checks and confirm/reject | relevant because it shows a current blocking pattern and still depends on manual operator identity |
| `lib/presentation/widgets/shift_handover_dialog.dart` | operator selector + handover items | adjacent operator-dependent workflow |
| `lib/presentation/widgets/pending_handover_dialog.dart` | operator selector for confirm/reject | another adjacent operator-dependent workflow |
| `lib/data/repositories/shift_handover_repository_impl.dart` | handover endpoints using `operatorId` / `incomingOperatorId` | shows manual operator assumptions still exist outside pallet creation |
| `lib/presentation/widgets/summary_card.dart` | summary rendering | useful because summary should likely remain visible even when a line is blocked |
| `test/widget_test.dart` | default counter smoke test | confirms meaningful workflow test coverage is not in place yet |

## Useful Start-Line References

- `lib/main.dart`
  - `AuthWrapper` starts around line 60
- `lib/presentation/screens/palletizing_screen.dart`
  - `PalletizingScreen` starts around line 17
  - initial data load in `initState()` around lines 39-44
  - shared refresh around lines 474-479
  - hardcoded line entity resolution around lines 528-534
- `lib/presentation/widgets/production_line_section.dart`
  - `_buildOperatorField()` around line 155
  - `_buildProductField()` around line 234
  - `_buildSummaryCard()` around line 656
  - `_buildCreateButton()` around line 672
  - create request building around lines 716-746
- `lib/presentation/providers/palletizing_provider.dart`
  - per-line maps around lines 27-31
  - `loadInitialData()` around line 53
  - `createPallet()` around line 119
- `lib/presentation/widgets/create_pallet_dialog.dart`
  - operator dropdown around line 114
  - product dropdown around line 187
  - create validation around line 349
- `lib/presentation/screens/login_screen.dart`
  - `_handleLogin()` around line 83
  - PIN UI around line 253
- `lib/data/repositories/palletizing_repository_impl.dart`
  - create-pallet POST body around lines 56-64

# 15. Final Frontend Recommendation

The best frontend UX for this feature is:

- no manual operator dropdown in the pallet flow
- each line owns its own authorization state
- unauthorized lines show a section-scoped blocking PIN overlay
- authorized lines show a read-only responsible-operator display
- create and print actions rely on backend-authorized line identity, not a free `operatorId` chosen in the UI

The best state shape is:

- explicit per-line authorization objects inside `PalletizingProvider`
- not reuse of `selectedOperator`
- plus optional per-line async flags if full line independence is required

The safest integration approach is:

1. keep the existing `Provider` architecture
2. extend `PalletizingProvider` with line authorization state
3. add line authorization endpoints to the palletizing repository
4. place the blocking overlay inside `ProductionLineSection`
5. remove operator selection from the create flow
6. only then clean old dropdown-dependent code

What should be removed:

- operator dropdown from `ProductionLineSection`
- operator dropdown from `CreatePalletDialog`
- create-pallet request building that manually injects `operatorId`
- validation logic that treats operator as a UI choice rather than verified line state

What should remain:

- `PalletizingProvider` as the main workflow provider
- `ProductionLineSection` as the line UI boundary
- line-specific maps keyed by `line.number`
- current backend create response structure that returns operator data
- summary visibility even when a line is blocked

What backend behavior frontend must rely on:

- line-specific PIN verification
- line-specific current authorized operator restoration
- line-specific clear/replace behavior
- create-pallet authorization derived from backend line state, not manual `operatorId`
- explicit error codes for wrong PIN, line mismatch, inactive operator, and missing authorization

The single most important architectural recommendation is this:

- keep app/session authentication and line/operator authorization as two separate concepts
- but move all line responsibility logic into explicit per-line state, not dropdown state

That gives the frontend a clean path from the current codebase to the desired operator PIN authorization model with the least unnecessary breakage.
