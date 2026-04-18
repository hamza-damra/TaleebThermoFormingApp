# Product Type Description — Frontend Integration Note

## Summary

Backend changes **were required** and have been implemented. The `description` field was present on the `ProductType` entity and the admin API, but was **not exposed** in the palletizing app's product type responses. It is now included.

## What Changed (Backend)

| File                                              | Change                                       |
| ------------------------------------------------- | -------------------------------------------- |
| `PalletizingProductTypeResponse.java`             | Added `description` field                    |
| `PalletizingService.toProductTypeResponse()`      | Maps `pt.getDescription()` into the response |
| `BootstrapResponse.ProductTypeItem`               | Added `description` field                    |
| `PalletizingBootstrapService.toProductTypeItem()` | Maps `pt.getDescription()` into the response |

## API Field Details

- **Field name**: `description`
- **Type**: `String` (nullable)
- **Content**: Admin-entered product description/notes text

## Endpoints That Now Include `description`

### 1. Bootstrap endpoint

```
GET /api/v1/palletizing-line/bootstrap
```

Response path: `data.productTypes[].description`

### 2. Active product types (search)

Called via `PalletizingService.getActiveProductTypes(query)` — returns `List<PalletizingProductTypeResponse>`, each item now includes `description`.

## Frontend Requirements

### Product Picker / Product Selection UI

The product description should be displayed **visibly** alongside the product name in the product selection list:

1. **Primary line**: Product display label (name / color / quantity) — already shown
2. **Secondary line**: Product description — **new**, show below or alongside the product name as a stable helper text

### Display Rules

- The description should appear as a **visible secondary text line** under the product name, not hidden behind a tap/click
- Use a lighter/smaller font style to visually distinguish it from the product name
- The description is **optional** — it may be `null` or empty string

### Null/Empty Fallback

- If `description` is `null` or blank: **do not render** the description line at all
- Do not show placeholder text like "No description" — simply omit the line
- The product item should still look correct without the description (no extra blank space)

### Example Layout

```
┌────────────────────────────────────────┐
│ [image]  أحمر - أحمر (50 عبوة)       │
│          وصف المنتج من الإدارة          │
└────────────────────────────────────────┘
```

When description is null:

```
┌────────────────────────────────────────┐
│ [image]  أحمر - أحمر (50 عبوة)       │
└────────────────────────────────────────┘
```

## Backward Compatibility

This is a purely additive change. The `description` field is a new optional JSON property. Existing clients that do not read it will be unaffected.

## Additional Frontend Display Requirements

The product description must not be limited to the product picker list only.

It must also be displayed in all product-selection related UI states below:

### 1. Product picker dialog list

Show the description as a secondary text line under each product name in the selectable list.

### 2. Product switch confirmation dialog

When the operator selects a new product and the switch confirmation dialog appears, show:

- previous product name + description (if available)
- new product name + description (if available)

The description should be visible and readable, not hidden.

### 3. Selected product field on the main screen

After the operator selects a product, the chosen product area/card on the main palletizing screen must also show:

- product name on the primary line
- product description on a secondary smaller line

This should remain visible as stable product details after selection, not only inside the picker.

### 4. Create pallet / create order related product confirmation dialog

If there is a dialog/card that confirms the selected product before pallet creation, also show the description there when available.

### Null / Blank fallback

If description is null or blank:

- do not render the description line
- do not show placeholder text
- collapse spacing cleanly
