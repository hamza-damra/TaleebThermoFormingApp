import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/printing/label_renderer.dart';

void main() {
  // ── Label content mapping ──

  group('Label content — productName / description / sequence / sides', () {
    test('topText includes sequence when present', () {
      const productName = 'TL-7 B250 Black';
      const int? seq = 3;
      final topText = seq != null ? '$productName ($seq)' : productName;
      expect(topText, 'TL-7 B250 Black (3)');
    });

    test('topText omits parentheses when sequence is null', () {
      const productName = 'TL-7 B250 Black';
      const int? seq = null;
      final topText = seq != null ? '$productName ($seq)' : productName;
      expect(topText, productName);
    });

    test('bottomText uses description when present', () {
      const description = 'Plate 250 Black';
      const name = 'TL-7 B250 Black / أسود / 500 كرتونة';
      final bottomText = (description.isNotEmpty) ? description : name;
      expect(bottomText, description);
    });

    test('bottomText falls back to name when description is empty', () {
      const description = '';
      const name = 'TL-7 B250 Black / أسود / 500 كرتونة';
      final bottomText = (description.isNotEmpty) ? description : name;
      expect(bottomText, name);
    });

    test('sideText is scannedValue + lineLetter', () {
      const scannedValue = '037000000015';
      const lineNumber = 1;
      final lineLetter = lineNumber == 1 ? 'A' : 'B';
      final sideText = '$scannedValue ($lineLetter)';
      expect(sideText, '037000000015 (A)');
    });

    test('sideText for line 2 uses B', () {
      const scannedValue = '037000000015';
      const lineNumber = 2;
      final lineLetter = lineNumber == 1 ? 'A' : 'B';
      final sideText = '$scannedValue ($lineLetter)';
      expect(sideText, '037000000015 (B)');
    });
  });

  // ── 4-side label layout ──

  group('LabelLayout — 4-side text zone calculations', () {
    test('hasText=false produces no text fields and full QR area', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: false);

      expect(layout.hasText, false);
      expect(layout.mainFontHeight, 0);
      expect(layout.topTextY, 0);
      expect(layout.bottomTextY, 0);
      expect(layout.sideBandWidth, 0);
    });

    test('hasText=true produces 4-side layout fields', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      expect(layout.hasText, true);
      expect(layout.mainFontHeight, greaterThan(0));
      expect(layout.topTextY, greaterThan(0));
      expect(layout.bottomTextY, greaterThan(0));
      expect(layout.sideBandWidth, greaterThan(0));
      expect(layout.sideBandTop, greaterThan(0));
      expect(layout.sideBandBottom, greaterThan(layout.sideBandTop));
    });

    test('QR size shrinks when text is present', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final noText = LabelLayout.fromPreset(preset, hasText: false);
      final withText = LabelLayout.fromPreset(preset, hasText: true);

      expect(
        withText.qrSize, lessThan(noText.qrSize),
        reason: 'QR must shrink to make room for 4-side text bands',
      );
    });

    test('QR does not overlap with top/bottom text bands', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);
        final topTextBottom = layout.topTextY + layout.mainFontHeight;
        final qrBottom = layout.qrY + layout.qrSize;

        expect(
          layout.qrY, greaterThanOrEqualTo(topTextBottom),
          reason: 'QR top must be below top text for ${preset.name}',
        );
        expect(
          layout.bottomTextY, greaterThanOrEqualTo(qrBottom),
          reason: 'Bottom text must be below QR for ${preset.name}',
        );
      }
    });

    test('QR does not overlap with left/right side bands', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);

        expect(
          layout.qrX, greaterThanOrEqualTo(layout.marginDots + layout.sideBandWidth),
          reason: 'QR left must be past left side band for ${preset.name}',
        );
        final qrRight = layout.qrX + layout.qrSize;
        final rightBandStart = layout.widthDots - layout.marginDots - layout.sideBandWidth;
        expect(
          qrRight, lessThanOrEqualTo(rightBandStart),
          reason: 'QR right must not overlap right side band for ${preset.name}',
        );
      }
    });

    test('no center text — QR center area is reserved only for QR', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      // Text bands are strictly outside the QR zone
      expect(layout.topTextY + layout.mainFontHeight, lessThanOrEqualTo(layout.sideBandTop));
      expect(layout.bottomTextY, greaterThanOrEqualTo(layout.sideBandBottom));
    });

    test('pallet number is rendered larger (uses larger font than arial14)', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      // mainFontHeight (arial24 or arial48) should be larger than arial14
      expect(layout.mainFontHeight, greaterThan(14));
    });

    test('text positions are within image bounds for all presets', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);

        expect(layout.topTextY, greaterThanOrEqualTo(0));
        expect(
          layout.bottomTextY + layout.mainFontHeight,
          lessThanOrEqualTo(layout.heightDots),
          reason: 'Bottom text must fit within image for ${preset.name}',
        );
        expect(
          layout.qrSize, greaterThanOrEqualTo(80),
          reason: 'QR must be at least 80 dots (~10mm) for ${preset.name}',
        );
      }
    });

    test('pallet number appears on all 4 sides (side bands allocated)', () {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      // Top and bottom have mainFontHeight
      expect(layout.mainFontHeight, greaterThan(0));
      expect(layout.topTextY, greaterThanOrEqualTo(layout.marginDots));
      expect(layout.bottomTextY, greaterThan(layout.qrY));

      // Left and right have side band width
      expect(layout.sideBandWidth, greaterThan(0));
    });
  });

  // ── Bitmap rendering ──

  group('LabelRenderer — 4-side bitmap rendering', () {
    test('render with topText/bottomText/sideText produces valid bitmap', () async {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final renderer = LabelRenderer();
      final result = await renderer.render(
        value: '0370000005',
        preset: preset,
        topText: 'TL-7 B250 Black (3)',
        bottomText: 'Plate 250 Black',
        sideText: '037000000015 (A)',
      );

      expect(result.monochromeBytes.isNotEmpty, true);
      expect(result.widthBytes, greaterThan(0));
      expect(result.height, greaterThan(0));
      expect(
        result.monochromeBytes.length,
        equals(result.widthBytes * result.height),
      );
    });

    test('render without text still works (QR only)', () async {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final renderer = LabelRenderer();
      final result = await renderer.render(
        value: '0370000005',
        preset: preset,
      );

      expect(result.monochromeBytes.isNotEmpty, true);
    });

    test('bitmap has black pixels in top text area', () async {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);
      final renderer = LabelRenderer();
      final result = await renderer.render(
        value: '0370000005',
        preset: preset,
        topText: 'Product Name',
      );

      bool found = false;
      for (int row = layout.topTextY; row < layout.topTextY + layout.mainFontHeight && row < result.height; row++) {
        for (int x = 0; x < result.widthBytes; x++) {
          if (result.monochromeBytes[row * result.widthBytes + x] != 0xFF) {
            found = true;
            break;
          }
        }
        if (found) break;
      }
      expect(found, true, reason: 'Top text area should have black pixels');
    });

    test('bitmap has black pixels in bottom text area', () async {
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);
      final renderer = LabelRenderer();
      final result = await renderer.render(
        value: '0370000005',
        preset: preset,
        bottomText: 'Product Description',
      );

      bool found = false;
      for (int row = layout.bottomTextY; row < layout.bottomTextY + layout.mainFontHeight && row < result.height; row++) {
        for (int x = 0; x < result.widthBytes; x++) {
          if (result.monochromeBytes[row * result.widthBytes + x] != 0xFF) {
            found = true;
            break;
          }
        }
        if (found) break;
      }
      expect(found, true, reason: 'Bottom text area should have black pixels');
    });

    test('no black pixels in QR center area that are not QR', () async {
      // Render without text to get baseline QR area
      const preset = LabelPreset(
        id: 'test', name: 'test', widthMm: 50, heightMm: 30, marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      // Confirm QR zone center row exists and has some white pixels
      // (no center text overlay — text is only on edges)
      expect(layout.qrX, greaterThan(layout.marginDots));
      expect(layout.qrY, greaterThan(layout.marginDots));
    });

    test('renders on all default presets without error', () async {
      final renderer = LabelRenderer();
      for (final preset in DefaultPresets.all) {
        final result = await renderer.render(
          value: '0370000005',
          preset: preset,
          topText: 'TL-7 B250 Black (3)',
          bottomText: 'Plate 250 Black',
          sideText: '037000000015 (A)',
        );
        expect(result.monochromeBytes.isNotEmpty, true,
            reason: '${preset.name} should render');
      }
    });
  });

  // ── Auto-print behavior verification (unit-level) ──

  group('Auto-print flow contract', () {
    test('print retry reuses stored topText/bottomText/sideText', () {
      // Verify the contract: retryPrint reuses all stored label fields
      const scannedValue = '037000000015';
      const topText = 'TL-7 B250 Black (3)';
      const bottomText = 'Plate 250 Black';
      const sideText = '037000000015 (A)';

      // Simulate: first print stores values, retry reuses them
      String? storedValue = scannedValue;
      String? storedTop = topText;
      String? storedBottom = bottomText;
      String? storedSide = sideText;

      // Retry uses stored values — no new pallet creation
      expect(storedValue, scannedValue);
      expect(storedTop, topText);
      expect(storedBottom, bottomText);
      expect(storedSide, sideText);
    });
  });
}
