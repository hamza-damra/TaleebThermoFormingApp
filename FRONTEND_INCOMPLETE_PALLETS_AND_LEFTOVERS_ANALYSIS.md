# Frontend Analysis: Incomplete Pallets & Leftover Cartons

**Generated**: April 5, 2026  
**Scope**: Current frontend implementation reality — no redesign recommendations acted upon  
**App**: Taleeb ThermoForming Palletizing App (Flutter)  
**Architecture**: Clean Architecture (Domain/Data/Presentation) + Provider (ChangeNotifier)

---

## 1. Executive Summary

The frontend currently treats **incomplete pallets** and **leftover cartons (فالت)** as **two distinct concepts** at every layer — entities, API calls, state management, and UI rendering. However, they share a **single entry-point screen** called "فالت" (Open Items), which is a unified view combining both concepts under one roof.

### How the two concepts are separated

| Aspect                    | Incomplete Pallet (طبلية ناقصة)                                    | Leftover Cartons (فالت / عبوات فالتة)                                         |
| ------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| **Entity**                | `ReceivedIncompletePallet`                                         | `LooseBalanceItem`                                                            |
| **API response wrapper**  | `OpenItemsResponse.receivedIncompletePallet` (nullable, singular)  | `OpenItemsResponse.looseBalances` (list)                                      |
| **Origin**                | Always from a confirmed handover (`sourceHandoverId` mandatory)    | Two origins: `CARRIED_FROM_HANDOVER` or current session (from product-switch) |
| **Action**                | "إكمال الطبلية" via `CompleteIncompletePalletDialog`               | "إنشاء طبلية" via `ProducePalletFromLooseDialog`                              |
| **API endpoint**          | `POST /palletizing-line/lines/{lineId}/incomplete-pallet/complete` | `POST /palletizing-line/lines/{lineId}/loose-balances/produce-pallet`         |
| **Multiplicity per line** | Max 1 (nullable)                                                   | 0..N (list of product types)                                                  |
| **Session table column**  | Not shown explicitly (only the resulting pallet shows)             | Shown in "الفالت" column in session table                                     |

### Where they overlap

- Both live under the `OpenItemsResponse` entity and the **single** "فالت" button / `OpenItemsScreen`.
- Both can appear in the **handover creation dialog** (`HandoverCreationDialog`) — the outgoing operator can declare incomplete pallets AND loose balances simultaneously.
- Both appear read-only in the **handover review card** (`LineHandoverCard`) for the incoming operator.
- Both are refreshed together via `fetchOpenItems()` and `_refreshLineStateFromBackend()`.

### Key finding

The frontend correctly separates the two at the data/state layer, but the UX bundles them into a single screen (Open Items) and the user must mentally distinguish between the purple "طبلية ناقصة مستلمة" card and the line-colored "العبوات الفالتة" cards. The naming on the entry button is simply "فالت" which could be read as applying to either concept.

---

## 2. Terminology and Naming Analysis

### 2.1 All terms found in code and UI

| Arabic UI Label                  | English Code Name                                    | Where Used                                               | Refers To                                          |
| -------------------------------- | ---------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------- |
| فالت                        | `OpenItemsScreen` (widget), `open_items_screen.dart` | Button on main screen, AppBar title                      | Combined screen for both concepts                  |
| العبوات الفالتة                  | Section header in `OpenItemsScreen._buildBody()`     | Open items screen, section above loose cards             | Leftover cartons                                   |
| طبلية ناقصة مستلمة               | Section header in `OpenItemsScreen._buildBody()`     | Open items screen, section for incomplete pallet         | Received incomplete pallet                         |
| إنشاء طبلية                      | Button on loose balance card                         | `OpenItemsScreen._buildLooseBalanceCard()`               | Action: create pallet from leftovers               |
| إنشاء طبلية من الفالت            | Dialog title                                         | `ProducePalletFromLooseDialog`                           | Create pallet from loose cartons                   |
| إكمال الطبلية                    | Button on incomplete pallet card                     | `OpenItemsScreen._buildIncompletePalletCard()`           | Action: complete incomplete pallet                 |
| إكمال الطبلية الناقصة            | Dialog title                                         | `CompleteIncompletePalletDialog`                         | Complete an incomplete pallet                      |
| لا توجد عناصر فالتة         | Empty state text                                     | `OpenItemsScreen._buildEmptyState()`                     | No open items at all                               |
| جميع العناصر تمت معالجتها        | Empty state subtitle                                 | `OpenItemsScreen._buildEmptyState()`                     | All items processed                                |
| تبديل نوع المنتج                 | Dialog title                                         | `ProductSwitchDialog`                                    | Product switch                                     |
| هل يوجد عبوات فالتة (فالتة) | Question in product switch dialog                    | `ProductSwitchDialog._buildStep0` area                   | Asks about leftover cartons when switching product |
| لا يوجد فالت                     | Toggle in product switch dialog                      | `ProductSwitchDialog`                                    | No leftovers                                       |
| نعم يوجد فالت                    | Toggle in product switch dialog                      | `ProductSwitchDialog`                                    | Yes leftovers exist                                |
| عدد العبوات الفالتة              | Input label in product switch                        | `ProductSwitchDialog`                                    | Leftover carton count                              |
| فالت                             | Session table column header                          | `SessionTableWidget._buildTable()`                       | Loose package count per product type               |
| تسليم مناوبة                     | Button + dialog title                                | `HandoverCreationDialog`, `production_line_section.dart` | Shift handover                                     |
| هل يوجد طبليات ناقصة؟            | Toggle in handover creation step 0                   | `HandoverCreationDialog._buildStep0()`                   | Incomplete pallets toggle                          |
| هل يوجد فالت؟                    | Toggle in handover creation step 0                   | `HandoverCreationDialog._buildStep0()`                   | Loose balances toggle                              |
| طبلية ناقصة                      | Section header in handover form                      | `HandoverCreationDialog._buildStep1()`                   | Incomplete pallet form section                     |
| ملخص الفالت                      | Section header in handover form + review card        | `HandoverCreationDialog`, `LineHandoverCard`             | Loose balances summary                             |
| تسليم نظيف — بدون عناصر معلقة    | Case chip                                            | `HandoverCreationDialog._buildCaseChip()`                | Clean handover (NONE)                              |
| طبليات ناقصة فقط                 | Case chip                                            | `HandoverCreationDialog._buildCaseChip()`                | INCOMPLETE_PALLET_ONLY                             |
| فالت فقط                         | Case chip                                            | `HandoverCreationDialog._buildCaseChip()`                | LOOSE_BALANCES_ONLY                                |
| طبليات ناقصة وفالت               | Case chip                                            | `HandoverCreationDialog._buildCaseChip()`                | BOTH                                               |
| من تسليم                         | Origin badge on loose balance card                   | `OpenItemsScreen._buildOriginBadge()`                    | Loose balance from handover                        |
| الجلسة الحالية                   | Origin badge on loose balance card                   | `OpenItemsScreen._buildOriginBadge()`                    | Loose balance from current session                 |
| من تسليم سابق                    | Sub-badge in produce-pallet dialog                   | `ProducePalletFromLooseDialog`                           | Loose balance transferred from prior handover      |
| مستلم من تسليم #                 | Source indicator in complete-pallet dialog           | `CompleteIncompletePalletDialog`                         | Received from handover ID                          |
| الرصيد المتاح                    | Info chip in produce-pallet dialog                   | `ProducePalletFromLooseDialog`                           | Available loose count                              |
| حجم الطبلية                      | Info chip in produce-pallet dialog                   | `ProducePalletFromLooseDialog`                           | Package quantity for the product type              |
| تكوين طبليات                     | AppBar title                                         | `PalletizingScreen._buildAppBar()`                       | Main screen title                                  |
| ملخص المناوبة                    | Session table header                                 | `SessionTableWidget`                                     | Shift summary table                                |
| ماكنة 1 / ماكنة 2                | Tab labels                                           | `PalletizingScreen._buildAppBar()`                       | Machine/line tabs                                  |
| خط الإنتاج 1 / خط الإنتاج 2      | `ProductionLine.arabicLabel`                         | Constants enum, summary card                             | Production line labels                             |

### 2.2 Naming inconsistencies

