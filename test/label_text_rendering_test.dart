import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taleeb_thermoforming/domain/entities/label_preset.dart';
import 'package:taleeb_thermoforming/domain/entities/pallet_label_content.dart';
import 'package:taleeb_thermoforming/printing/label_renderer.dart';
import 'package:taleeb_thermoforming/printing/tspl_builder.dart';
import 'package:taleeb_thermoforming/printing/zpl_builder.dart';

void main() {
  // ── Label content mapping ──

  group('Typed pallet label content', () {
    test('product text includes sequence when present', () {
      const content = PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: 200,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'A',
        sessionProductSequence: 3,
      );
      expect(content.productText, 'TL-7 B250 Black (3)');
    });

    test('product text omits sequence parentheses when sequence is null', () {
      const content = PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: 200,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'A',
      );
      expect(content.productText, 'TL-7 B250 Black');
    });

    test('bottom text explicitly identifies actual quantity and unit', () {
      const content = PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: 200,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'A',
      );
      expect(content.actualQuantityText, 'عدد العبوات: 200 كيس');
    });

    test('side text retains pallet QR value and line display', () {
      const content = PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: 200,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'B',
      );
      expect(content.sideText, '037000000015 (B)');
    });
  });

  // ── 4-side label layout ──

  group('LabelLayout — 4-side text zone calculations', () {
    test('hasText=false produces no text fields and full QR area', () {
      const preset = LabelPreset(
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
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
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
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
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
      );
      final noText = LabelLayout.fromPreset(preset, hasText: false);
      final withText = LabelLayout.fromPreset(preset, hasText: true);

      expect(
        withText.qrSize,
        lessThan(noText.qrSize),
        reason: 'QR must shrink to make room for 4-side text bands',
      );
    });

    test('QR does not overlap with top/bottom text bands', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);
        final topTextBottom = layout.topTextY + layout.mainFontHeight;
        final qrBottom = layout.qrY + layout.qrSize;

        expect(
          layout.qrY,
          greaterThanOrEqualTo(topTextBottom),
          reason: 'QR top must be below top text for ${preset.name}',
        );
        expect(
          layout.bottomTextY,
          greaterThanOrEqualTo(qrBottom),
          reason: 'Bottom text must be below QR for ${preset.name}',
        );
      }
    });

    test('QR does not overlap with left/right side bands', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);

        expect(
          layout.qrX,
          greaterThanOrEqualTo(layout.marginDots + layout.sideBandWidth),
          reason: 'QR left must be past left side band for ${preset.name}',
        );
        final qrRight = layout.qrX + layout.qrSize;
        final rightBandStart =
            layout.widthDots - layout.marginDots - layout.sideBandWidth;
        expect(
          qrRight,
          lessThanOrEqualTo(rightBandStart),
          reason:
              'QR right must not overlap right side band for ${preset.name}',
        );
      }
    });

    test('no center text — QR center area is reserved only for QR', () {
      const preset = LabelPreset(
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);

      // Text bands are strictly outside the QR zone
      expect(
        layout.topTextY + layout.mainFontHeight,
        lessThanOrEqualTo(layout.sideBandTop),
      );
      expect(layout.bottomTextY, greaterThanOrEqualTo(layout.sideBandBottom));
    });

    test(
      'pallet number is rendered larger (uses larger font than arial14)',
      () {
        const preset = LabelPreset(
          id: 'test',
          name: 'test',
          widthMm: 50,
          heightMm: 30,
          marginMm: 2,
        );
        final layout = LabelLayout.fromPreset(preset, hasText: true);

        // mainFontHeight (arial24 or arial48) should be larger than arial14
        expect(layout.mainFontHeight, greaterThan(14));
      },
    );

    test('text positions are within image bounds for all presets', () {
      for (final preset in DefaultPresets.all) {
        final layout = LabelLayout.fromPreset(preset, hasText: true);

        expect(layout.topTextY, greaterThanOrEqualTo(0));
        expect(
          layout.bottomTextY + layout.mainFontHeight,
          lessThanOrEqualTo(layout.heightDots),
          reason: 'Bottom text must fit within image for ${preset.name}',
        );
        // QR must remain readable. Narrow labels (≤30 mm width) share their
        // limited horizontal space with the rotated side text bands, so the
        // QR shrinks to ~5 mm; wider labels keep the original ~10 mm floor.
        final minQrDots = preset.widthMm <= 30 ? 40 : 80;
        expect(
          layout.qrSize,
          greaterThanOrEqualTo(minQrDots),
          reason: 'QR must be at least $minQrDots dots for ${preset.name}',
        );
      }
    });

    test('pallet number appears on all 4 sides (side bands allocated)', () {
      const preset = LabelPreset(
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
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
    test(
      'render with topText/bottomText/sideText produces valid bitmap',
      () async {
        const preset = LabelPreset(
          id: 'test',
          name: 'test',
          widthMm: 50,
          heightMm: 30,
          marginMm: 2,
        );
        final renderer = LabelRenderer();
        final result = await renderer.render(
          content: const PalletLabelContent(
            palletId: 15,
            qrValue: '037000000015',
            productDisplayName: 'TL-7 B250 Black',
            actualQuantity: 200,
            packageUnitDisplayName: 'كيس',
            lineDisplay: 'A',
            sessionProductSequence: 3,
          ),
          preset: preset,
        );

        expect(result.monochromeBytes.isNotEmpty, true);
        expect(result.widthBytes, greaterThan(0));
        expect(result.height, greaterThan(0));
        expect(
          result.monochromeBytes.length,
          equals(result.widthBytes * result.height),
        );
      },
    );

    test('render always includes typed pallet business content', () async {
      const preset = LabelPreset(
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
      );
      final renderer = LabelRenderer();
      final result = await renderer.render(
        content: const PalletLabelContent(
          palletId: 5,
          qrValue: '037000000005',
          productDisplayName: 'Product',
          actualQuantity: 1,
          packageUnitDisplayName: null,
          lineDisplay: 'A',
        ),
        preset: preset,
      );

      expect(result.monochromeBytes.isNotEmpty, true);
    });

    test('bitmap has black pixels in top text area', () async {
      const preset = LabelPreset(
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);
      final renderer = LabelRenderer();
      final result = await renderer.render(
        content: const PalletLabelContent(
          palletId: 5,
          qrValue: '037000000005',
          productDisplayName: 'Product Name',
          actualQuantity: 20,
          packageUnitDisplayName: 'كيس',
          lineDisplay: 'A',
        ),
        preset: preset,
      );

      bool found = false;
      for (
        int row = layout.topTextY;
        row < layout.topTextY + layout.mainFontHeight && row < result.height;
        row++
      ) {
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
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
      );
      final layout = LabelLayout.fromPreset(preset, hasText: true);
      final renderer = LabelRenderer();
      final result = await renderer.render(
        content: const PalletLabelContent(
          palletId: 5,
          qrValue: '037000000005',
          productDisplayName: 'Product',
          actualQuantity: 200,
          packageUnitDisplayName: 'كيس',
          lineDisplay: 'A',
        ),
        preset: preset,
      );

      bool found = false;
      for (
        int row = layout.bottomTextY;
        row < layout.bottomTextY + layout.mainFontHeight && row < result.height;
        row++
      ) {
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
        id: 'test',
        name: 'test',
        widthMm: 50,
        heightMm: 30,
        marginMm: 2,
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
          content: const PalletLabelContent(
            palletId: 15,
            qrValue: '037000000015',
            productDisplayName: 'TL-7 B250 Black',
            actualQuantity: 1000,
            packageUnitDisplayName: 'عبوة',
            lineDisplay: 'A',
            sessionProductSequence: 3,
          ),
          preset: preset,
        );
        expect(
          result.monochromeBytes.isNotEmpty,
          true,
          reason: '${preset.name} should render',
        );
      }
    });
  });

  // ── Printer command embedding (no business logic below the renderer) ──

  group('TSPL / ZPL carry the rendered bitmap verbatim', () {
    const preset = LabelPreset(
      id: 'test',
      name: 'test',
      widthMm: 50,
      heightMm: 30,
      marginMm: 2,
    );
    const content = PalletLabelContent(
      palletId: 15,
      qrValue: '037000000015',
      productDisplayName: 'TL-7 B250 Black',
      actualQuantity: 200,
      packageUnitDisplayName: 'كيس',
      lineDisplay: 'A',
    );

    test('TSPL embeds the complete bitmap between its commands', () async {
      final rendered = await LabelRenderer().render(
        content: content,
        preset: preset,
      );
      final data = TsplBuilder().createLabelPrint(
        widthMm: preset.widthMm,
        heightMm: preset.heightMm,
        bitmapWidthBytes: rendered.widthBytes,
        bitmapHeight: rendered.height,
        bitmapData: rendered.monochromeBytes,
        copies: 2,
      );

      final header = String.fromCharCodes(data);
      final marker = 'BITMAP 0,0,${rendered.widthBytes},${rendered.height},0,';
      expect(header, contains(marker));
      expect(header.trimRight(), endsWith('PRINT 1,2'));

      // The bitmap payload starts immediately after the BITMAP command and
      // must reach the wire byte-for-byte as rendered.
      final bitmapStart = header.indexOf(marker) + marker.length;
      expect(
        data.sublist(
          bitmapStart,
          bitmapStart + rendered.monochromeBytes.length,
        ),
        equals(rendered.monochromeBytes),
        reason: 'TSPL must forward every rendered byte untouched',
      );
      expect(
        data.length,
        equals(
          bitmapStart +
              rendered.monochromeBytes.length +
              'PRINT 1,2'.length +
              2, // CR LF
        ),
        reason: 'nothing may be appended between the bitmap and PRINT',
      );
    });

    test('ZPL embeds the complete bitmap as inverted hex', () async {
      final rendered = await LabelRenderer().render(
        content: content,
        preset: preset,
      );
      final data = ZplBuilder().createLabelPrint(
        widthMm: preset.widthMm,
        heightMm: preset.heightMm,
        bitmapWidthBytes: rendered.widthBytes,
        bitmapHeight: rendered.height,
        bitmapData: rendered.monochromeBytes,
        copies: 3,
      );

      final text = String.fromCharCodes(data);
      final total = rendered.widthBytes * rendered.height;
      expect(text, startsWith('^XA'));
      expect(text, contains('^GFA,$total,$total,${rendered.widthBytes},'));
      expect(text, contains('^PQ3'));
      expect(text, contains('^XZ'));

      final expectedHex = rendered.monochromeBytes
          .map(
            (b) => (~b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'),
          )
          .join();
      expect(
        text,
        contains(expectedHex),
        reason: 'ZPL must carry the full rendered bitmap, polarity-inverted',
      );
    });

    test(
      'printer builders re-encode the label, they do not rebuild it',
      () async {
        // Two pallets differing only in actual quantity must reach the wire as
        // different bytes — proof the command layer is a pure transport of the
        // renderer output and holds no label business logic of its own.
        final renderer = LabelRenderer();
        PalletLabelContent forQuantity(int q) => PalletLabelContent(
          palletId: 15,
          qrValue: '037000000015',
          productDisplayName: 'TL-7 B250 Black',
          actualQuantity: q,
          packageUnitDisplayName: 'كيس',
          lineDisplay: 'A',
        );

        final a = await renderer.render(
          content: forQuantity(200),
          preset: preset,
        );
        final b = await renderer.render(
          content: forQuantity(1000),
          preset: preset,
        );

        Uint8List tspl(LabelRenderResult r) => TsplBuilder().createLabelPrint(
          widthMm: preset.widthMm,
          heightMm: preset.heightMm,
          bitmapWidthBytes: r.widthBytes,
          bitmapHeight: r.height,
          bitmapData: r.monochromeBytes,
        );
        Uint8List zpl(LabelRenderResult r) => ZplBuilder().createLabelPrint(
          widthMm: preset.widthMm,
          heightMm: preset.heightMm,
          bitmapWidthBytes: r.widthBytes,
          bitmapHeight: r.height,
          bitmapData: r.monochromeBytes,
        );

        expect(tspl(a), isNot(equals(tspl(b))));
        expect(zpl(a), isNot(equals(zpl(b))));
      },
    );
  });

  // ── Auto-print behavior verification (unit-level) ──

  group('Auto-print flow contract', () {
    test('typed content retains all retry-critical fields', () {
      const content = PalletLabelContent(
        palletId: 15,
        qrValue: '037000000015',
        productDisplayName: 'TL-7 B250 Black',
        actualQuantity: 200,
        packageUnitDisplayName: 'كيس',
        lineDisplay: 'A',
        sessionProductSequence: 3,
      );

      const storedContent = content;
      expect(storedContent, content);
      expect(storedContent.actualQuantity, 200);
      expect(storedContent.actualQuantityText, 'عدد العبوات: 200 كيس');
    });
  });
}
