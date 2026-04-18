# Product Count UI Fix Report

## Bug Summary

Product type **TT-20 BLACK 500** (packageQuantity = 500 عبوة) was incorrectly displaying **20** in the "إنشاء مشتاح جديد" (Create Pallet) dialog and the "تم إنشاء المشتاح بنجاح" (Pallet Created Successfully) dialog.

---

## Root Cause

**Semantic mismatch between two distinct quantity concepts:**

| Concept | Field | Meaning |
|---|---|---|
| Product package count | `ProductType.packageQuantity` | Standard carton count for the product type (e.g., 500 for TT-20 BLACK 500) |
| Pallet creation quantity | `PalletCreateResponse.quantity` / user-entered `_quantity` | The quantity submitted when creating a pallet |

### In `create_pallet_dialog.dart`

The quantity stepper was initialized with a **hardcoded default of 20** (`int _quantity = 20`) instead of using the selected product type's `packageQuantity`. Additionally, when the user changed the product selection via the picker, the quantity was **not updated** to the newly selected product's `packageQuantity`.

### In `pallet_success_dialog.dart`

The "الكمية" (Quantity) info row displayed `widget.pallet.quantity` (the pallet's submitted quantity, which was 20 due to the wrong default) instead of `widget.pallet.productType.packageQuantity` (the product's actual package count). Since this row sits in the product info section alongside product name and color, it should reflect the product type attribute, not the pallet submission value.

---

## Issue Classification

**Frontend-only bug.** No backend issue was found. The backend correctly stores and returns whatever quantity is submitted. The `PalletCreateResponseModel.fromJson` correctly parses `productType.packageQuantity` from the API response.

---

## Changes Made

### 1. `lib/presentation/widgets/create_pallet_dialog.dart`

- **Line 27:** Changed `int _quantity = 20;` → `late int _quantity;`
- **Line 34:** Added `_quantity = _selectedProductType?.packageQuantity ?? 20;` in `initState()` to initialize from the selected product's `packageQuantity`.
- **Lines 141-145:** Added `_quantity = selected.packageQuantity;` and `_quantityController.text = '$_quantity';` when a new product is selected via the picker, so the stepper updates to the new product's standard count.

### 2. `lib/presentation/widgets/pallet_success_dialog.dart`

- **Line 102:** Changed `widget.pallet.quantity` → `widget.pallet.productType.packageQuantity` in the "الكمية" info row, so it displays the product's standard package count instead of the pallet submission quantity.

---

## Bug Status

**Fully fixed.**

---

## Screens/Dialogs Corrected

1. **إنشاء مشتاح جديد** (Create New Pallet dialog) — quantity stepper now defaults to the selected product's `packageQuantity`
2. **تم إنشاء المشتاح بنجاح** (Pallet Created Successfully dialog) — "الكمية" row now shows the product type's `packageQuantity`

---

## Test Scenarios

| Scenario | Expected Result |
|---|---|
| Open create dialog with TT-20 BLACK 500 pre-selected | Stepper shows 500 |
| Open create dialog with no product pre-selected | Stepper shows fallback (20) |
| Select TT-20 BLACK 500 via product picker | Stepper updates to 500 |
| Switch from one product to another | Stepper updates to new product's `packageQuantity` |
| Create pallet and view success dialog | "الكمية" row shows product's `packageQuantity` + unit name |
| Other product types | Show their respective `packageQuantity` correctly |
| Pallet creation submission | Still sends the user's (possibly adjusted) quantity to the API — no regression |
| Product switch and session summary | Unaffected — uses `productType.packageQuantity` directly (verified in `production_line_section.dart` line 740) |

---

## Backend Notes

No backend changes needed. The backend API:
- Correctly provides `packageQuantity` in the `productType` object of the pallet create response
- The `quantity` field in `PalletCreateResponse` represents the pallet's submitted quantity (separate concept)
- JSON parsing in `PalletCreateResponseModel.fromJson` is correct

---

## Static Analysis

`flutter analyze` passes with **no issues** on both modified files.