| Issue                                                   | Details                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **"فالت" button ambiguity**                        | The button text means "Incomplete" but the screen shows BOTH incomplete pallets AND loose balances. The button could mislead users into thinking it only shows incomplete pallets.                                                                                                                                    |
| **Two distinct `LooseBalanceItem` classes**             | `lib/domain/entities/loose_balance_item.dart` and `lib/domain/entities/line_handover_info.dart` each define a `LooseBalanceItem` class with different fields. The one in `loose_balance_item.dart` has `origin` and `sourceHandoverId`; the one in `line_handover_info.dart` does not. This is a **naming conflict**. |
| **"فالتة" vs "فالته" vs "فالت"**                        | The word "فالت" appears in different forms across the UI. The section header uses "العبوات الفالتة" (correct feminine plural), the toggle uses "فالت" (masculine shorthand). This is acceptable colloquially but inconsistent.                                                                                        |
| **"طبليات ناقصة" (plural) vs "طبلية ناقصة" (singular)** | The handover step 0 asks "هل يوجد طبليات ناقصة؟" (plural) but the backend and entity only support a single incomplete pallet per handover per line. The UI case chip says "طبليات ناقصة فقط" (plural) but only one can be specified. **This is misleading.**                                                          |
| **"مشتاح" / "طلبية" not used**                          | The terms مشتاح (pallet in Levantine dialect) and طلبية (order) are **not found** in the current frontend code. The code consistently uses "طبلية" (pallet).                                                                                                                                                          |
| **product-switch dialog parenthetical**                 | The question reads "هل يوجد عبوات فالتة (فالتة)" where "(فالتة)" is parenthetical but confuses the two concepts — leftover cartons are not the same as incomplete pallets.                                                                                                                                  |
| **"ماكنة" vs "خط الإنتاج"**                             | Tab labels say "ماكنة 1" (machine) and summary labels say "خط الإنتاج 1" (production line). These are used interchangeably but refer to the same entity.                                                                                                                                                              |
| **Code paths use "lineNumber" everywhere**              | The `ProductionLine` constants enum (`line1`, `line2`) is in `core/constants.dart` and conflates with the entity `production_line.dart`. Both exist under different import aliases (`constants.ProductionLine` vs `entity.ProductionLine`).                                                                           |

### 2.3 English code names vs Arabic UI

| English Code                     | Arabic UI Counterpart  |
| -------------------------------- | ---------------------- |
| `OpenItemsScreen`                | فالت              |
| `LooseBalanceItem`               | العبوات الفالتة / فالت |
| `ReceivedIncompletePallet`       | طبلية ناقصة مستلمة     |
| `ProducePalletFromLooseDialog`   | إنشاء طبلية من الفالت  |
| `CompleteIncompletePalletDialog` | إكمال الطبلية الناقصة  |
| `ProductSwitchDialog`            | تبديل نوع المنتج       |
| `HandoverCreationDialog`         | تسليم مناوبة           |
| `LineHandoverCard`               | تسليم مناوبة معلق      |
| `SessionTableWidget`             | ملخص المناوبة          |
| `SummaryCard`                    | ملخص (line label)      |

---

## 3. Screen Inventory

### 3.1 PalletizingScreen (Main Screen)

| Property             | Value                                                                   |
| -------------------- | ----------------------------------------------------------------------- |
| **File**             | `lib/presentation/screens/palletizing_screen.dart`                      |
| **Route**            | Root screen (home via `DeviceKeyWrapper` → `PalletizingScreen`)         |
| **Purpose**          | Container for two production line tabs (ماكنة 1, ماكنة 2)               |
| **How reached**      | App startup after device key configuration                              |
| **Data displayed**   | Delegates to `ProductionLineSection` per tab                            |
| **Actions**          | Settings navigation, tab switching, pull-to-refresh (`loadBootstrap()`) |
| **State dependency** | `PalletizingProvider.state`, `PalletizingProvider.productionLines`      |
| **State scope**      | Global (single `PalletizingProvider` from `MultiProvider`)              |

### 3.2 ProductionLineSection (Per-line content)

| Property              | Value                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **File**              | `lib/presentation/widgets/production_line_section.dart`                                                                               |
| **Route**             | Embedded in `PalletizingScreen` tabs                                                                                                  |
| **Purpose**           | All per-line UI: operator display, product selector, session table, handover card, create button                                      |
| **How reached**       | Rendered for each tab                                                                                                                 |
| **Data displayed**    | Authorized operator, selected product type, session table, pending handover card                                                      |
| **Actions**           | Open items button, handover creation button, product selection, create pallet, confirm/reject handover                                |
| **State dependency**  | `PalletizingProvider` (per-line maps keyed by `lineNumber`)                                                                           |
| **UI mode driven by** | `lineUiMode` from backend: `NEEDS_AUTHORIZATION`, `PENDING_HANDOVER_NEEDS_INCOMING`, `PENDING_HANDOVER_REVIEW`, `AUTHORIZED`, or null |

### 3.3 OpenItemsScreen (Open Items / فالت)

| Property             | Value                                                                                                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **File**             | `lib/presentation/widgets/open_items_screen.dart`                                                                                                   |
| **Route**            | Push navigation via `MaterialPageRoute` (no named route)                                                                                            |
| **Purpose**          | Show loose balances and received incomplete pallet for a specific line                                                                              |
| **How reached**      | Tap "فالت" button on main screen (only visible when line is authorized and not blocked)                                                        |
| **Data displayed**   | `OpenItemsResponse.looseBalances` (cards) + `OpenItemsResponse.receivedIncompletePallet` (card)                                                     |
| **Actions**          | "إنشاء طبلية" per loose balance card → `ProducePalletFromLooseDialog`; "إكمال الطبلية" on incomplete pallet card → `CompleteIncompletePalletDialog` |
| **State dependency** | `PalletizingProvider.getOpenItems(lineNumber)`, `PalletizingProvider.isOpenItemsLoading(lineNumber)`                                                |
| **State scope**      | Per-line (keyed by `lineNumber`), API-backed, fetched on `initState`                                                                                |
| **Refresh**          | Pull-to-refresh via `RefreshIndicator` → `fetchOpenItems()`                                                                                         |

### 3.4 ProducePalletFromLooseDialog

| Property                    | Value                                                                                        |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| **File**                    | `lib/presentation/widgets/produce_pallet_from_loose_dialog.dart`                             |
| **Route**                   | `showDialog` from `OpenItemsScreen`                                                          |
| **Purpose**                 | Let operator specify how many loose cartons to use and optional fresh cartons to add         |
| **UI inputs**               | Loose quantity to use (pre-filled with available count), fresh quantity to add (default 0)   |
| **Returns**                 | `Map<String, int>?` with `looseQuantityToUse` and `freshQuantityToAdd`, or null if cancelled |
| **Validation**              | Loose qty must be > 0 and ≤ available balance; fresh qty must be ≥ 0                         |
| **State dependency**        | Stateless dialog; receives `LooseBalanceItem` and `packageQuantity` as parameters            |
| **API triggered by caller** | `PalletizingProvider.producePalletFromLoose()`                                               |

### 3.5 CompleteIncompletePalletDialog

| Property                    | Value                                                                                                |
| --------------------------- | ---------------------------------------------------------------------------------------------------- |
| **File**                    | `lib/presentation/widgets/complete_incomplete_pallet_dialog.dart`                                    |
| **Route**                   | `showDialog` from `OpenItemsScreen`                                                                  |
| **Purpose**                 | Let operator complete an inherited incomplete pallet, optionally adding fresh cartons                |
| **UI inputs**               | Toggle: "إكمال كما هو" (complete as-is) or "إضافة عبوات جديدة" (add fresh); optional fresh qty input |
| **Returns**                 | `int?` — 0 for complete as-is, N for fresh qty to add, null if cancelled                             |
| **Validation**              | If adding fresh, qty must be > 0                                                                     |
| **State dependency**        | Stateless dialog; receives `ReceivedIncompletePallet` as parameter                                   |
| **API triggered by caller** | `PalletizingProvider.completeIncompletePallet()`                                                     |

### 3.6 ProductSwitchDialog

| Property                    | Value                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------- |
| **File**                    | `lib/presentation/widgets/product_switch_dialog.dart`                                          |
| **Route**                   | `showDialog` from `ProductionLineSection._handleProductSelection()`                            |
| **Purpose**                 | When switching product type, ask whether there are leftover cartons from the previous product  |
| **UI inputs**               | Toggle: "لا يوجد فالت" / "نعم يوجد فالت"; if yes, numeric input for loose count                |
| **Returns**                 | `int?` — 0 for no leftovers, N for loose count, null if cancelled                              |
| **Validation**              | If has loose, count must be > 0                                                                |
| **API triggered by caller** | `PalletizingProvider.switchProduct()` → `POST /palletizing-line/lines/{lineId}/product-switch` |

### 3.7 HandoverCreationDialog

