# UI Terminology & Top Button Layout Report

## Overview

Applied user-facing terminology changes and button layout restructuring across the Taleeb Thermoforming Flutter app. No workflow, backend contracts, state management, or navigation logic was altered.

---

## 1. Terminology Changes

### App Title

| Old              | New            |
| ---------------- | -------------- |
| `تكوين المشاتيح` | `تكوين طبليات` |

**Files updated:**

- `lib/presentation/screens/palletizing_screen.dart` — AppBar title (mobile/tablet + desktop variants)
- `lib/presentation/screens/login_screen.dart` — Login screen branding title

### Tab Labels

| Old    | New       |
| ------ | --------- |
| `خط 1` | `ماكنة 1` |
| `خط 2` | `ماكنة 2` |

**File updated:**

- `lib/presentation/screens/palletizing_screen.dart` — TabBar tab labels

### Session Summary Title

| Old           | New             |
| ------------- | --------------- |
| `ملخص الجلسة` | `ملخص المناوبة` |

**File updated:**

- `lib/presentation/widgets/session_table_widget.dart` — Section header

### Open Items Button & Screen Title

| Old                             | New                                 |
| ------------------------------- | ----------------------------------- |
| `العناصر المفتوحة`              | `غير مكتمل`                         |
| `فشل في تحميل العناصر المفتوحة` | `فشل في تحميل العناصر غير المكتملة` |
| `لا توجد عناصر مفتوحة`          | `لا توجد عناصر غير مكتملة`          |

**Files updated:**

- `lib/presentation/widgets/production_line_section.dart` — Button label
- `lib/presentation/widgets/open_items_screen.dart` — AppBar title, empty state text
- `lib/presentation/providers/palletizing_provider.dart` — Error message

### مشتاح → طبلية (Pallet Terminology)

All user-facing occurrences of `مشتاح` (singular) and `مشاتيح` (plural) were replaced:

| Old                               | New                                | Context                                                         |
| --------------------------------- | ---------------------------------- | --------------------------------------------------------------- |
| `المشاتيح`                        | `الطبليات`                         | Summary card stat label, session table header                   |
| `تم إنشاء المشتاح بنجاح`          | `تم إنشاء الطبلية بنجاح`           | Pallet success dialog                                           |
| `إنشاء مشتاح جديد`                | `إنشاء طبلية جديدة`                | Create pallet dialog title, bottom create button                |
| `فشل في إنشاء المشتاح`            | `فشل في إنشاء الطبلية`             | Error snackbar, provider error state                            |
| `مشتاح ناقص`                      | `طبلية ناقصة`                      | Handover card, creation dialog, open items screen, auth overlay |
| `مشاتيح ناقصة فقط`                | `طبليات ناقصة فقط`                 | Handover type label (3 files)                                   |
| `مشاتيح ناقصة وفالت`              | `طبليات ناقصة وفالت`               | Handover type label (3 files)                                   |
| `هل يوجد مشاتيح ناقصة؟`           | `هل يوجد طبليات ناقصة؟`            | Handover creation toggle                                        |
| `إكمال المشتاح الناقص`            | `إكمال الطبلية الناقصة`            | Complete incomplete pallet dialog title                         |
| `إكمال المشتاح`                   | `إكمال الطبلية`                    | Complete button label (2 locations)                             |
| `إنشاء مشتاح من الفالت`           | `إنشاء طبلية من الفالت`            | Produce from loose dialog title                                 |
| `حجم المشتاح`                     | `حجم الطبلية`                      | Info chip in produce from loose dialog                          |
| `إنشاء المشتاح`                   | `إنشاء الطبلية`                    | Confirm button in produce from loose dialog                     |
| `إنشاء مشتاح`                     | `إنشاء طبلية`                      | Loose balance card action button                                |
| `مشتاح ناقص مستلم`                | `طبلية ناقصة مستلمة`               | Open items section header                                       |
| `مشتاح ناقص — X عبوة`             | `طبلية ناقصة — X عبوة`             | Incomplete pallet card                                          |
| `المشتاح غير موجود`               | `الطبلية غير موجودة`               | API error display message                                       |
| `المشتاح لا ينتمي لهذا الخط`      | `الطبلية لا تنتمي لهذا الخط`       | API error display message                                       |
| `لا يوجد مشتاح ناقص معلق`         | `لا يوجد طبلية ناقصة معلقة`        | API error display message                                       |
| `تم معالجة المشتاح الناقص مسبقاً` | `تم معالجة الطبلية الناقصة مسبقاً` | API error display message                                       |

**Files updated (مشتاح → طبلية):**

- `lib/presentation/widgets/summary_card.dart`
- `lib/presentation/widgets/pallet_success_dialog.dart`
- `lib/presentation/widgets/session_table_widget.dart`
- `lib/presentation/widgets/create_pallet_dialog.dart`
- `lib/presentation/widgets/line_handover_card.dart`
- `lib/presentation/widgets/handover_creation_dialog.dart`
- `lib/presentation/widgets/complete_incomplete_pallet_dialog.dart`
- `lib/presentation/widgets/produce_pallet_from_loose_dialog.dart`
- `lib/presentation/widgets/open_items_screen.dart`
- `lib/presentation/widgets/line_auth_overlay.dart`
- `lib/presentation/widgets/production_line_section.dart`
- `lib/presentation/providers/palletizing_provider.dart`
- `lib/core/exceptions/api_exception.dart`

---

## 2. Button Layout Changes

### What Changed

The two action buttons (`غير مكتمل` and `تسليم مناوبة`) were moved from their previous mid-screen positions (between the form card and the session table) to the **top of each line screen**, before the form card.

