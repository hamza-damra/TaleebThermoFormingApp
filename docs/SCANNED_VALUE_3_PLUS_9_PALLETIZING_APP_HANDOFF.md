# Scanned Value 3+9 Format — Palletizing App Handoff

> **Document Purpose:** This document is written for the AI agent / developer working on the Flutter palletizing app. It describes the backend format change from 4+8 to 3+9 scanned values and all impacts on the palletizing workflow.

---

## 1. What Changed

The scanned value (QR code payload) format changed from **4-digit prefix + 8-digit serial** to **3-digit prefix + 9-digit serial**. Total length remains **12 numeric digits**.

| Aspect | Old (4+8) | New (3+9) |
|---|---|---|
| Prefix length | 4 digits | **3 digits** |
| Serial length | 8 digits | **9 digits** |
| Total length | 12 digits | 12 digits (unchanged) |
| Max serial | 99,999,999 | **999,999,999** |
| Example | `0073 00000125` | `073 000000125` |
| Full value | `"007300000125"` | `"073000000125"` |

### Migration Impact (V31)

This is a **pre-production hard cutover**:
- `product_types.prefix` column narrowed from `VARCHAR(4)` to `VARCHAR(3)`
- All serial counters reset to 0
- All existing pallets, movements, and statuses deleted
- **No backward compatibility** — old 4+8 values no longer exist

---

## 2. API Response Changes

### `POST /api/v1/palletizing/lines/{lineId}/pallets` — CreatePalletResponse

The `scannedValue` field now returns a 3+9 format value:

```json
{
  "palletId": 500,
  "scannedValue": "073000000001",
  "operator": { "name": "أحمد" },
  "productType": {
    "id": 5,
    "name": "Red 20kg",
    "prefix": "073"
  },
  "quantity": 50,
  "currentDestination": "PRODUCTION",
  "createdAt": "2025-06-15T10:30:00.000+03:00",
  "createdAtDisplay": "15/06/2025، 10:30 صباحًا"
}
```

**Key fields affected:**
- `scannedValue` — now `"073000000001"` (prefix `"073"` + serial `"000000001"`)
- `productType.prefix` — now 3 digits (e.g., `"073"` instead of `"0073"`)

### Other affected responses

All palletizing responses that wrap `CreatePalletResponse` follow the same format:
- `CompleteIncompletePalletResponse.pallet.scannedValue`
- `ConvertFaletToPalletResponse.pallet.scannedValue`
- `ProducePalletFromLooseResponse.pallet.scannedValue`
- `SessionPalletDetail.scannedValue` and `SessionPalletDetail.serialNumber`

### SessionPalletDetail.serialNumber

This field returns the serial portion **without the prefix** — now 9 digits instead of 8:

| Old | New |
|---|---|
| `"00000042"` (8 digits) | `"000000042"` (9 digits) |

---

## 3. QR Code Generation

The Flutter app generates QR codes from the `scannedValue` returned by the backend.

**No change needed in QR generation logic** — the app should already be using the raw `scannedValue` string as the QR payload. The string is still exactly 12 numeric digits.

However, if the app displays the prefix or serial separately (e.g., in labels), update:
- **Prefix** = first 3 characters of `scannedValue` (was 4)
- **Serial** = last 9 characters of `scannedValue` (was 8)

---

## 4. Product Type Prefix Display

If the palletizing app shows the product type prefix anywhere (e.g., product type selection, labels):

| Old | New |
|---|---|
| `"0073"` | `"073"` |
| `"0001"` | `"001"` |
| `"0007"` | `"007"` |

The `productType.prefix` field in API responses is now always exactly 3 digits.

---

## 5. Print Label Layout

If the printed label includes:
- **QR code:** No change — still 12 digits
- **Human-readable prefix:** Now 3 digits — adjust label layout if the prefix is printed separately
- **Human-readable serial:** Now 9 digits — adjust layout if printed separately
- **Full scanned value text:** No change — still 12 characters

### Label format suggestion

```
┌─────────────────────────┐
│  ┌───────┐              │
│  │  QR   │  073-000000001  │
│  │ CODE  │  Red 20kg       │
│  └───────┘  50 pcs         │
└─────────────────────────┘
```

---

## 6. Validation Rules

The backend enforces these via `ScannedValueParser`:

| Rule | Value |
|---|---|
| Total length | Exactly 12 digits |
| Characters | Numeric only (`0-9`) |
| Prefix | First 3 digits — must match an active `ProductType.prefix` |
| Serial | Last 9 digits — auto-generated, zero-padded |

The palletizing app **does not submit** scanned values to the backend — the backend generates them. But if the app validates QR scans (e.g., re-scanning a label for verification), apply the 12-digit numeric check.

---

## 7. Checklist for Palletizing App

- [ ] Update prefix display from 4 chars to 3 chars wherever shown
- [ ] Update serial extraction if splitting scanned value: `substring(0, 3)` for prefix, `substring(3)` for serial
- [ ] Update label printing layout if prefix/serial are printed separately
- [ ] Update any hardcoded format strings (e.g., `"%04d"` → `"%03d"` for prefix display)
- [ ] Update any local validation of scanned value format if present
- [ ] Test QR scanning still works (12-digit payload unchanged)
- [ ] Remove any references to 4-digit prefix in UI strings or help text

---

## 8. No Action Needed

- QR code encoding/decoding — still 12-digit numeric string
- Backend endpoint URLs — unchanged
- Authentication — unchanged
- Pallet creation flow — unchanged (backend generates scanned values)
- Print logging — unchanged