| Property                    | Value                                                                                                                                                                  |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **File**                    | `lib/presentation/widgets/handover_creation_dialog.dart`                                                                                                               |
| **Route**                   | `showDialog` (barrierDismissible: false) from `ProductionLineSection._handleCreateHandover()`                                                                          |
| **Purpose**                 | Multi-step dialog for outgoing operator to create shift handover                                                                                                       |
| **Step 0**                  | Two toggles: "هل يوجد طبليات ناقصة؟" and "هل يوجد فالت؟"                                                                                                               |
| **Step 1**                  | Dynamic form based on selections: incomplete pallet form (product type + quantity), loose balances form (dynamic rows with product type + count), notes (always shown) |
| **Returns**                 | `HandoverCreationResult?` with optional incompletePalletProductTypeId, incompletePalletQuantity, looseBalances list, notes                                             |
| **Validation**              | Product types + quantities must be valid; no duplicate product types in loose balances                                                                                 |
| **API triggered by caller** | `PalletizingProvider.createLineHandover()`                                                                                                                             |
| **Case enum**               | `_HandoverCase { none, incompletePalletOnly, looseBalancesOnly, both }`                                                                                                |

### 3.8 LineHandoverCard

| Property             | Value                                                                                                                      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **File**             | `lib/presentation/widgets/line_handover_card.dart`                                                                         |
| **Route**            | Embedded in `ProductionLineSection` (main screen and handover review layout)                                               |
| **Purpose**          | Read-only display of pending handover details; optional confirm/reject actions                                             |
| **Data**             | Outgoing operator, time, handover type, notes, incomplete pallet info, loose balances summary                              |
| **Actions**          | "معلومات دقيقة وتأكيد التسليم" (confirm), "تسليم غير دقيق وتأكيد الاستلام" (reject) — only when `showResolveActions: true` |
| **State dependency** | `LineHandoverInfo` passed as prop                                                                                          |

### 3.9 SessionTableWidget

| Property                  | Value                                                                                              |
| ------------------------- | -------------------------------------------------------------------------------------------------- |
| **File**                  | `lib/presentation/widgets/session_table_widget.dart`                                               |
| **Purpose**               | Displays session/shift summary as a table with columns: نوع المنتج, الطبليات, العبوات, الفالت      |
| **Loose column behavior** | Rows with `hasLooseBalance == true` get orange highlight and a warning icon next to the فالت count |
| **Data**                  | `List<SessionTableRow>` from `PalletizingProvider.getSessionTable(lineNumber)`                     |

### 3.10 SummaryCard

| Property    | Value                                                                                                                                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **File**    | `lib/presentation/widgets/summary_card.dart`                                                                                                                                                                |
| **Purpose** | Shows pallet count and package count per line                                                                                                                                                               |
| **Status**  | Appears to be **legacy/unused** — `ProductionLineSection` renders `SessionTableWidget` instead. The summary card is still in the codebase but not referenced in the current `production_line_section.dart`. |
| **Note**    | Does NOT show loose balance or incomplete pallet information.                                                                                                                                               |

### 3.11 LineAuthOverlay

| Property      | Value                                                           |
| ------------- | --------------------------------------------------------------- |
| **File**      | `lib/presentation/widgets/line_auth_overlay.dart`               |
| **Purpose**   | PIN entry overlay for operator authentication on a line         |
| **Relevance** | Blocks all line actions (including open items) until authorized |

---

## 4. Current UX Flow

### 4.1 Normal Production Flow

1. App starts → `DeviceKeyWrapper` checks for device key → `PalletizingScreen` loads.
2. `loadBootstrap()` fires → fetches all lines, product types, per-line state.
3. If `lineUiMode == 'NEEDS_AUTHORIZATION'`: PIN overlay shown. Operator enters 4-digit PIN.
4. After auth: line content visible. Operator selects product type (confirmation dialog).
5. Operator taps "إنشاء طبلية جديدة" → `CreatePalletDialog` → `createPallet()` → `PalletSuccessDialog`.
6. After pallet creation: line state refreshed from backend. Session table updates.

### 4.2 Selecting / Changing Product Type

**First selection (no current product):**

1. Tap product dropdown → `SearchablePickerDialog` opens.
2. Select product → confirmation dialog with product image.
3. Confirm → `provider.selectProductType(lineNumber, product)` — **local state only, no API call**.

**Switching product (current product exists, different selected):**

1. Tap product dropdown → `SearchablePickerDialog`.
2. Select different product → `ProductSwitchDialog` opens.
3. Dialog asks: "هل يوجد عبوات فالتة (فالتة) من المنتج السابق؟"
4. If "لا يوجد فالت" → returns 0.
5. If "نعم يوجد فالت" → user enters count → returns N.
6. `provider.switchProduct()` called → `POST /palletizing-line/lines/{lineId}/product-switch` with `{ previousProductTypeId, loosePackageCount }`.
7. Backend returns updated `sessionTable` → stored in `_sessionTables[lineNumber]`.
8. On success: `provider.selectProductType(lineNumber, newProduct)` sets new product locally.
9. On failure: SnackBar with error message; product NOT changed.

**Same product selected again:**

- No switch dialog. Confirmation dialog only, same as first selection.

### 4.3 Opening Open Items / Incomplete Screen

1. "فالت" button visible only when `isLineAuthorized && !isLineBlocked`.
2. Tap → `OpenItemsScreen.show()` pushes new route.
3. `initState` → `provider.fetchOpenItems(lineNumber)` → `GET /palletizing-line/lines/{lineId}/open-items`.
4. Response parsed into `OpenItemsResponse` (list of `LooseBalanceItem` + optional `ReceivedIncompletePallet`).
5. Loose balances shown as cards with product name, count, origin badge ("من تسليم" or "الجلسة الحالية").
6. Incomplete pallet shown as a purple card with source handover ID.
7. If both sections empty → "لا توجد عناصر فالتة".

### 4.4 Creating Pallet from Loose Cartons

1. From `OpenItemsScreen`, tap "إنشاء طبلية" on a loose balance card.
2. `ProducePalletFromLooseDialog` opens with:
   - Available loose count (pre-filled in input).
   - Package quantity for product type (shown as info chip).
   - Fresh quantity input (default 0).
3. User adjusts quantities and confirms.
4. `provider.producePalletFromLoose()` → `POST /palletizing-line/lines/{lineId}/loose-balances/produce-pallet`.
5. On success: `PalletSuccessDialog` shows the created pallet. Open items and line state refreshed.
6. On failure: SnackBar with API error message.

### 4.5 Completing Incomplete Pallet

1. From `OpenItemsScreen`, tap "إكمال الطبلية" on the incomplete pallet card.
2. `CompleteIncompletePalletDialog` opens with:
   - Current quantity displayed.
   - Source handover ID displayed.
   - Toggle: "إكمال كما هو" (return 0) or "إضافة عبوات جديدة" (enter fresh qty).
3. User confirms.
4. `provider.completeIncompletePallet()` → `POST /palletizing-line/lines/{lineId}/incomplete-pallet/complete`.
5. On success: `PalletSuccessDialog`. Open items and line state refreshed.
6. On failure: SnackBar with error.

### 4.6 Shift Handover Creation (Outgoing Operator)

1. "تسليم مناوبة" button visible only when `canInitiateHandover(lineNumber) == true` (backend-driven flag).
2. Tap → `HandoverCreationDialog` opens (non-dismissible).
3. **Step 0**: Two toggles — incomplete pallet? loose balances?
4. Tap "التالي" → **Step 1**: Dynamic form:
   - If incomplete: product type picker + quantity input.
   - If loose: dynamic rows (product type + count per row), up to 50 rows.
   - Always: notes field (optional).
5. "تأكيد التسليم" → validation → `HandoverCreationResult` returned.
6. `provider.createLineHandover()` → `POST /palletizing-line/lines/{lineId}/handover`.
7. On success: SnackBar "تم إنشاء طلب التسليم بنجاح". Line state refreshed → `lineUiMode` transitions to `PENDING_HANDOVER_NEEDS_INCOMING`. Outgoing operator's auth is released by backend.
8. On failure: SnackBar with error.

### 4.7 Incoming Operator Handover Review

1. When a new operator authenticates on a line with a pending handover, backend returns `lineUiMode == 'PENDING_HANDOVER_REVIEW'`.
2. `ProductionLineSection` renders `_buildHandoverReviewLayout()` instead of normal content.
3. Review layout shows an orange header "مراجعة التسليم" and a `LineHandoverCard` with full details.
4. Two buttons:
   - "معلومات دقيقة وتأكيد التسليم" → `_handleConfirmHandover()` → `POST .../confirm`.
   - "تسليم غير دقيق وتأكيد الاستلام" → `_handleRejectHandover()` → rejection notes dialog → `POST .../reject`.
