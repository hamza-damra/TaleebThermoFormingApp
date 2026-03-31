# Mobile Searchable Pickers — Backend Handoff

This document describes the backend changes made to support professional searchable picker/dialog UX for operator and product type selection in the palletizing mobile app (تطبيق تكوين المشاتيح).

---

## Section 1: What Changed in the Backend

### Summary of Changes

The existing picker endpoints were enhanced in-place. **No new endpoints were created.** The same URLs are used, with backward-compatible additions.

### Modified Files

| File | Change |
|------|--------|
| `OperatorRepository.java` | Added `searchActiveByNameOrCode(query)` — active-only search by name or code |
| `ProductTypeRepository.java` | Added `searchActiveByQuery(query)` — active-only search by product name, color, prefix, or computed name |
| `OperatorResponse.java` | Added `displayLabel` field |
| `PalletizingProductTypeResponse.java` | Added `displayLabel` field |
| `PalletizingService.java` | Updated `getActiveOperators(query)` and `getActiveProductTypes(query)` to support optional search; updated mapping methods to populate `displayLabel` |
| `PalletizingController.java` | Added optional `q` query parameter to `GET /operators` and `GET /product-types` |

### Endpoint Changes

#### `GET /api/v1/palletizing/operators`

- **New optional query parameter:** `q` (string)
- When `q` is omitted or blank: returns all active operators sorted by name ascending (same as before)
- When `q` is provided: filters active operators where name OR code matches (case-insensitive LIKE), sorted by name ascending
- **Auth:** JWT, role `PALLETIZER`

**Response shape (unchanged URL, new field added):**

