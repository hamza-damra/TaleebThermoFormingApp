# Pallet Label Side Text Size Fix

## 1. What Was Wrong

The pallet number + A/B indicator on the **left and right sides** of the label appeared significantly smaller than the top and bottom text. On the physical printed label, the side text was barely readable compared to the large, clear top/bottom text.

## 2. Why the Side Text Looked Smaller

The side text was rendered using `arial14` (14px bitmap font), while the top and bottom text used `arial48` or `arial24` (depending on label size). After rotation, the arial14 text appeared tiny — roughly **3–4× smaller** than the top/bottom text.

The side band width was also calculated from `arial14.lineHeight + gap`, making the allocated space too narrow to hold larger text.

**Before:**
| Position | Font     | Visual size |
|----------|----------|-------------|
| Top      | arial48  | Large       |
| Bottom   | arial48  | Large       |
| Left     | arial14  | Tiny        |
| Right    | arial14  | Tiny        |

## 3. What Was Changed

**File:** `lib/printing/label_renderer.dart`

### Layout changes (`LabelLayout.fromPreset`)
- Side band width now uses `mainFontH + gap` instead of `arial14H + gap`
- Removed unused `arial14H` variable
- This gives side bands the same proportional space as the top/bottom bands

### Rendering changes (`_drawLabelText`)
- Sides now use the **same `mainFont`** (arial48 or arial24) as top/bottom
- Replaced `_drawRotatedText` with `_drawScaledRotatedText`

### New `_drawScaledRotatedText` method
1. Renders text at full `mainFont` size on a temporary horizontal image
2. If text pixel width exceeds the available vertical space after rotation, scales the image proportionally using `img.copyResize` with `Interpolation.average`
3. Rotates the (possibly scaled) image by ±90°
4. Centers the rotated image within the side band
5. Composites only black pixels onto the destination

This ensures the side text starts at the same font size and is only scaled down if it physically doesn't fit — maintaining maximum visual parity with top/bottom.

## 4. How the Side Text Now Matches Top/Bottom Visually

**After:**
| Position | Font     | Rendering                              | Visual size |
|----------|----------|----------------------------------------|-------------|
| Top      | arial48* | Horizontal, centered                   | Large       |
| Bottom   | arial48* | Horizontal, centered                   | Large       |
| Left     | arial48* | Rotated CCW 90°, scaled to fit if needed | Large       |
| Right    | arial48* | Rotated CW 90°, scaled to fit if needed  | Large       |

*Falls back to arial24 on smaller labels (e.g., 50×25mm) where arial48 would make the QR too small.

**Key points:**
- All 4 sides use the **same font** for rendering
- Side text is rendered at full font size first, then proportionally scaled only if the text length exceeds available space
- Scaling uses `Interpolation.average` for clean downscaling without jagged edges
- The side text is centered both horizontally and vertically within its band
- The A/B indicator on the sides is the same size as on top/bottom

## 5. Physical Print Tests To Perform

### Visual parity
- [ ] Print a label on the most common preset (e.g., 60×40mm)
- [ ] Verify left/right text is visually the same size as top/bottom text
- [ ] Verify A/B indicator on sides is readable at arm's length
- [ ] Compare old label (photo provided) with new label side-by-side

### QR readability
- [ ] Scan QR code with phone camera on all default presets
- [ ] Verify QR quiet zone is maintained (no text overlapping QR)
- [ ] Test scanning from 30cm distance

### Text completeness
- [ ] Verify no text is clipped on left or right edges
- [ ] Verify text is centered on all 4 sides
- [ ] Verify correct pallet number + A/B on all 4 sides

### Multi-preset validation
- [ ] Print on 40×30mm — verify text fits and QR scans
- [ ] Print on 50×25mm — verify text fits and QR scans
- [ ] Print on 50×30mm — verify text fits and QR scans
- [ ] Print on 60×40mm — verify text fits and QR scans
- [ ] Print on 100×50mm — verify text fits and QR scans

### Printer behavior (unchanged)
- [ ] Labels tear correctly at the tear bar
- [ ] No extra feed after printing
- [ ] TSPL commands unchanged