5. On confirm success: handover cleared, line returns to normal production mode. Open items now populated with carried items.
6. On reject success: SnackBar "تم رفض التسليم وسيتم مراجعته من قبل الإدارة".

### 4.8 End of Shift Scenarios

**End of shift with incomplete pallet only:**

- Outgoing operator opens handover dialog, enables "طبليات ناقصة" toggle, specifies product type and quantity.
- Backend records incomplete pallet in handover record.

**End of shift with leftovers only:**

- Outgoing operator opens handover dialog, enables "فالت" toggle, adds product types with counts.
- Backend records loose balances in handover record.

**End of shift with both:**

- Both toggles enabled. Both forms filled out.
- Backend records both.

**Clean handover (no open items):**

- Neither toggle enabled. Only notes (optional).
- Handover type: `NONE`.

### 4.9 Post-Refresh / App Restart Behavior

- **Pull-to-refresh**: Calls `loadBootstrap()` which resets ALL state from backend.
- **App restart**: `PalletizingScreen.initState()` calls `loadBootstrap()` — fresh state from server.
- **State persistence**: **None**. All state is in-memory only (`PalletizingProvider` fields). No local persistence (SharedPreferences/Hive) is used for palletizing state.
- **After bootstrap**: For lines in `PENDING_HANDOVER_REVIEW` mode, an extra `getLineHandover()` call fetches full handover details (bootstrap only provides summary).

### 4.10 Cancel / Dismiss Behavior

- **Product switch dialog cancelled** → null returned → no product change, no API call.
- **Handover creation dialog cancelled** → null returned → no API call.
- **Open items dialog cancelled** → null returned → no API call.
- **Handover reject notes cancelled** → null returned → reject not executed.

---

## 5. State Management Analysis

### 5.1 State Architecture

**Single provider**: `PalletizingProvider extends ChangeNotifier`  
**Scope**: Global (one instance in `MultiProvider` at app root)  
**Pattern**: Per-line state stored in `Map<int, T>` keyed by `lineNumber`

### 5.2 State Objects

| State Map               | Type                               | Scope    | Source                                               |
| ----------------------- | ---------------------------------- | -------- | ---------------------------------------------------- |
| `_productTypes`         | `List<ProductType>`                | Global   | Bootstrap API                                        |
| `_productionLines`      | `List<ProductionLine>`             | Global   | Bootstrap API                                        |
| `_lineAuthorizations`   | `Map<int, LineAuthorizationState>` | Per-line | Bootstrap + authorize API                            |
| `_sessionTables`        | `Map<int, List<SessionTableRow>>`  | Per-line | Bootstrap + line state API + product-switch response |
| `_selectedProductTypes` | `Map<int, ProductType?>`           | Per-line | Bootstrap + local selection                          |
| `_lastPalletResponses`  | `Map<int, PalletCreateResponse?>`  | Per-line | Create pallet API                                    |
| `_pendingHandovers`     | `Map<int, LineHandoverInfo?>`      | Per-line | Bootstrap + line state API + handover APIs           |
| `_blockedReasons`       | `Map<int, String?>`                | Per-line | Backend                                              |
| `_lineCreating`         | `Map<int, bool>`                   | Per-line | Local (loading state)                                |
| `_lineErrors`           | `Map<int, String?>`                | Per-line | Local (error messages)                               |
| `_lineSwitchingProduct` | `Map<int, bool>`                   | Per-line | Local (loading state)                                |
| `_lineUiModes`          | `Map<int, String?>`                | Per-line | Backend                                              |
| `_canInitiateHandovers` | `Map<int, bool>`                   | Per-line | Backend                                              |
| `_canConfirmHandovers`  | `Map<int, bool>`                   | Per-line | Backend                                              |
| `_canRejectHandovers`   | `Map<int, bool>`                   | Per-line | Backend                                              |
| `_openItems`            | `Map<int, OpenItemsResponse?>`     | Per-line | Open items API                                       |
| `_openItemsLoading`     | `Map<int, bool>`                   | Per-line | Local (loading state)                                |

### 5.3 Source of Truth

| Concept                           | Source of Truth                                                                                                                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Line authorization state          | Backend (refreshed after auth, after handover actions)                                                                                                                                      |
| Line UI mode                      | Backend (`lineUiMode` string: `NEEDS_AUTHORIZATION`, `PENDING_HANDOVER_REVIEW`, `PENDING_HANDOVER_NEEDS_INCOMING`, `AUTHORIZED`)                                                            |
| Selected product type             | **Hybrid**: Seeded from backend `selectedProductType` in bootstrap, but also locally overridden by user selection. Local selection does NOT write to backend except during pallet creation. |
| Session table                     | Backend (returned by bootstrap, line state, product-switch response, post-pallet-creation refresh)                                                                                          |
| Open items                        | Backend (fetched on demand, refreshed after produce-from-loose or complete-incomplete actions)                                                                                              |
| Pending handover                  | Backend (from bootstrap, line state refresh, post-handover creation/confirm/reject)                                                                                                         |
| Whether handover can be initiated | Backend (`canInitiateHandover` flag)                                                                                                                                                        |

### 5.4 Optimistic vs Server-Driven

| Operation                      | Optimistic?              | Details                                                                                                               |
| ------------------------------ | ------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| Product selection              | **Partially optimistic** | Selected product is set locally immediately. Only committed to backend during pallet creation or product-switch call. |
| Product switch                 | **Server-driven**        | Session table only updated from API response. If API fails, product type is NOT changed.                              |
| Pallet creation                | **Server-driven**        | Last pallet response stored from API. Line state refreshed from backend.                                              |
| Handover creation              | **Server-driven**        | Pending handover set from API response. Full line state refreshed.                                                    |
| Handover confirm/reject        | **Server-driven**        | Pending handover nulled. Line state refreshed.                                                                        |
| Open items fetch               | **Server-driven**        | Stored from API response.                                                                                             |
| Open items produce pallet      | **Server-driven**        | Both open items and line state refreshed after success.                                                               |
| Open items complete incomplete | **Server-driven**        | Both open items and line state refreshed after success.                                                               |

### 5.5 State Survival

| Scenario                                | Survives?                                                                                                       |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Navigate between tabs (Line 1 ↔ Line 2) | **Yes** — all state in single provider, keyed by lineNumber                                                     |
| Navigate to Open Items screen and back  | **Yes** — provider state persists; open items are in the per-line map                                           |
| Navigate to Settings and back           | **Yes** — provider not disposed                                                                                 |
| Pull-to-refresh                         | **Overwritten** — `loadBootstrap()` replaces ALL per-line state from backend                                    |
| App restart (cold start)                | **Lost** — all state is in-memory. `loadBootstrap()` restores from backend.                                     |
| Logout                                  | **Not applicable** — current auth flow uses device key, not login/logout. Provider is NOT recreated on re-auth. |

### 5.6 Line Isolation

- **Properly isolated**: All per-line state is keyed by `lineNumber`. Line 1 and Line 2 have completely separate maps.
- **Product types and production lines**: Global (shared across lines), correctly so.
- **Open items**: Properly scoped to lineNumber.
- **Handovers**: Properly scoped to lineNumber.

### 5.7 Loading / Error / Empty States

| State                          | Representation                                                                                                                               |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Global loading**             | `PalletizingState.loading` → shimmer loading screens                                                                                         |
| **Global error**               | `PalletizingState.error` + `_errorMessage` → error screen with retry button                                                                  |
| **Per-line creating**          | `_lineCreating[lineNumber]` → disabled create button + spinner                                                                               |
| **Per-line error**             | `_lineErrors[lineNumber]` → SnackBar shown by UI widget, then `clearLineError()`                                                             |
| **Open items loading**         | `_openItemsLoading[lineNumber]` → `CircularProgressIndicator`                                                                                |
| **Open items empty**           | `openItems == null \|\| openItems.isEmpty` → empty state illustration with "لا توجد عناصر فالتة"                                        |
| **Per-line switching product** | `_lineSwitchingProduct[lineNumber]` → **stored but not visually consumed in UI** (potential gap: no loading indicator during product switch) |

### 5.8 Race Condition Risks

