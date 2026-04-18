# Pallet Label Content Change — Backend-to-Frontend Specification

## Summary of the Label Change

The pallet label is being updated. Previously the label showed the scanned value (pallet number) plus a production-line letter (A/B) on all four sides. The new layout is:

| Label position | Old content | New content |
|---|---|---|
| **Top** | Pallet number + line letter (A/B) | **Product name** |
| **Bottom** | Pallet number + line letter (A/B) | **Product description** |
| **QR code** | scannedValue (12 digits) | **Unchanged** |

The QR-encoded value remains the `scannedValue` — no change.

---

## Backend Changes Applied

A **minimal backend change was required**: the `description` field was missing from `CreatePalletResponse.ProductTypeInfo`. It has been added.

### What changed

| File | Change |
|---|---|
| `src/main/java/ps/taleeb/taleebbackend/palletizing/dto/CreatePalletResponse.java` | Added `String description` field to inner class `ProductTypeInfo` |
| `src/main/java/ps/taleeb/taleebbackend/palletizing/PalletizingService.java` | Added `.description(productType.getDescription())` in `toCreatePalletResponse()` mapper |
| `src/main/java/ps/taleeb/taleebbackend/palletizing/FaletService.java` | Added `.description(productType.getDescription())` in `buildCreatePalletResponse()` mapper |
| `src/test/java/ps/taleeb/taleebbackend/palletizing/PalletizingServiceTest.java` | Added `description` to test fixture; added assertions verifying description is mapped (non-null and null cases) |

### What did NOT change

- No new endpoints
- No fields removed or renamed
- No database migration (description column already exists on `product_types` table)
- No QR content change
- No scanned-value generation change
- No print-attempt logging change
- `@JsonInclude(NON_NULL)` on `CreatePalletResponse` means null descriptions are omitted from JSON

### Old vs New `productType` in CreatePalletResponse

**Before:**
```json
"productType": {
  "id": 1,
  "name": "لنش بوكس مقطع بسن إغلاق واحد / أبيض / 500 كرتونة",
  "productName": "لنش بوكس مقطع بسن إغلاق واحد",
  "prefix": "073",
  "color": "أبيض",
  "packageQuantity": 500,
  "packageUnit": "CARTON"
}
```

**After:**
```json
"productType": {
  "id": 1,
  "name": "لنش بوكس مقطع بسن إغلاق واحد / أبيض / 500 كرتونة",
  "productName": "لنش بوكس مقطع بسن إغلاق واحد",
  "prefix": "073",
  "color": "أبيض",
  "packageQuantity": 500,
  "packageUnit": "CARTON",
  "description": "وصف المنتج هنا"
}
```

If description is null for a product type, the field is omitted entirely (not sent as `null`).

---

## Final Data Contract

### Field mapping for label rendering

| Label element | JSON path (from create-pallet response) | Field | Nullable? |
|---|---|---|---|
| **Top text** | `data.productType.productName` | Structured product name (Arabic) | No — always present |
| **Bottom text** | `data.productType.description` | Optional product description | **Yes — can be null/missing** |
| **QR content** | `data.scannedValue` | 12-digit pallet serial | No — always present |

### Fallback when description is null or blank

If `productType.description` is null or empty, the frontend should use the composite `productType.name` field as a fallback. This field is always present and contains a computed display name in the format:

```
{productName} / {color} / {packageQuantity} {packageUnitArabic}
```

Example: `"لنش بوكس مقطع بسن إغلاق واحد / أبيض / 500 كرتونة"`

**Recommended fallback logic:**
```dart
final String bottomText = (response.productType.description != null &&
                           response.productType.description.isNotEmpty)
    ? response.productType.description
    : response.productType.name;
```

---

## Affected Flows

### 1. Standard Pallet Creation

**Endpoint:** `POST /api/v1/palletizing-line/lines/{lineId}/pallets`

**Response type:** `CreatePalletResponse`

Both `productName` and `description` are now in `data.productType`.

### 2. FALET Convert-to-Pallet

**Endpoint:** `POST /api/v1/palletizing-line/lines/{lineId}/falet/convert-to-pallet`

