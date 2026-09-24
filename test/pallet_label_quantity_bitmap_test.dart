import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/printing/label_renderer.dart';

/// Bitmap-level regression for the original defect: two pallets of the *same*
/// product used to render an identical quantity-like band, because that band
/// was the product description rather than the pallet's own quantity.
///
/// Scope note — `flutter test` renders text with the headless test font, whose
/// glyphs are uniform boxes. Two same-length numbers (200 vs 250) therefore
/// produce byte-identical bitmaps *in the test environment only*; that
/// discrimination is proven at the content boundary in
/// `pallet_label_content_test.dart`, on the exact string this renderer draws.
/// What is provable here — and what the old implementation could never satisfy
/// — is that the quantity band is a function of `PalletLabelContent.
/// actualQuantity` at all, while the QR and side bands stay untouched.
void main() {
  const preset = LabelPreset(
    id: 'test',
    name: 'test',
    widthMm: 50,
    heightMm: 30,
    marginMm: 2,
  );

  final layout = LabelLayout.fromPreset(preset, hasText: true);
  final renderer = LabelRenderer();

  /// Same product, same QR — only the pallet's own quantity changes.
  Future<LabelRenderResult> renderQuantity(int quantity) {
    return renderer.render(
      content: PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: quantity,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'A',
      ),
      preset: preset,
    );
  }

  bool isBlack(LabelRenderResult r, int x, int y) {
    final byte = r.monochromeBytes[y * r.widthBytes + (x >> 3)];
    return (byte & (1 << (7 - (x % 8)))) == 0;
  }

  /// Black-pixel extent inside a rectangle. `width` is 0 when there is no ink.
  ({int count, int minX, int maxX, int width}) ink(
    LabelRenderResult r,
    int xStart,
    int xEnd,
    int yStart,
    int yEnd,
  ) {
    var count = 0;
    var minX = layout.widthDots;
    var maxX = -1;
    for (var y = yStart; y < yEnd && y < r.height; y++) {
      for (var x = xStart; x < xEnd && x < layout.widthDots; x++) {
        if (isBlack(r, x, y)) {
          count++;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    return (
      count: count,
      minX: minX,
      maxX: maxX,
      width: maxX < 0 ? 0 : maxX - minX + 1,
    );
  }

  /// Bytes of a horizontal band, for exact region comparison.
  List<int> band(LabelRenderResult r, int yStart, int yEnd) {
    final out = <int>[];
    for (var y = yStart; y < yEnd && y < r.height; y++) {
      for (var x = 0; x < r.widthBytes; x++) {
        out.add(r.monochromeBytes[y * r.widthBytes + x]);
      }
    }
    return out;
  }

  ({int count, int minX, int maxX, int width}) quantityInk(
    LabelRenderResult r,
  ) => ink(
    r,
    0,
    layout.widthDots,
    layout.bottomTextY,
    layout.bottomTextY + layout.mainFontHeight,
  );

  group('Quantity band is driven by the pallet, not the product', () {
    test(
      'two pallets of the same product render different quantity bands',
      () async {
        // The exact shape of the original bug: same product type, same
        // description, different actual quantities. The old bottom band came
        // from the description and was therefore identical for both.
        final a = await renderQuantity(200);
        final b = await renderQuantity(1000);

        expect(
          quantityInk(a).count,
          greaterThan(0),
          reason: 'pallet A must have a rendered quantity band',
        );
        expect(
          band(
            a,
            layout.bottomTextY,
            layout.bottomTextY + layout.mainFontHeight,
          ),
          isNot(
            equals(
              band(
                b,
                layout.bottomTextY,
                layout.bottomTextY + layout.mainFontHeight,
              ),
            ),
          ),
          reason:
              'quantity band must differ between two pallets of the same '
              'product — this is exactly what the description-based band could '
              'not do',
        );
      },
    );

    test(
      'quantity bands of different magnitudes are pairwise distinct',
      () async {
        // The band is auto-scaled to fill the printable width, so its bounding
        // box saturates; the *content* is what must differ per pallet.
        final bands = <int, List<int>>{};
        for (final quantity in [1, 20, 200, 1000]) {
          final result = await renderQuantity(quantity);
          expect(
            quantityInk(result).count,
            greaterThan(0),
            reason: 'quantity $quantity must render ink in the bottom band',
          );
          bands[quantity] = band(
            result,
            layout.bottomTextY,
            layout.bottomTextY + layout.mainFontHeight,
          );
        }

        final quantities = bands.keys.toList();
        for (var i = 0; i < quantities.length; i++) {
          for (var j = i + 1; j < quantities.length; j++) {
            expect(
              bands[quantities[i]],
              isNot(equals(bands[quantities[j]])),
              reason:
                  'quantity ${quantities[i]} and ${quantities[j]} must not share '
                  'a quantity band',
            );
          }
        }
      },
    );

    test('quantity band ink stays inside its allotted height', () async {
      final result = await renderQuantity(250);
      var minY = layout.heightDots;
      var maxY = -1;
      for (
        var y = layout.bottomTextY;
        y < layout.bottomTextY + layout.mainFontHeight && y < result.height;
        y++
      ) {
        for (var x = 0; x < layout.widthDots; x++) {
          if (isBlack(result, x, y)) {
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
            break;
          }
        }
      }
      expect(maxY, greaterThanOrEqualTo(0), reason: 'band must carry ink');
      expect(maxY, lessThan(layout.heightDots - layout.marginDots));
      expect(
        maxY - minY + 1,
        lessThanOrEqualTo(layout.mainFontHeight),
        reason: 'quantity text must not bleed out of its band',
      );
    });

    test('changing the quantity leaves the QR untouched', () async {
      final a = await renderQuantity(200);
      final b = await renderQuantity(1000);

      for (var y = layout.qrY; y < layout.qrY + layout.qrSize; y++) {
        for (var x = layout.qrX; x < layout.qrX + layout.qrSize; x++) {
          expect(
            isBlack(a, x, y),
            isBlack(b, x, y),
            reason: 'QR pixel ($x,$y) must not depend on the quantity',
          );
        }
      }
    });

    test(
      'changing the quantity leaves the side identifier untouched',
      () async {
        final a = await renderQuantity(200);
        final b = await renderQuantity(1000);

        final sideBand = band(a, layout.sideBandTop, layout.sideBandBottom);
        expect(
          sideBand,
          equals(band(b, layout.sideBandTop, layout.sideBandBottom)),
          reason: 'the rotated pallet-number bands carry no quantity',
        );
      },
    );
  });

  group('Arabic quantity band renders without clipping', () {
    for (final quantity in [1, 20, 200, 250, 1000]) {
      test('quantity $quantity fits inside the printable width', () async {
        final result = await renderQuantity(quantity);
        final measured = quantityInk(result);

        expect(measured.count, greaterThan(0));
        expect(
          measured.minX,
          greaterThanOrEqualTo(layout.marginDots),
          reason: 'quantity band must not start inside the left margin',
        );
        expect(
          measured.maxX,
          lessThan(layout.widthDots - layout.marginDots),
          reason: 'quantity band must not run into the right margin',
        );
      });
    }

    test('every default preset renders an Arabic quantity band', () async {
      for (final p in DefaultPresets.all) {
        final presetLayout = LabelLayout.fromPreset(p, hasText: true);
        final result = await renderer.render(
          content: const PalletLabelContent(
            palletId: 15,
            qrValue: '037000000015',
            productDisplayName: 'TL-7 B250 Black',
            actualQuantity: 250,
            packageUnitDisplayName: 'كيس',
            lineDisplay: 'A',
          ),
          preset: p,
        );

        var found = false;
        for (
          var y = presetLayout.bottomTextY;
          y < presetLayout.bottomTextY + presetLayout.mainFontHeight &&
              y < result.height;
          y++
        ) {
          for (var x = 0; x < presetLayout.widthDots; x++) {
            final byte =
                result.monochromeBytes[y * result.widthBytes + (x >> 3)];
            if ((byte & (1 << (7 - (x % 8)))) == 0) {
              found = true;
              break;
            }
          }
          if (found) break;
        }
        expect(found, isTrue, reason: '${p.name} must render a quantity band');
      }
    });
  });
}