| Risk                                                     | Details                                                                                                                                                                                                                                                                              |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Double-tap on create pallet**                          | Mitigated: `isLineCreating` disables the button during API call                                                                                                                                                                                                                      |
| **Double-tap on handover confirm/reject**                | **Partially mitigated**: `isResolving` prop on `LineHandoverCard` disables buttons, but `isResolving` is always `false` — it is never set to `true` by the caller (`ProductionLineSection`). **Bug: no loading indicator during confirm/reject.**                                    |
| **Product switch while previous switch pending**         | `_lineSwitchingProduct` flag exists but the dialog is modal, so the user can't easily trigger this. Low risk.                                                                                                                                                                        |
| **Produce pallet from loose while already in progress**  | `ProducePalletFromLooseDialog` returns and then `OpenItemsScreen` calls the provider. The dialog is dismissed, button is accessible again. **No protection against rapid double-calls.** The API could be called twice.                                                              |
| **Complete incomplete pallet while already in progress** | Same as above: no local loading guard on the button in `OpenItemsScreen`.                                                                                                                                                                                                            |
| **Stale open items after tabbing away and back**         | Open items are only fetched on `OpenItemsScreen.initState()`. If the user opens open items, goes back, creates a pallet, then opens open items again — `initState` fires again and fetches fresh data. This works correctly.                                                         |
| **Bootstrap refresh during handover review**             | Pull-to-refresh during handover review calls `loadBootstrap()` which replaces all state. The handover review mode is preserved because bootstrap returns the current `lineUiMode` from backend. Then the extra `getLineHandover()` call fetches full details. Should work correctly. |

---

## 6. API Integration Mapping

### 6.1 `GET /palletizing-line/bootstrap`

| Property              | Value                                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| **Called from**       | `PalletizingProvider.loadBootstrap()`                                                                     |
| **Called when**       | App start, pull-to-refresh                                                                                |
| **Request**           | No body. `X-Device-Key` header.                                                                           |
| **Response model**    | `BootstrapResponseModel` → `BootstrapResponse` (productTypes, productionLines, lines with per-line state) |
| **Screen dependency** | All screens depend on this                                                                                |
| **On success**        | All state maps populated. For lines in `PENDING_HANDOVER_REVIEW`, extra `getLineHandover()` call made.    |
| **On failure**        | Error screen with retry button                                                                            |
| **Retry**             | User taps "إعادة المحاولة"                                                                                |
| **Null handling**     | Defensively handles nullable fields with defaults                                                         |

### 6.2 `POST /palletizing-line/lines/{lineId}/authorize-pin`

| Property        | Value                                                                                 |
| --------------- | ------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.authorizeLineWithPin()`                                          |
| **Request**     | `{ "pin": "XXXX" }`                                                                   |
| **Response**    | `LineAuthorizationState` with operator info                                           |
| **On success**  | Auth state updated, `_refreshLineStateFromBackend()` called with `preserveAuth: true` |
| **On failure**  | Auth error stored in `LineAuthorizationState.authError`                               |

### 6.3 `GET /palletizing-line/lines/{lineId}/state`

| Property        | Value                                                                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider._refreshLineStateFromBackend()`                                                                                               |
| **Called when** | After auth, after pallet creation, after handover create/confirm/reject, after product-switch, after produce-from-loose, after complete-incomplete |
| **Response**    | `BootstrapLineState` (same structure as bootstrap per-line)                                                                                        |
| **On success**  | Per-line state updated: session table, pending handover, UI mode, blocked reason, authorization flags                                              |
| **Note**        | In `PENDING_HANDOVER_REVIEW` mode, triggers additional `getLineHandover()` for full details                                                        |

### 6.4 `POST /palletizing-line/lines/{lineId}/product-switch`

| Property        | Value                                                                             |
| --------------- | --------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.switchProduct()`                                             |
| **Request**     | `{ "previousProductTypeId": int, "loosePackageCount": int }`                      |
| **Response**    | Updated `List<SessionTableRow>` extracted from `data.sessionTable`                |
| **On success**  | Session table updated. Caller then sets selected product type locally.            |
| **On failure**  | Error message stored in `_lineErrors`. SnackBar shown by UI. Product NOT changed. |
| **Note**        | Even when looseCount == 0, the API is called (backend records the switch).        |

### 6.5 `POST /palletizing-line/lines/{lineId}/handover`

| Property        | Value                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.createLineHandover()`                                                                                      |
| **Request**     | `{ incompletePalletProductTypeId?, incompletePalletQuantity?, looseBalances?: [{ productTypeId, loosePackageCount }], notes? }` |
| **Response**    | `LineHandoverInfo`                                                                                                              |
| **On success**  | Pending handover stored. Full line state refreshed (auth released, UI mode transitions).                                        |
| **On failure**  | ApiException rethrown. SnackBar shown.                                                                                          |

### 6.6 `GET /palletizing-line/lines/{lineId}/handover/pending`

| Property           | Value                                                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **Called from**    | `PalletizingRepositoryImpl.getLineHandover()` (not directly from provider; called internally during refresh for review mode) |
| **Response**       | `LineHandoverInfo?` (null if no pending handover)                                                                            |
| **Error handling** | Catches all exceptions and returns null (defensive, no rethrow)                                                              |

### 6.7 `POST /palletizing-line/lines/{lineId}/handover/{id}/confirm`

| Property        | Value                                          |
| --------------- | ---------------------------------------------- |
| **Called from** | `PalletizingProvider.confirmLineHandover()`    |
| **Request**     | Empty body `{}`                                |
| **Response**    | `LineHandoverInfo`                             |
| **On success**  | Pending handover nulled. Line state refreshed. |
| **On failure**  | Error rethrown                                 |

### 6.8 `POST /palletizing-line/lines/{lineId}/handover/{id}/reject`

| Property        | Value                                          |
| --------------- | ---------------------------------------------- |
| **Called from** | `PalletizingProvider.rejectLineHandover()`     |
| **Request**     | `{ notes?: string }`                           |
| **Response**    | `LineHandoverInfo`                             |
| **On success**  | Pending handover nulled. Line state refreshed. |

### 6.9 `GET /palletizing-line/lines/{lineId}/open-items`

| Property        | Value                                                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.fetchOpenItems()`                                                                                     |
| **Response**    | `OpenItemsResponse` with `looseBalances: List<LooseBalanceItem>` and `receivedIncompletePallet?: ReceivedIncompletePallet` |
| **On success**  | Stored in `_openItems[lineNumber]`                                                                                         |
| **On failure**  | Error message stored in `_lineErrors`                                                                                      |

### 6.10 `POST /palletizing-line/lines/{lineId}/loose-balances/produce-pallet`

| Property        | Value                                                                                                                      |
| --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.producePalletFromLoose()`                                                                             |
| **Request**     | `{ productTypeId, looseQuantityToUse, freshQuantityToAdd }`                                                                |
| **Response**    | `ProducePalletFromLooseResponse` with `pallet`, `creationMode`, `looseQuantityUsed`, `freshQuantityAdded`, `finalQuantity` |
| **On success**  | Open items and line state refreshed in parallel (`Future.wait`). Pallet success dialog shown.                              |
| **On failure**  | ApiException rethrown                                                                                                      |

### 6.11 `POST /palletizing-line/lines/{lineId}/incomplete-pallet/complete`

| Property        | Value                                                                                                                                                 |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Called from** | `PalletizingProvider.completeIncompletePallet()`                                                                                                      |
| **Request**     | `{ additionalFreshQuantity: int }`                                                                                                                    |
| **Response**    | `CompleteIncompletePalletResponse` with `pallet`, `creationMode`, `incompleteQuantityUsed`, `freshQuantityAdded`, `finalQuantity`, `sourceHandoverId` |
| **On success**  | Open items and line state refreshed in parallel. Pallet success dialog shown.                                                                         |
| **On failure**  | ApiException rethrown                                                                                                                                 |

### 6.12 Frontend Assumptions About Backend

| Assumption                                                                                                             | Evidence                                                                         |
| ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| At most one incomplete pallet per line                                                                                 | `OpenItemsResponse.receivedIncompletePallet` is nullable singular, not a list    |
| Handover type is one of: NONE, INCOMPLETE_PALLET_ONLY, LOOSE_BALANCES_ONLY, BOTH                                       | Hardcoded in `LineHandoverCard._handoverTypeLabel()`                             |
| Loose balance origin is one of: `CARRIED_FROM_HANDOVER` or other (current session)                                     | `LooseBalanceItem.isFromHandover` checks for `origin == 'CARRIED_FROM_HANDOVER'` |
| `lineUiMode` values: `NEEDS_AUTHORIZATION`, `PENDING_HANDOVER_NEEDS_INCOMING`, `PENDING_HANDOVER_REVIEW`, `AUTHORIZED` | Hardcoded comparisons in `ProductionLineSection.build()` and `isLineBlocked()`   |
| Received incomplete pallet has mandatory `sourceHandoverId` and `status`                                               | Entity enforces `required` for these fields                                      |
| `loosePackageCount` in product-switch request will be 0 when operator says no leftover                                 | `ProductSwitchDialog` returns 0 and provider passes it to API                    |

---

## 7. UI-to-Backend-to-DB Flow Mapping

### 7.1 Open Incomplete Screen