### Previous Layout

```
┌─────────────────────────────────│
│  Form Card                      │
│  ────────────                   │
│  [Open Items Button] (full-width)│  ← Was here
│  [Handover Button]  (full-width) │  ← Was here
│  Pending Handover Card          │
│  Session Table                  │
└─────────────────────────────────┘
```

### New Layout

```
┌─────────────────────────────────┐
│  [غير مكتمل] [تسليم مناوبة]     │  ← Now here (same row, equal width)
│  Form Card                      │
│  ────────────                   │
│  Pending Handover Card          │
│  Session Table                  │
└─────────────────────────────────┘
```

### Implementation Details

- Created new `_buildTopActionButtons()` method in `ProductionLineSection`
- Removed old `_buildHandoverButton()` and `_buildOpenItemsButton()` standalone methods (eliminated dead code)
- Both buttons placed in a `Row` with `Expanded` wrappers for **equal sizing**
- In RTL (Arabic), first child in `Row` = right side visually:
  - **`غير مكتمل`** (OutlinedButton) → **RIGHT** side
  - **`تسليم مناوبة`** (ElevatedButton, orange) → **LEFT** side
- `SizedBox(width: 10-14)` gap between buttons (responsive)
- Buttons are conditionally shown based on the same authorization logic as before:
  - `غير مكتمل`: visible when `isLineAuthorized && !isLineBlocked`
  - `تسليم مناوبة`: visible when `canInitiateHandover`
- When only one button is visible, it still fills its `Expanded` space
- When neither button should show, `SizedBox.shrink()` is returned
- Button padding reduced to `12-16` (from `14-18`) and font size to `14-16` (from `16-18`) to fit well in the row layout on phones

---

## 3. Localization / String Structure

- **No localization framework** is used in the project (no `.arb` files, no `intl`, no `easy_localization`)
- All Arabic strings are **hardcoded** directly in widget files
- All replacements were done as direct string edits in the source files
- No new localization infrastructure was created (per instruction to reuse existing structure)

---

## 4. Files Changed (Complete List)

| File                                                              | Changes                                                                                        |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `lib/presentation/screens/palletizing_screen.dart`                | App title (×2), tab labels (×2)                                                                |
| `lib/presentation/screens/login_screen.dart`                      | App title (×1)                                                                                 |
| `lib/presentation/widgets/production_line_section.dart`           | Button layout restructure, create button text, error snackbar text, removed old button methods |
| `lib/presentation/widgets/session_table_widget.dart`              | Session summary title, table header                                                            |
| `lib/presentation/widgets/open_items_screen.dart`                 | Screen title, empty state text, section header, button labels, card text                       |
| `lib/presentation/widgets/pallet_success_dialog.dart`             | Success message                                                                                |
| `lib/presentation/widgets/create_pallet_dialog.dart`              | Dialog title                                                                                   |
| `lib/presentation/widgets/summary_card.dart`                      | Stat card label                                                                                |
| `lib/presentation/widgets/line_handover_card.dart`                | Section title, handover type labels                                                            |
| `lib/presentation/widgets/handover_creation_dialog.dart`          | Toggle label, section header, case chip labels                                                 |
| `lib/presentation/widgets/complete_incomplete_pallet_dialog.dart` | Dialog title, confirm button                                                                   |
| `lib/presentation/widgets/produce_pallet_from_loose_dialog.dart`  | Dialog title, info chip, confirm button                                                        |
| `lib/presentation/widgets/line_auth_overlay.dart`                 | Summary row label, handover type labels                                                        |
| `lib/presentation/providers/palletizing_provider.dart`            | Error messages (×2)                                                                            |
| `lib/core/exceptions/api_exception.dart`                          | Error display messages (×4)                                                                    |

**Total: 15 files, ~35 string replacements + 1 layout restructure**

---

## 5. Verification

| Check                                          | Status                        |
| ---------------------------------------------- | ----------------------------- |
| `flutter analyze` passes with 0 issues         | ✅                            |
| Grep for `المشاتيح` in lib/                    | ✅ 0 matches                  |
| Grep for `مشتاح` in lib/                       | ✅ 0 matches                  |
| Grep for `مشاتيح` in lib/                      | ✅ 0 matches                  |
| Grep for `ملخص الجلسة` in lib/                 | ✅ 0 matches                  |
| Grep for `العناصر المفتوحة` in lib/            | ✅ 0 matches                  |
| Grep for `خط 1` / `خط 2` as tab labels in lib/ | ✅ 0 matches                  |
| App title shows `تكوين طبليات`                 | ✅ Verified in code           |
| Tabs show `ماكنة 1` and `ماكنة 2`              | ✅ Verified in code           |
| Buttons in same-size Row at top                | ✅ Both wrapped in `Expanded` |
| `غير مكتمل` on RIGHT (RTL first child)         | ✅ First in Row               |
| `تسليم مناوبة` on LEFT (RTL second child)      | ✅ Second in Row              |
| Phone-friendly font sizes (14-16)              | ✅ Responsive sizing          |
| No workflow/navigation changes                 | ✅ Only labels and layout     |

---

## 6. What Was NOT Changed (By Design)

- Internal model class names (e.g., `PalletCreateResponse`, `palletizing_repository`)
- API field names and endpoint paths
- Backend contracts
- State management architecture
- Navigation/routing logic
- `lib/core/constants.dart` production line names (`خط الإنتاج 1/2` — these are backend-facing display names, not tab labels)
- Workflow or business logic
- Printing system
- Authentication flow
