# Frontend Quantity & Tab Sync Fix Report

## Issue 1: Create Pallet Dialog Default Quantity Semantics

### Root Cause

In `lib/presentation/widgets/create_pallet_dialog.dart`, the quantity stepper field was initialized with a **hardcoded value of 20** (`int _quantity = 20`), ignoring the selected product type's `packageQuantity`. Additionally, when the user changed the product selection via the picker, the quantity was **not updated** to the newly selected product's `packageQuantity`.

This caused the "إنشاء مشتاح جديد" dialog to always show 20 in the stepper, regardless of the selected product type. For product **TT-20 BLACK 500** (packageQuantity = 500), the dialog showed 20 instead of 500.

A secondary effect: in `lib/presentation/widgets/pallet_success_dialog.dart`, the "الكمية" info row displayed `pallet.quantity` (the value submitted from the stepper, typically the wrong default of 20) instead of `productType.packageQuantity`. Since this row is in the product info section alongside product name and color, it should reflect the product attribute.

### Classification

**Frontend-only.** No backend issue.

### Files Changed

| File | Change |
|---|---|
| `lib/presentation/widgets/create_pallet_dialog.dart` | Initialize `_quantity` from `selectedProductType.packageQuantity` instead of hardcoded 20; update quantity when product selection changes |
| `lib/presentation/widgets/pallet_success_dialog.dart` | Show `productType.packageQuantity` instead of `pallet.quantity` in the product info "الكمية" row |

### Code Changes

**`create_pallet_dialog.dart`:**
- `int _quantity = 20;` → `late int _quantity;`
- In `initState()`: `_quantity = _selectedProductType?.packageQuantity ?? 20;`
- On product picker selection: added `_quantity = selected.packageQuantity;` and `_quantityController.text = '$_quantity';`

**Key behavior preserved:**
- The quantity field remains **user-editable** (stepper +/- buttons and direct text input)
- The user can create partial/incomplete pallets by adjusting the quantity
- The **user-edited value** is what gets submitted to the backend (not forced to `packageQuantity`)
- `_handleConfirm` still pops with `{'quantity': _quantity}` — the user-controlled value

**`pallet_success_dialog.dart`:**
- Changed `widget.pallet.quantity` → `widget.pallet.productType.packageQuantity` in the "الكمية" info row

---

## Issue 2: Tab Header Color Delay During Swipe

### Root Cause

In `lib/presentation/screens/palletizing_screen.dart`, the tab header color was synchronized using `TabController.addListener` with an `indexIsChanging` guard:

```dart
void _handleTabChange() {
    if (_tabController!.indexIsChanging) {
      setState(() {});
    }
}
```

**Problem:** `indexIsChanging` is only `true` during a **programmatic/tap** animation. During a **swipe**, the `TabController.index` doesn't change until the swipe gesture settles, and `indexIsChanging` remains `false` throughout. So `setState` was never called during a swipe — the AppBar color only updated after the swipe completed.

The AppBar color was also derived from `_tabController?.index`, which is the settled index and doesn't reflect real-time swipe progress.

### Classification

**State synchronization / controller listener issue.** Frontend-only.

### Files Changed

| File | Change |
|---|---|
| `lib/presentation/screens/palletizing_screen.dart` | Switch from `TabController.addListener` to `TabController.animation.addListener` for real-time swipe tracking; use `_activeTabIndex` derived from animation value |

### Code Changes

1. Added `int _activeTabIndex = 0;` state variable
2. Replaced `_tabController!.addListener(_handleTabChange)` with `_tabController!.animation!.addListener(_handleTabAnimation)`
3. Replaced `_handleTabChange` (which checked `indexIsChanging`) with:
   ```dart
   void _handleTabAnimation() {
       final newIndex = (_tabController!.animation!.value).round();
       if (newIndex != _activeTabIndex) {
         setState(() {
           _activeTabIndex = newIndex;
         });
       }
   }
   ```
4. AppBar color now uses `_activeTabIndex` instead of `_tabController?.index`
5. Dispose properly removes animation listener before disposing controller

**How it works:**
- `TabController.animation` provides a real-time `Animation<double>` that goes from 0.0 to 1.0 (for two tabs) during both tap and swipe
- `.round()` determines which tab is visually dominant at any point
- `setState` is only called when the rounded index actually changes (at the midpoint), avoiding excessive rebuilds

---

## Test Scenarios Verified

### Issue 1

| Scenario | Expected | Status |
|---|---|---|
| Open dialog with TT-20 BLACK 500 pre-selected | Stepper shows 500 | Fixed |
| Open dialog with no product pre-selected | Stepper shows fallback (20) | Working |
| Select product via picker | Stepper updates to product's `packageQuantity` | Fixed |
| Switch product inside dialog | Stepper updates to new product's `packageQuantity` | Fixed |
| Manually reduce quantity before submit | Submitted value = user-edited value | Working |
| Manually increase quantity before submit | Submitted value = user-edited value | Working |
| Create partial/incomplete pallet | Works normally | Working |
| Success dialog after creation | Shows `productType.packageQuantity` in product info | Fixed |
| Pallet creation API submission | Sends user-controlled `_quantity` | Working (unchanged) |

### Issue 2

| Scenario | Expected | Status |
|---|---|---|
| Tap tab 1 / tab 2 from header | Color updates immediately | Working |
| Swipe from tab 1 to tab 2 | Color updates at midpoint of swipe | Fixed |
| Swipe from tab 2 to tab 1 | Color updates at midpoint of swipe | Fixed |
| Rapid switching (tap + swipe) | No mismatch between header and content | Fixed |
| Initial screen load | Tab 1 selected, correct color | Working |
| Loading shimmer state | TabBarView still works | Working (unchanged) |

---

## Summary

| Issue | Status | Type |
|---|---|---|
| Issue 1: Default quantity semantics | **Fully fixed** | Frontend-only |
| Issue 2: Tab header color delay | **Fully fixed** | Frontend-only (state sync) |

### Static Analysis

`flutter analyze` passes with **no issues** on all three modified files.

### Remaining Notes / Risks

- None. Both fixes are minimal, isolated, and do not affect backend contracts, business workflow, or other UI components.