| Step                  | What happens                                                              |
| --------------------- | ------------------------------------------------------------------------- |
| User taps "فالت" | `OpenItemsScreen.show()` pushes route                                     |
| Widget `initState`    | `provider.fetchOpenItems(lineNumber)`                                     |
| Provider method       | Resolves lineId from lineNumber, calls `_repository.getOpenItems(lineId)` |
| API                   | `GET /palletizing-line/lines/{lineId}/open-items`                         |
| Response parsed       | `OpenItemsResponseModel.fromJson()` → `OpenItemsResponse`                 |
| State updated         | `_openItems[lineNumber] = result`                                         |
| UI rendered           | Loose balance cards + incomplete pallet card (or empty state)             |

### 7.2 Create Pallet from Loose Cartons

| Step                                  | What happens                                                                           |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| User taps "إنشاء طبلية" on loose card | `_handleProducePallet()`                                                               |
| Dialog shown                          | `ProducePalletFromLooseDialog.show()`                                                  |
| User confirms                         | Returns `{ looseQuantityToUse, freshQuantityToAdd }`                                   |
| Provider method                       | `producePalletFromLoose(lineNumber, productTypeId, looseQty, freshQty)`                |
| API                                   | `POST /palletizing-line/lines/{lineId}/loose-balances/produce-pallet`                  |
| Backend expected                      | Creates pallet record, deducts loose balance, returns `ProducePalletFromLooseResponse` |
| State updated                         | `fetchOpenItems()` + `_refreshLineStateFromBackend()` called in parallel               |
| UI                                    | `PalletSuccessDialog` shown with new pallet details                                    |

### 7.3 Complete Incomplete Pallet

| Step                      | What happens                                                         |
| ------------------------- | -------------------------------------------------------------------- |
| User taps "إكمال الطبلية" | `_handleCompletePallet()`                                            |
| Dialog shown              | `CompleteIncompletePalletDialog.show()`                              |
| User confirms             | Returns `int` (0 for as-is, N for fresh qty)                         |
| Provider method           | `completeIncompletePallet(lineNumber, freshQty)`                     |
| API                       | `POST /palletizing-line/lines/{lineId}/incomplete-pallet/complete`   |
| Backend expected          | Creates pallet from incomplete + fresh, marks incomplete as resolved |
| State updated             | `fetchOpenItems()` + `_refreshLineStateFromBackend()` in parallel    |
| UI                        | `PalletSuccessDialog` shown                                          |

### 7.4 Product Switch with Leftovers

| Step                                          | What happens                                                              |
| --------------------------------------------- | ------------------------------------------------------------------------- |
| User selects different product                | `_handleProductSelection()` detects different product                     |
| Dialog shown                                  | `ProductSwitchDialog.show()`                                              |
| User selects "نعم يوجد فالت" and enters count | Returns `int` (loose count)                                               |
| Provider method                               | `switchProduct(lineNumber, previousProductTypeId, looseCount)`            |
| API                                           | `POST /palletizing-line/lines/{lineId}/product-switch`                    |
| Backend expected                              | Records loose balance for previous product, returns updated session table |
| State updated                                 | `_sessionTables[lineNumber] = updatedTable`                               |
| Provider then                                 | `selectProductType(lineNumber, newProduct)` — local state                 |
| Failure                                       | SnackBar error. Product NOT changed.                                      |

### 7.5 Create Handover

| Step                         | What happens                                                                           |
| ---------------------------- | -------------------------------------------------------------------------------------- |
| User taps "تسليم مناوبة"     | `_handleCreateHandover()`                                                              |
| Dialog shown                 | `HandoverCreationDialog` (2-step)                                                      |
| User fills form and confirms | Returns `HandoverCreationResult`                                                       |
| Provider method              | `createLineHandover(lineNumber, ...)`                                                  |
| API                          | `POST /palletizing-line/lines/{lineId}/handover`                                       |
| Backend expected             | Creates handover record, releases outgoing operator's auth                             |
| State updated                | `_pendingHandovers[lineNumber] = handover`, then full line state refresh               |
| UI                           | SnackBar success. Line transitions to `PENDING_HANDOVER_NEEDS_INCOMING` (PIN overlay). |

### 7.6 Confirm Handover

| Step                                                  | What happens                                                                                                 |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Incoming operator taps "معلومات دقيقة وتأكيد التسليم" | `_handleConfirmHandover()`                                                                                   |
| Provider method                                       | `confirmLineHandover(lineNumber, handoverId)`                                                                |
| API                                                   | `POST /palletizing-line/lines/{lineId}/handover/{id}/confirm`                                                |
| Backend expected                                      | Moves handover to CONFIRMED. Creates incoming line's open items (loose balances + incomplete pallet if any). |
| State updated                                         | `_pendingHandovers[lineNumber] = null`, line state refreshed                                                 |
| UI                                                    | SnackBar success. Line transitions to normal production mode.                                                |

### 7.7 Reject Handover

| Step                                                    | What happens                                                                       |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Incoming operator taps "تسليم غير دقيق وتأكيد الاستلام" | `_handleRejectHandover()`                                                          |
| Rejection notes dialog                                  | User optionally enters reason                                                      |
| Provider method                                         | `rejectLineHandover(lineNumber, handoverId, notes)`                                |
| API                                                     | `POST /palletizing-line/lines/{lineId}/handover/{id}/reject`                       |
| Backend expected                                        | Moves handover to REJECTED/DISPUTED for admin review. May still create open items. |
| State updated                                           | `_pendingHandovers[lineNumber] = null`, line state refreshed                       |
| UI                                                      | SnackBar "تم رفض التسليم وسيتم مراجعته من قبل الإدارة".                            |

### 7.8 Refresh Main Screen

| Step                  | What happens                                   |
| --------------------- | ---------------------------------------------- |
| User pulls to refresh | `_refreshData()` → `loadBootstrap()`           |
| Provider              | Clears error, sets loading, fetches bootstrap  |
| All state             | Replaced from backend response                 |
| Extra calls           | Lines in review mode get full handover details |
| UI                    | Shimmer during loading, then full render       |

---

## 8. Conditional UI and Edge Cases

### 8.1 No Open Items

- `OpenItemsScreen` shows empty state: icon + "لا توجد عناصر فالتة" + "جميع العناصر تمت معالجتها".
- Pull-to-refresh still available.

### 8.2 Leftovers Only (No Incomplete Pallet)

- `OpenItemsScreen` shows only the "العبوات الفالتة" section with loose balance cards.
- The incomplete pallet section is completely absent (not even a header).

### 8.3 Incomplete Only (No Leftovers)

- `OpenItemsScreen` shows only the "طبلية ناقصة مستلمة" section.
- No loose balance section shown.

### 8.4 Both Leftovers and Incomplete

- Both sections shown in order: loose balances first, then incomplete pallet.
- No visual grouping or priority indication.

### 8.5 Duplicate Taps on Produce-from-Loose / Complete-Incomplete

- **No loading guard**: The "إنشاء طبلية" and "إكمال الطبلية" buttons in `OpenItemsScreen` have no `isLoading` state that disables them during API calls.
- **Risk**: User can tap multiple times quickly, potentially sending duplicate API requests.
- The provider methods do not have their own loading guards for these operations.

### 8.6 Loading While Navigating Away

- If `fetchOpenItems()` is in-flight and user pops the screen: the provider still completes the request and stores the result. No crash (handled via `context.mounted` checks in dialog callbacks).
- If `producePalletFromLoose()` succeeds after user navigates away: the `PalletSuccessDialog` will not show (guarded by `context.mounted`), but state is correctly updated.

### 8.7 Dialog Reopened After Failure

- After error SnackBar, user can tap the action button again to retry. There is no persistent error state blocking retries.

### 8.8 Stale Session Table After Refresh

- Session table is always replaced from backend during `_refreshLineStateFromBackend()` or `loadBootstrap()`. The only staleness window is between API calls.
- **Edge case**: If product-switch completes but `_refreshLineStateFromBackend` fails silently (catch block just prints), the session table is updated from the product-switch response but the rest of the line state may be stale.

### 8.9 Wrong Machine Tab Showing Wrong Data

- **Not a risk**: All per-line state is keyed by `lineNumber`. Tab 1 reads from `lineNumber=1` maps, Tab 2 from `lineNumber=2`. The `ProductionLineSection` widget receives its `line` enum as a constructor parameter.

### 8.10 Changing Product Type Twice Rapidly

- The `ProductSwitchDialog` is modal, so the user must dismiss it before opening a new one. However, between the dialog returning and the API completing, the user could theoretically open the product picker again.
- **Mitigation**: `_lineSwitchingProduct` flag exists but is **not checked** in `_buildProductField()` to disable the dropdown. The dropdown is always tappable.