**Response type:** `ConvertFaletToPalletResponse` which nests `CreatePalletResponse` at `data.pallet`

Fields available at `data.pallet.productType.productName` and `data.pallet.productType.description`.

### 3. Reprint Flow

There is **no dedicated reprint endpoint** on the backend. The app must use the `CreatePalletResponse` data it received at pallet-creation time. The app should cache/persist the pallet response (or at minimum `scannedValue`, `productName`, and `description`) locally so it can re-render the label for reprint without an additional API call.

If the app needs to look up product data independently (e.g., after a cold restart), the **bootstrap endpoint** already returns description:

**Endpoint:** `GET /api/v1/palletizing-line/bootstrap`

**Path:** `data.productTypes[].description` and `data.productTypes[].productName`

The session drill-down endpoint (`GET /lines/{lineId}/session-production-detail`) returns `productTypeName` per group but does NOT return `description` or `productName` separately — it is not suitable for label reprinting.

---

## Frontend Implementation Notes

### Flutter model update

Add the `description` field to the Flutter model class that parses `CreatePalletResponse.ProductTypeInfo`:

```dart
class ProductTypeInfo {
  final int id;
  final String name;
  final String productName;
  final String prefix;
  final String color;
  final int packageQuantity;
  final String packageUnit;
  final String? description;  // ← NEW — nullable

  // ... fromJson, etc.
}
```

In `fromJson`, parse it as optional:
```dart
description: json['description'] as String?,
```

### Label layout in TSPL

Update the TSPL command generation to replace the old pallet-number + line-letter text with product data:

```
REM ── existing TSPL preamble (SIZE, GAP, CLS, etc.) ── keep as-is

TEXT {x},{yTop},"{font}",0,1,1,"{productName}"
REM ── existing QRCODE command ── keep as-is
TEXT {x},{yBottom},"{font}",0,1,1,"{description or fallback}"

REM ── existing PRINT / tear-mode commands ── keep as-is
```

### What to remove from label

- Remove the pallet number text from the top and bottom label positions
- Remove the line letter (A / B) from the top and bottom label positions
- These were previously derived from `scannedValue` and `productionLine.lineNumber`

### What to keep

- QR code content (`scannedValue`) — unchanged
- All TSPL initialization commands (SIZE, GAP, SPEED, DENSITY, DIRECTION, CLS)
- Print / tear-mode sequence
- Printer connection logic

---

## Production Risks and Cautions

### Long text on small labels

Arabic product names and descriptions can be long. Examples:
- `productName`: `"لنش بوكس مقطع بسن إغلاق واحد"` (30+ chars)
- `description`: unbounded TEXT field — could be very long

**Recommendations:**
- Use a small but readable font size
- Truncate at a safe character limit (e.g., 40–50 chars) if the text would overflow the label width
- Test with the longest product name in the production database
- Arabic text renders right-to-left — ensure the TSPL font/encoding supports Arabic glyphs

### Null-safety for old pallets / old product records

- `productName` is `NOT NULL` in the database — always safe
- `description` is nullable — use the fallback logic documented above
- Old pallets created before this change will not have `description` in their cached response — the app should handle this gracefully at reprint time

### No migration impact

The `description` column already exists on the `product_types` table (added in the original schema). This change is purely at the DTO mapping layer. No Flyway migration is needed.

---

## Test Verification

To verify the backend change works correctly:

1. **Create a pallet** with a product type that has a description set → `data.productType.description` should be present in the response
2. **Create a pallet** with a product type that has no description → `data.productType.description` should be absent from the JSON (omitted by `@JsonInclude(NON_NULL)`)
3. **Convert a FALET to pallet** → `data.pallet.productType.description` should be present
4. **Existing tests pass:** `PalletizingServiceTest` (3 tests), `FaletServiceTest`, `PalletizingWorkflowAlignmentTest`

---

## Quick Reference

| What | Value |
|---|---|
| Top label text field | `productType.productName` |
| Bottom label text field | `productType.description` (fallback: `productType.name`) |
| QR content field | `scannedValue` |
| Backend files changed | 3 source + 1 test |
| New endpoints | None |
| New migrations | None |
| Breaking changes | None — additive only |