```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "name": "أحمد محمد",
      "code": "OP-001",
      "displayLabel": "أحمد محمد (OP-001)"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | Long | Operator ID (use for `operatorId` in create pallet / handover requests) |
| `name` | String | Operator name (Arabic) |
| `code` | String | Unique operator code |
| `displayLabel` | String | **NEW** — ready-to-use Arabic display label formatted as `"name (code)"` |

#### `GET /api/v1/palletizing/product-types`

- **New optional query parameter:** `q` (string)
- When `q` is omitted or blank: returns all active product types sorted by name ascending (same as before)
- When `q` is provided: filters active product types where product name, color, prefix, or computed name matches (case-insensitive LIKE), sorted by name ascending
- **Auth:** JWT, role `PALLETIZER`

**Response shape (unchanged URL, new field added):**

```json
{
  "success": true,
  "data": [
    {
      "id": 5,
      "name": "لنش بوكس مقطع / أبيض / 500 كرتونة",
      "productName": "لنش بوكس مقطع",
      "prefix": "0001",
      "color": "أبيض",
      "packageQuantity": 500,
      "packageUnit": "CARTON",
      "packageUnitDisplayName": "كرتونة",
      "displayLabel": "لنش بوكس مقطع - أبيض (500 كرتونة)"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | Long | Product type ID (use for `productTypeId` in create pallet / handover requests) |
| `name` | String | Computed full display name (`productName / color / quantity unit`) |
| `productName` | String | Product name only (e.g. `"لنش بوكس مقطع"`) |
| `prefix` | String | 4-digit prefix code (e.g. `"0001"`) |
| `color` | String | Color (e.g. `"أبيض"`, `"أسود"`, `"شفاف"`) |
| `packageQuantity` | Integer | Items per package (e.g. 500) |
| `packageUnit` | String (enum) | `"CARTON"` or `"BAG"` |
| `packageUnitDisplayName` | String | Arabic unit label (`"كرتونة"` or `"كيس"`) |
| `displayLabel` | String | **NEW** — ready-to-use Arabic display label formatted as `"productName - color (quantity unit)"` |

### Search Behavior

- Search is **case-insensitive** and uses **substring matching** (SQL `LIKE '%query%'`)
- Search is performed **server-side** but the frontend may also do local filtering for instant responsiveness
- Only **active** records are returned — inactive operators/product types are never included
- Results are always sorted by **name ascending** (alphabetical, Arabic-friendly)
- Omitting `q` returns the full active list (identical behavior to before this change)

### Backward Compatibility

- **Fully backward compatible.** Calling the endpoints without `?q=` returns the exact same response as before, with one additional field (`displayLabel`) that new clients can use and old clients will ignore.
- No existing endpoint was removed or renamed.
- No request body contract changed.
- The `createPallet`, `createPendingHandover`, `confirmHandover`, and `rejectHandover` flows are completely unaffected.

---

## Section 2: What the Frontend Should Do

### Architecture Recommendation

Since the typical number of operators and product types in this factory is small (tens, not thousands), the recommended approach is:

1. **Load the full list once** on screen open by calling the endpoint without `?q=`
2. **Filter locally** in the picker dialog as the user types
3. **Optionally** use server-side `?q=` for larger datasets or pull-to-refresh scenarios

This gives the fastest perceived search speed while keeping the backend available as a fallback.

### Operator Picker

When the user taps the operator field (اسم المشغل):

1. Open a searchable dialog / bottom sheet / full-screen picker
2. Fetch `GET /api/v1/palletizing/operators` (full active list)
3. Display each operator using `displayLabel` (e.g. "أحمد محمد (OP-001)")
4. Allow typing to filter — match against `name`, `code`, or `displayLabel` locally
5. On selection: store `id` for the API call, display `displayLabel` on the main form
6. Support RTL layout

### Product Type Picker

When the user taps the product field (نوع المنتج):

1. Open a searchable dialog / bottom sheet / full-screen picker
2. Fetch `GET /api/v1/palletizing/product-types` (full active list)
3. Display each product type using `displayLabel` (e.g. "لنش بوكس مقطع - أبيض (500 كرتونة)")
4. Allow typing to filter — match against `productName`, `color`, `prefix`, `name`, or `displayLabel` locally
5. Optionally show `prefix` as a subtitle or secondary text
6. On selection: store `id` for the API call, display `displayLabel` on the main form
7. Support RTL layout

### What to Send to Backend

When creating a pallet (`POST /api/v1/palletizing/pallets`):

```json
{
  "operatorId": 1,
  "productTypeId": 5,
  "productionLineId": 2,
  "quantity": 500
}
```

When creating a handover (`POST /api/v1/shift-handover`), items include:

```json
{
  "operatorId": 1,
  "items": [
    {
      "productionLineId": 2,
      "productTypeId": 5,
      "quantity": 300
    }
  ]
}
```

The IDs sent to the backend are the `id` values from the picker responses. Nothing else changes.

---

## Section 3: Prompt for the Frontend AI Agent

Copy and paste the following prompt to the frontend AI agent to implement the mobile side.

---

### BEGIN FRONTEND AGENT PROMPT

You are working on the Taleeb Thermoforming palletizing mobile app (تطبيق تكوين المشاتيح).

Your task is to replace the existing primitive dropdown selectors for **operator** (اسم المشغل) and **product type** (نوع المنتج) with professional searchable picker dialogs.

This applies to all screens that currently use these dropdowns, including:
- The main pallet creation screen
- The shift handover creation flow (outgoing operator selection)
- The shift handover confirm/reject flow (incoming operator selection)
- Any other screen that selects an operator or product type

#### Backend API Details

The backend already provides everything needed. Use these endpoints:

**Operators:**
- `GET /api/v1/palletizing/operators` — returns all active operators
- `GET /api/v1/palletizing/operators?q=search_term` — server-side search (optional)
- Auth: JWT Bearer token, role PALLETIZER
- Response fields per item:
  - `id` (Long) — operator ID to send in requests
  - `name` (String) — operator name in Arabic
  - `code` (String) — unique operator code
  - `displayLabel` (String) — **use this as the primary display text**, formatted as `"name (code)"`

**Product Types:**
- `GET /api/v1/palletizing/product-types` — returns all active product types
- `GET /api/v1/palletizing/product-types?q=search_term` — server-side search (optional)
- Auth: JWT Bearer token, role PALLETIZER
- Response fields per item:
  - `id` (Long) — product type ID to send in requests
  - `name` (String) — full computed name
  - `productName` (String) — product name only
  - `color` (String) — product color
  - `prefix` (String) — 4-digit prefix code
  - `packageQuantity` (Integer) — quantity per package
  - `packageUnit` (String) — `"CARTON"` or `"BAG"`
  - `packageUnitDisplayName` (String) — Arabic unit label
  - `displayLabel` (String) — **use this as the primary display text**, formatted as `"productName - color (quantity unit)"`

Both endpoints return:
```json
{
  "success": true,
  "data": [ ... ]
}
```

Both lists are small (tens of items), already sorted alphabetically by name, and contain only active items.

#### Implementation Requirements

1. **Replace primitive dropdowns** with searchable picker dialogs for both operator and product type selection
2. **Picker UX:**
   - When the user taps the operator or product type field, open a modal/bottom sheet/dialog
   - Show a search/filter text field at the top of the dialog
   - Show the list of items below, each displaying `displayLabel` as the primary text
   - For product types, optionally show `prefix` as secondary text or subtitle
   - Support instant local filtering as the user types (match against `displayLabel`, `name`, `code` for operators; `displayLabel`, `name`, `productName`, `color`, `prefix` for products)
   - Show an empty state message when no results match (e.g. "لا توجد نتائج")
   - Show a loading state while fetching data
   - Show an error state with retry option if the fetch fails
   - Tapping an item selects it and closes the dialog
   - The selected item's `displayLabel` should be shown on the main form
   - Store the selected item's `id` to send in API requests
3. **Arabic RTL support:**
   - All text is Arabic — ensure the picker dialog, search field, and list items properly support RTL layout
   - Text alignment should be right-to-left
   - Search field hint text in Arabic (e.g. "ابحث عن المشغل..." or "ابحث عن المنتج...")
4. **Loading strategy:**
   - Load the full list once when the picker opens (call endpoint without `?q=`)
   - Filter locally as the user types for instant responsiveness
   - Do NOT call the backend on every keystroke
   - Cache the list for the duration of the screen lifecycle (refetch only on pull-to-refresh or screen re-entry if appropriate)
5. **Make the picker component reusable:**
   - Create a single reusable searchable picker component/widget
   - Parameterize: title, hint text, items list, display text extractor, search matcher, onSelect callback
   - Use it for both operator and product type pickers (and potentially production line picker in the future)
6. **Preserve existing behavior:**
   - Do not break the pallet creation flow — `operatorId`, `productTypeId`, `productionLineId` must still be sent correctly
   - Do not break the shift handover flow — operator IDs must still be sent correctly
   - Do not break the production line tabs or any other navigation
   - The selected value must persist correctly when navigating between tabs/screens
7. **Production-ready quality:**
   - Smooth animations for dialog open/close
   - Proper keyboard handling (dismiss keyboard when selecting, focus search field on open)
   - Support phones and tablets
   - No visual glitches or layout overflow
   - Handle edge cases: empty list, single item, very long item names
8. **State management:**
   - Keep existing state management architecture (do not introduce new state management libraries)
   - Fetch picker data using the existing API service/client layer
   - Store selected operator/product type in the existing form state

#### What NOT to do

- Do NOT change the backend API calls for creating pallets or handovers (the request body is unchanged)
- Do NOT add new dependencies unless absolutely necessary for the picker UX
- Do NOT change the app navigation structure
- Do NOT break any existing functionality
- Do NOT hardcode operator or product type data

### END FRONTEND AGENT PROMPT