### 8.11 Same Product Type Selected Again

- `_handleProductSelection` checks `currentProduct.id == newProduct.id`. If same, it shows a simple confirmation dialog (not the switch dialog). No API call is made. This is correct.

### 8.12 Backend Returns Data But UI Hides It

- The "فالت" button is hidden when `isLineBlocked(lineNumber)` returns true. This means during `PENDING_HANDOVER_REVIEW` or `PENDING_HANDOVER_NEEDS_INCOMING` modes, open items are inaccessible even if the backend has data.
- The handover creation button is hidden when `canInitiateHandover` is false.

### 8.13 Already-Resolved Handover Conflict

- If user tries to confirm/reject an already-resolved handover, backend returns `LINE_HANDOVER_ALREADY_RESOLVED` error code.
- Frontend shows Arabic message "تم معالجة هذا التسليم مسبقاً" via SnackBar.
- After error, line state refresh will clear the stale handover.

### 8.14 App Reopened After Pending Action

- Since all state is server-driven and `loadBootstrap()` is called on every app start, the UI correctly reflects the current server state regardless of what was happening before app close.

### 8.15 `isResolving` Always False Bug

- `LineHandoverCard` accepts `isResolving` prop. In `ProductionLineSection`, it is used in the handover review layout but is **never set to true**. The confirm/reject buttons don't show a loading state during the API call. If the API is slow, the user might tap multiple times.

---

## 9. Component / Widget Analysis

### 9.1 OpenItemsScreen

- **Responsibility**: Full-screen view combining loose balances and incomplete pallet.
- **Reusable?**: No, tightly coupled to `PalletizingProvider` and specific entity types.
- **Business logic in UI**: Handler methods (`_handleProducePallet`, `_handleCompletePallet`) orchestrate the dialog-then-API flow directly in the widget code. The provider method is the actual state mutation point, but the try/catch/SnackBar logic lives in the widget.
- **Line-scoped**: Yes, receives `ProductionLine` (constants enum) as constructor parameter.

### 9.2 ProductSwitchDialog

- **Responsibility**: Collect loose carton count during product switch.
- **Reusable?**: No, specific to product switch flow.
- **Business logic in UI**: Minimal — just validation and data collection.
- **Important design note**: This dialog does NOT connect to the backend. It only collects user input. The caller (`ProductionLineSection._handleProductSelection`) handles the API call. This is a correct separation.

### 9.3 HandoverCreationDialog

- **Responsibility**: Multi-step form for handover creation.
- **Reusable?**: No, specific to handover flow.
- **Business logic in UI**: Contains case selection logic (`_HandoverCase` enum), form validation, duplicate product type detection. These are presentation-level concerns and appropriate for the dialog.
- **Important design note**: Like `ProductSwitchDialog`, this dialog only collects data. The API call is in the caller.

### 9.4 LineHandoverCard

- **Responsibility**: Read-only display of handover info with optional action buttons.
- **Reusable?**: Partially — used in both main screen (read-only) and review layout (with actions).
- **Business logic in UI**: `_handoverTypeLabel()` maps backend enum to Arabic text. This is presentation logic, acceptable.

### 9.5 SessionTableWidget

- **Responsibility**: Display session summary table with loose balance column.
- **Reusable?**: Yes, stateless widget that receives data.
- **Business logic in UI**: `row.hasLooseBalance` check for orange highlighting. This is pure presentation.

### 9.6 ProductionLineSection

- **Responsibility**: Main per-line orchestrator. Contains significant business flow logic.
- **Business logic in UI**: `_handleProductSelection()` contains the full product-switch flow decision tree (first selection vs. re-selection vs. switch). `_handleCreateHandover()` and `_handleConfirmHandover()` / `_handleRejectHandover()` orchestrate dialog → API → feedback.
- **Risk**: This widget is large (~1180 lines) and mixes presentation with orchestration. A future refactor could extract flow handlers into the provider or a dedicated controller.

### 9.7 PalletizingProvider

- **Responsibility**: Central state management for all palletizing flows.
- **Size**: ~680 lines with 20+ state maps.
- **Risk**: Single large provider managing all state. Methods properly scope by lineNumber. No threading issues (Flutter is single-threaded).
- **Correctly isolated**: Line 1 and Line 2 state never leak into each other.

---

## 10. Bugs / Gaps / UX Ambiguities

### 10.1 Confirmed Bugs

| #   | Bug                                                                                | Severity | Location                                                                                                                                           |
| --- | ---------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **`isResolving` never set to true during handover confirm/reject**                 | Medium   | `ProductionLineSection._buildHandoverReviewLayout()` — `LineHandoverCard(isResolving: false)` is hardcoded; no loading state shown during API call |
| 2   | **No double-tap protection on produce-from-loose and complete-incomplete buttons** | Medium   | `OpenItemsScreen._handleProducePallet` and `_handleCompletePallet` — buttons remain active during API call                                         |
| 3   | **`_lineSwitchingProduct` flag stored but never consumed by UI**                   | Low      | `ProductionLineSection._buildProductField()` doesn't check this flag to disable the dropdown during switch                                         |

### 10.2 State Synchronization Issues

| #   | Issue                                                       | Details                                                                                                                                                                                                                                                                          |
| --- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Selected product type hybrid state**                      | Product type is seeded from backend (bootstrap `selectedProductType`) but can be locally overridden without API call. If the user selects product A, then pulls to refresh, the backend may return a different `selectedProductType` (or null), overwriting the local selection. |
| 2   | **Open items not auto-refreshed**                           | Open items screen fetches on `initState` but the underlying data may change if another flow (e.g. handover confirmation) modifies it while the screen is open. The screen would show stale data until pull-to-refresh.                                                           |
| 3   | **Session table updated from product-switch response only** | After a successful product switch, the session table is set from the switch response. But the subsequent `_refreshLineStateFromBackend()` call will overwrite it with the backend's view. If there's a slight delay, the session table might flicker.                            |

### 10.3 UI / Backend Mismatches

| #   | Issue                                                            | Details                                                                                                                                                                                                                                                                                                                                                                                                      |
| --- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | **Product switch dialog says "عبوات فالتة (فالتة)"**        | This parenthetical "(فالتة)" conflates leftovers with incomplete pallets. Leftovers from a product switch are NOT incomplete pallets — they are loose cartons. The UI wording is misleading.                                                                                                                                                                                                            |
| 2   | **Handover step 0 says "طبليات ناقصة" (plural)**                 | But only ONE incomplete pallet can be specified per handover. The plural wording suggests multiple are possible.                                                                                                                                                                                                                                                                                             |
| 3   | **Reject handover button says "تسليم غير دقيق وتأكيد الاستلام"** | This implies the incoming operator still accepts the items despite the data being inaccurate. The frontend sends a reject API call but the UI text implies acceptance. **Ambiguous to end users.**                                                                                                                                                                                                           |
| 4   | **Two `LooseBalanceItem` classes**                               | `domain/entities/loose_balance_item.dart` has `origin` and `sourceHandoverId`; `domain/entities/line_handover_info.dart` defines its own `LooseBalanceItem` without those fields. The model layer also has two `LooseBalanceItemModel` classes — one in `open_items_response_model.dart` and one in `line_handover_info_model.dart`. **This is a code-level duplication that could cause import confusion.** |

### 10.4 Hidden Assumptions

| #   | Assumption                                                | Risk                                                                                                                               |
| --- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Max one incomplete pallet per line**                    | If backend ever supports multiple, the frontend would only show one                                                                |
| 2   | **lineUiMode is always one of 4 known values**            | Any unknown mode falls through to normal layout (no explicit "unknown mode" handling)                                              |
| 3   | **Bootstrap always returns lines for lineNumber 1 and 2** | Constants enum is hardcoded to 2 lines. If backend adds line 3, no tab would appear                                                |
| 4   | **LooseBalanceItem.origin values**                        | Only `CARRIED_FROM_HANDOVER` is explicitly checked. Any other value defaults to "الجلسة الحالية" badge display                     |
| 5   | **Product type list is global and shared**                | Product types are not filtered per line. If backend restricts certain products to certain lines, the frontend would still show all |

### 10.5 UX Ambiguities

