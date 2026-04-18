# Palletizing App — T13 Tear Mode Port

## 1. What was copied from T13

The exact TSPL command sequence behavior from `T13` (strategy code `'T13'`, titled `'وضع التمزيق فقط'`) in the TALEEB PRINTER diagnostic pipeline was ported. Specifically:

- **Tear mode enabled**: `SET TEAR ON` before `CLS`/`BITMAP`/`PRINT`.
- **Positioning resets**: `OFFSET 0 mm`, `SHIFT 0`, `REFERENCE 0,0` before mode commands.
- **Mode commands**: `SET PEEL OFF`, `SET TEAR ON`, `SET CUTTER OFF` in that exact order.
- **No post-PRINT FEED**: The command sequence ends at `PRINT 1,1` with no trailing `FEED`.
- **GAP second parameter**: Uses `0.0 mm` (not shorthand `0 mm`).

Source reference: `T13_TEAR_MODE_TRANSFER_SPEC.md` from TALEEB PRINTER codebase.

## 2. Where it was integrated in this app

### Files modified

| File | Change |
|------|--------|
| `lib/core/constants/tspl_constants.dart` | Added `setTearOn = 'SET TEAR ON'` constant. |
| `lib/printing/tspl_builder.dart` | Added `setTearOn()` method. Changed `createLabelPrint()` to call `setTearOn()` instead of `setTearOff()`. Fixed GAP format to `0.0 mm`. |

### Files NOT modified (unchanged, verified correct)

| File | Reason |
|------|--------|
| `lib/printing/printer_client.dart` | Already calls `createLabelPrint()` correctly; no FEED logic exists. |
| `lib/printing/label_renderer.dart` | Label content/bitmap rendering is independent of TSPL command sequence. |
| `lib/core/constants/printing_constants.dart` | `defaultGapMm = 2.0` already matches T13 reference value. |
| `lib/domain/entities/label_preset.dart` | Label sizes and margins are unrelated to command sequence. |

### Test file created

| File | Purpose |
|------|---------|
| `test/tspl_t13_command_sequence_test.dart` | 10 focused tests verifying T13 command behavior. |

## 3. Exact final command sequence now used

Each command is terminated with `\r\n` (`TsplConstants.lineEnding`):

```
1.  SIZE <w> mm,<h> mm
2.  GAP <gap> mm,0.0 mm
3.  DIRECTION 0
4.  OFFSET 0 mm
5.  SHIFT 0
6.  REFERENCE 0,0
7.  SET PEEL OFF
8.  SET TEAR ON
9.  SET CUTTER OFF
10. CLS
11. BITMAP 0,0,<widthBytes>,<heightDots>,0,<raw monochrome bytes>
12. PRINT 1,1
```

- `<w>` / `<h>` come from `LabelPreset.widthMm` / `heightMm`.
- `<gap>` comes from `PrintingConstants.defaultGapMm` (2.0).
- `<widthBytes>` / `<heightDots>` come from `LabelRenderResult`.
- Binary bitmap payload is inserted between the BITMAP header and PRINT command.

## 4. Confirmation: no FEED after PRINT

**Confirmed.** The `createLabelPrint()` method in `TsplBuilder` produces:

1. Pre-bitmap commands (SIZE through BITMAP header)
2. Raw bitmap bytes
3. `PRINT 1,<copies>` only

There is **no** `FEED`, `FORMFEED`, or `HOME` command after `PRINT`. This matches T13 exactly (`resolvePresentFeedMm` returns 0 → `forwardDots == 0` → no `FEED` appended).

## 5. App-specific notes and risks

### Notes

- **Previous behavior**: The app was sending `SET TEAR OFF` before this port. This was the **only** divergence from T13 in the command sequence — all other commands (SIZE, GAP, DIRECTION, OFFSET, SHIFT, REFERENCE, SET PEEL OFF, SET CUTTER OFF, CLS, BITMAP, PRINT) were already in the correct T13 order.
- **GAP format fix**: Changed from `0 mm` to `0.0 mm` to exactly match the T13 spec's `GAP <gap> mm,0.0 mm` format.
- **Label content unchanged**: QR rendering, bitmap generation, and business data logic in `LabelRenderer` were not touched.
- **Copies**: Default is `1`, yielding `PRINT 1,1`. The `copies` parameter is still passed through for flexibility but T13 behavior expects single-label printing.

### Risks

- **Printer state persistence**: `SET TEAR ON` is persistent on the printer firmware until changed by another job. If other apps send `SET TEAR OFF`, this app will re-assert `SET TEAR ON` on each print job (same as T13 diagnostic behavior).
- **`setTearOff()` still available**: The old `setTearOff()` method was kept in `TsplBuilder` for backward compatibility but is **not called** in the production print path.
- **No mixed strategies**: This port does not implement feed percentage, fixed feed mm, offset experiments, or alignment tricks. It is a pure T13 reproduction.
