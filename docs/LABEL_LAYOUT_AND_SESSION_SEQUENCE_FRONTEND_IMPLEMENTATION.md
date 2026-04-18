# Label Layout & Session Product Sequence — Frontend Implementation

## Overview

This document describes the frontend changes to support the new pallet label layout and the `sessionProductSequence` field from the backend.

---

## Backend Fields Used

| Field | Source Path (create-pallet) | Source Path (FALET convert) | Type |
|---|---|---|---|
| `sessionProductSequence` | `data.sessionProductSequence` | `data.pallet.sessionProductSequence` | `int?` |
| `productType.productName` | `data.productType.productName` | `data.pallet.productType.productName` | `String` |
| `productType.description` | `data.productType.description` | `data.pallet.productType.description` | `String?` |
| `scannedValue` | `data.scannedValue` | `data.pallet.scannedValue` | `String` |
| `productionLine.lineNumber` | `data.productionLine.lineNumber` | `data.pallet.productionLine.lineNumber` | `int` |

The `sessionProductSequence` is:
- A display-oriented, server-computed number
- Scoped per session + per product type
- Continues when returning to the same product in the same session
- Resets only when a new session starts
- **Never computed or incremented on the frontend**

---

## Label Layout Rules

### Top Side
- Content: `productName (sessionProductSequence)`
- Example: `TL-7 B250 Black (3)`
- If `sessionProductSequence` is null: show only `productName` (no parentheses)

### Bottom Side
- Content: `productType.description`
- Fallback: `productType.name` (the full composite name)
- Example: `Plate 250 Black`

### Left Side
- Content: `scannedValue (lineLetter)`
- Example: `037000000015 (A)`
- Rotated CCW 90° (reads bottom-to-top)

### Right Side
- Content: `scannedValue (lineLetter)`
- Example: `037000000015 (A)`
- Rotated CW 90° (reads top-to-bottom)

### QR Code
- Content: `scannedValue` (unchanged)
- No modifications to QR generation logic

### Line Letter Mapping
- Line 1 → `A`
- Line 2 → `B`

---

## Fallback Behavior

| Field | Condition | Fallback |
|---|---|---|
| `sessionProductSequence` | null | Omit parentheses, show only `productName` |
| `productType.description` | null or empty | Use `productType.name` |
| `lineLetter` | Uses existing `lineNumber` mapping | No change |
| Reprint flows | No `sessionProductSequence` available | Top shows `productName` only |

---

## Flows Covered

### 1. Standard Pallet Creation (`PalletSuccessDialog`)
- Full data available from `PalletCreateResponse`
- All four label sides populated with correct content
- `sessionProductSequence` displayed in top text

### 2. FALET Convert-to-Pallet
- Uses `FaletConvertToPalletResponse.pallet` (same `PalletCreateResponse` structure)
- Routed through `PalletSuccessDialog` — same label logic applies
- `sessionProductSequence` parsed from `data.pallet.sessionProductSequence`

### 3. Session Drilldown Reprint (`_ReprintDialog`)
- Looks up `ProductType` from bootstrap data by `productTypeId`
- No `sessionProductSequence` available (historical data)
- Top text shows `productName` without sequence
- Side text restored to `scannedValue (lineLetter)`

### 4. Reprint by ID (`ReprintByIdDialog`)
- Same lookup strategy as session drilldown
- Same fallback behavior

### 5. Retry Print (`PrintingProvider.retryPrint`)
- All three text fields (`topText`, `bottomText`, `sideText`) stored and reused

---

## Files Changed

### Domain / Model Layer
- **`lib/domain/entities/pallet_create_response.dart`** — Added `sessionProductSequence` (`int?`) field
- **`lib/data/models/pallet_create_response_model.dart`** — Parse `sessionProductSequence` from JSON; constructor updated

### Printing Pipeline
- **`lib/printing/label_renderer.dart`** — Added `sideText` parameter to `render()` and `_drawLabelText()`; side bands now use dedicated `sideText` instead of duplicating `topText`
- **`lib/printing/printer_client.dart`** — Added `sideText` parameter, passed through to `LabelRenderer`
- **`lib/presentation/providers/printing_provider.dart`** — Added `sideText` parameter to `print()`, stored as `_lastSideText` for retry

### Print Call Sites
- **`lib/presentation/widgets/pallet_success_dialog.dart`** — Builds `topText` = `productName (seq)`, `bottomText` = description/fallback, `sideText` = `scannedValue (lineLetter)`
- **`lib/presentation/widgets/session_drilldown_dialog.dart`** — Builds correct `sideText`; no sequence for reprints
- **`lib/presentation/widgets/reprint_by_id_dialog.dart`** — Builds correct `sideText`; no sequence for reprints

### Tests
- **`test/label_text_rendering_test.dart`** — Updated to cover sequence formatting, side text, and all three text fields

---

## Edge Cases

- **Old cached responses** without `sessionProductSequence`: parsed as `null`, top text shows `productName` only
- **Old responses** without `description`: falls back to composite `name`
- **Reprint from session history**: no sequence data, gracefully omitted
- **Long text**: side bands auto-scale (shrink) text to fit available space via `_drawScaledRotatedText`
- **Arabic text**: rendered via bitmap font (latin glyphs only in current `image` package); complex Arabic requires font extension
