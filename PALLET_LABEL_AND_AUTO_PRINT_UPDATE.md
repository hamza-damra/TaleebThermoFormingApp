# Pallet Label & Auto-Print Update

## 1. What Was Changed

### A/B Indicator Source (Bug Fix)
- **Before**: A/B was derived from `productType.packageUnit` (CARTON → A, BAG → B), which printed "A" for both lines.
- **After**: A/B is derived from `lineNumber` — the **same source** used by the success dialog to display "خط الإنتاج 1" / "خط الإنتاج 2".

### Label Layout (4-Side Text)
- **Before**: Pallet number appeared only above and below the QR in small arial24 font.
- **After**: Pallet number + A/B indicator rendered on **all 4 sides** of the QR code with a larger font.

### Auto-Print After Pallet Creation
- **Before**: After creating a pallet, a success dialog appeared with a manual "طباعة الملصق" button.
- **After**: Printing starts **automatically** as soon as pallet creation succeeds. No manual print button.

---

## 2. How A/B Is Now Determined

```
lineNumber == 1  →  "A"
lineNumber == 2  →  "B"
```

- `lineNumber` is the same integer already used to display "خط الإنتاج 1" / "خط الإنتاج 2" in the pallet success dialog.
- In `PalletSuccessDialog`: uses `widget.lineNumber`.
- In `_ReprintDialog` (session drilldown): uses `widget.line.number`.
- No backend changes. No new fields. Same source as the dialog's production line display.

---

## 3. Confirmation: A/B Uses Same Source as Dialog Line Display

The success dialog shows:

```
_buildInfoRow('خط الإنتاج', widget.pallet.productionLine.name)
```

And the A/B indicator uses:

```dart
final indicator = widget.lineNumber == 1 ? 'A' : 'B';
```

Both `widget.lineNumber` and `widget.pallet.productionLine` originate from the same `line.number` passed by the production line section. **They are the same source.**

---

## 4. How the New 4-Side Label Layout Works

```
+------------------------------------------------+
|  [margin]                                      |
|    ┌──────────────────────────────────────┐    |
|    │    0370000005  A   (top, large font) │    |
|    └──────────────────────────────────────┘    |
|    [gap]                                       |
|  ┌──┐  ┌────────────────────────┐  ┌──┐       |
|  │ L│  │                        │  │R │       |
|  │ e│  │                        │  │i │       |
|  │ f│  │       QR CODE          │  │g │       |
|  │ t│  │                        │  │h │       |
|  │  │  │                        │  │t │       |
|  └──┘  └────────────────────────┘  └──┘       |
|    [gap]                                       |
|    ┌──────────────────────────────────────┐    |
|    │   0370000005  A  (bottom, large font)│    |
|    └──────────────────────────────────────┘    |
|  [margin]                                      |
+------------------------------------------------+
```

### Font Selection
| Position     | Font     | Notes                                            |
|-------------|----------|--------------------------------------------------|
| Top         | arial48* | Large, horizontally centered                     |
| Bottom      | arial48* | Large, horizontally centered                     |
| Left        | arial14  | Rotated 90° CCW, reads bottom-to-top             |
| Right       | arial14  | Rotated 90° CW, reads top-to-bottom              |

*Falls back to arial24 on smaller labels (e.g., 50×25mm) to keep QR ≥ 80 dots (~10mm).

### Side Text
- Rendered only if the rotated text width fits in the available vertical space between top and bottom bands.
- Skipped gracefully if the text is too long for the label size.

### QR Safety
- QR size is always ≥ 80 dots (~10mm) across all default presets.
- Text bands never overlap the QR code.
- A 6-dot gap separates each text band from the QR zone.

---

## 5. Confirmation: Center Text Was Removed

- No text is rendered inside or on top of the QR code.
- No text is placed in the QR center area.
- The old 2-side (top/bottom only) layout was replaced with the 4-side layout.
- The QR center zone is exclusively reserved for the QR code bitmap.

---

## 6. How Automatic Printing Works After Pallet Creation

### Flow
1. User presses "إنشاء طبلية"
2. Pallet creation API succeeds
3. `PalletSuccessDialog` opens with `_isPrinting = true`
4. `initState` triggers `_handlePrint()` via `addPostFrameCallback`
5. Printing starts immediately — dialog shows spinner + "جاري الطباعة..."
6. On **success**: dialog shows "تمت الطباعة بنجاح" with close button
7. On **failure**: dialog shows error with retry + close buttons

### Key Rules
- No separate "طباعة الملصق" button exists in the flow.
- The dialog cannot be dismissed while printing is in progress.
- Pallet creation is **never** retried — only printing is retried.

---

## 7. How Retry / Close Works on Print Failure

### Print Failure Dialog
When automatic printing fails, the dialog shows:

| Button           | Action                                               |
|-----------------|------------------------------------------------------|
| **إعادة المحاولة** | Retries label printing for the same pallet. Does NOT recreate the pallet. Uses stored `labelText` and `scannedValue`. |
| **إغلاق**        | Dismisses the dialog. The pallet remains created.    |

### Technical Detail
- `PrintingProvider` stores `_lastPrintedValue` and `_lastLabelText` on first print.
- `retryPrint()` reuses these stored values — no pallet creation API call.
- The retry button calls `_handleRetryPrint` → `_handlePrint` which re-derives the label text from the same `widget.pallet` and `widget.lineNumber`.

---

## 8. What Should Be Tested Physically on the Printer

### A/B Indicator
- [ ] Create a pallet on **line 1** → label shows "A"
- [ ] Create a pallet on **line 2** → label shows "B"
- [ ] Verify A/B matches the "خط الإنتاج" shown in the dialog

### Label Layout
- [ ] Pallet number + A/B visible on **top** of QR (large text)
- [ ] Pallet number + A/B visible on **bottom** of QR (large text)
- [ ] Pallet number + A/B visible on **left** of QR (small rotated text, if label is large enough)
- [ ] Pallet number + A/B visible on **right** of QR (small rotated text, if label is large enough)
- [ ] No text inside or overlapping the QR code
- [ ] QR code scans correctly with a phone/scanner
- [ ] Text is clearly readable without scanning

### Auto-Print
- [ ] After pressing "إنشاء طبلية", label prints automatically without pressing a separate button
- [ ] Dialog shows "جاري الطباعة..." with spinner during printing
- [ ] On success: dialog shows "تمت الطباعة بنجاح" with close button
- [ ] On failure: dialog shows "إعادة المحاولة" + "إغلاق" buttons
- [ ] Retry prints the same label (not a new pallet)
- [ ] Close dismisses without affecting the created pallet

### Tear Mode / T13
- [ ] Labels tear correctly at the tear bar (SET TEAR ON preserved)
- [ ] No extra feed after printing
- [ ] TSPL command sequence unchanged (SIZE, GAP, CLS, BITMAP, PRINT)

---

## Files Changed

| File | Change Summary |
|------|---------------|
| `lib/printing/label_renderer.dart` | 4-side layout, dynamic font selection, rotated side text |
| `lib/presentation/widgets/pallet_success_dialog.dart` | Auto-print in initState, A/B from lineNumber, removed manual print button |
| `lib/presentation/widgets/session_drilldown_dialog.dart` | A/B from line.number |
| `lib/presentation/providers/printing_provider.dart` | labelText parameter + storage for retry |
| `lib/printing/printer_client.dart` | labelText pass-through |
| `test/label_text_rendering_test.dart` | 19 tests covering A/B, 4-side layout, rendering |