| #   | Ambiguity                                            | Details                                                                                                                                                                                                                                                           |
| --- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **What does "فالت" mean to the user?**          | It labels a button that leads to BOTH loose balances and incomplete pallets. A user might interpret it as "incomplete pallets only" and miss the loose balance information, or vice versa.                                                                        |
| 2   | **No indication of open items count on main screen** | The "فالت" button has no badge or count indicator. The user must tap it to see if there are any open items.                                                                                                                                                  |
| 3   | **Session table shows "فالت" column but no action**  | The فالت column in the session table shows loose counts per product type but offers no way to act on them (e.g. tap to produce pallet). The user must go to the open items screen.                                                                                |
| 4   | **No clear lifecycle of leftovers**                  | The UI doesn't show WHERE a leftover came from (which product switch or which handover) in the session table — only in the open items screen via origin badges.                                                                                                   |
| 5   | **Rejection flow unclear**                           | After rejecting a handover, the SnackBar says admin will review. But the UI immediately clears the handover and refreshes the line. The user might wonder: "Do I still get the items?" The answer depends on backend logic, but the frontend provides no clarity. |

### 10.6 Missing Features / Gaps

| #   | Gap                                                             | Details                                                                                                                                                                                                                                                 |
| --- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **No local persistence for palletizing state**                  | All state is in-memory. If the app crashes during a multi-step flow, all context is lost. The server state is authoritative but any unsaved user selections (like product type) are gone.                                                               |
| 2   | **No offline support**                                          | All operations require network connectivity. No queuing or caching.                                                                                                                                                                                     |
| 3   | **No handover history screen**                                  | Users can't see past handovers, only the current pending one.                                                                                                                                                                                           |
| 4   | **No explicit "end session" / "logout" from line**              | `revokeLineAuthorization()` exists in the provider but is **never called from the UI**. There is no "خروج" or "تسجيل خروج" button on the line section. The only way to de-authorize is via handover creation (which releases auth on the backend side). |
| 5   | **No confirmation before handover creation for clean handover** | If the user selects neither toggle (clean handover) and taps "تأكيد التسليم", a handover is created immediately with type NONE. No confirmation "Are you sure there are no open items?" is shown.                                                       |
| 6   | **No tests**                                                    | No test files were found related to incomplete pallets, leftovers, open items, or handover flows.                                                                                                                                                       |

---

## 11. Redesign Readiness Notes

These are questions that **must be answered** before redesigning the incomplete pallets and leftover cartons UX:

### 11.1 Conceptual Questions

1. **Should incomplete pallets and leftover cartons have separate screens or remain unified under "Open Items"?** Currently they share one screen. Separating them would make each concept clearer but adds navigation complexity.

2. **Should the "فالت" button be renamed to better reflect both concepts?** Options: "العناصر المعلقة" (pending items), "الفالت والناقص" (leftovers and incomplete), or keep current name.

3. **Should the open items count be shown as a badge on the button?** This would inform the user without requiring navigation.

4. **Should product-switch leftovers use a different UX flow from shift-handover leftovers?** Currently, product-switch leftovers are quietly recorded via API and appear in the open items screen. Handover leftovers are explicitly declared by the outgoing operator. Should these flows converge?

5. **Should the session table's فالت column be actionable?** E.g., tapping a row with loose balance could navigate to the produce-pallet-from-loose flow.

### 11.2 State Management Questions

6. **Should selected product type be server-persisted?** Currently it's a hybrid (seeded from backend but locally overrideable). This creates sync risks during refresh.

7. **What state must be server-driven vs local-only?** Currently all critical state is server-driven (correct), but there are no server-driven constraints on UI interactions (e.g., the product dropdown is never disabled by the server).

8. **Should open items state be cached locally?** Currently fetched on-demand only when the screen is opened. Caching could enable badge counts on the main screen.

### 11.3 UX Flow Questions

9. **Should dialogs be multi-step or simplified?** The handover creation dialog is already 2-step. Could it be simplified to a single form?

10. **What should happen after confirming a handover with both incomplete pallet and loose balances?** Currently the open items screen shows both. Should there be a guided "process your inherited items" flow?

11. **Should the rejection flow be clearer about what happens to the items?** Users need to know: does rejection mean they still get the items, just with a dispute flag?

12. **How should success/error/empty states be made more explicit?** Currently errors are SnackBars (easily missed) and empty states are static illustrations. Consider more prominent feedback.

### 11.4 Naming Questions

13. **What naming should be unified?** Should the app use "طبلية" consistently or adopt another term? Should "فالت" be formalized?

14. **Should "ماكنة" and "خط الإنتاج" be standardized?** Currently mixed in the UI.

15. **Should the plural "طبليات ناقصة" be corrected to singular "طبلية ناقصة" in the handover dialog?** Given only one is supported.

### 11.5 Technical Questions

16. **Should the two `LooseBalanceItem` classes be unified?** Currently duplicated across `loose_balance_item.dart` and `line_handover_info.dart`.

17. **Should `ProductionLineSection` be broken into smaller widgets?** At ~1180 lines, it's the largest widget and mixes orchestration with presentation.

18. **Should the provider be split?** A single `PalletizingProvider` manages all state. Consider splitting into `LineStateProvider`, `OpenItemsProvider`, `HandoverProvider`.

19. **Should loading guards be added for all API-triggering actions?** Currently only pallet creation has proper loading guards.

20. **Should `revokeLineAuthorization()` be exposed in the UI?** It exists in the provider but has no UI trigger.

---

## 12. Final Recommendation Summary

### 12.1 Current Frontend Reality

The frontend **correctly separates** incomplete pallets and leftover cartons at the data layer — they are distinct entities (`ReceivedIncompletePallet` vs `LooseBalanceItem`) with distinct API endpoints and distinct UI rendering. They share a unified entry screen ("فالت") and a unified handover creation dialog, but within these screens, the two concepts are visually distinguished (purple cards for incomplete, line-colored cards for leftover).

The state management is **centralized and server-driven**, which is architecturally sound. All critical state flows through the backend, ensuring consistency. The per-line isolation via `Map<int, T>` keyed by `lineNumber` is correct and prevents line 1/line 2 data leakage.

### 12.2 Top UX/State-Management Risks

1. **Missing loading guards** on produce-from-loose, complete-incomplete, and handover confirm/reject buttons create double-tap risks.
2. **"فالت" button naming** is ambiguous and doesn't communicate the presence of both concepts or their count.
3. **Hybrid product type state** (backend-seeded but locally overrideable) creates sync risks on refresh.
4. **Handover confirm/reject has no loading state** (`isResolving` always false).
5. **Two duplicate `LooseBalanceItem` classes** create maintenance risk.

### 12.3 Biggest Ambiguities to Resolve Before Redesign

1. **Are incomplete pallets and leftover cartons truly separate flows or should they converge?** The backend clearly separates them; the frontend should match.
2. **What is the intended user journey after handover confirmation?** Should the incoming operator be guided to process inherited items?
3. **What does handover rejection mean for item ownership?** The frontend's messaging is unclear.
4. **Should open items be proactively surfaced (badge count) or only on-demand (current)?**
5. **Should the handover creation flow auto-detect loose balances from the session table** rather than relying on manual operator input?

---

## Appendix: Files Analyzed

| Category        | Files                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Entities**    | `open_items_response.dart`, `loose_balance_item.dart`, `complete_incomplete_pallet_response.dart`, `produce_pallet_from_loose_response.dart`, `received_incomplete_pallet.dart`, `line_handover_info.dart`, `line_authorization_state.dart`, `bootstrap_response.dart`, `line_summary.dart`, `session_table_row.dart`, `pallet_create_response.dart`, `product_type.dart`, `production_line.dart`, `operator.dart` |
| **Models**      | `bootstrap_response_model.dart`, `open_items_response_model.dart`, `line_handover_info_model.dart`, `produce_pallet_from_loose_response_model.dart`, `complete_incomplete_pallet_response_model.dart`, `session_table_row_model.dart`                                                                                                                                                                              |
| **Provider**    | `palletizing_provider.dart`                                                                                                                                                                                                                                                                                                                                                                                        |
| **Repository**  | `palletizing_repository.dart` (interface), `palletizing_repository_impl.dart` (implementation)                                                                                                                                                                                                                                                                                                                     |
| **API**         | `api_client.dart`                                                                                                                                                                                                                                                                                                                                                                                                  |
| **Screens**     | `palletizing_screen.dart`                                                                                                                                                                                                                                                                                                                                                                                          |
| **Widgets**     | `production_line_section.dart`, `open_items_screen.dart`, `complete_incomplete_pallet_dialog.dart`, `produce_pallet_from_loose_dialog.dart`, `product_switch_dialog.dart`, `handover_creation_dialog.dart`, `line_handover_card.dart`, `session_table_widget.dart`, `summary_card.dart`, `line_auth_overlay.dart`                                                                                                  |
| **Core**        | `constants.dart`, `di.dart`, `api_exception.dart`                                                                                                                                                                                                                                                                                                                                                                  |
| **Entry point** | `main.dart`                                                                                                                                                                                                                                                                                                                                                                                                        |
