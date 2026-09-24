import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// The public API has no offline hook; these two are @visibleForTesting.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as google_fonts_base;

/// Lets widget tests render screens that use `GoogleFonts.*` without network.
///
/// google_fonts looks for a pre-bundled `<Family>-<Variant>.ttf` asset before
/// fetching over HTTP (which fails in the test sandbox and surfaces as an
/// uncaught error). This lists fake font assets for every family/variant the
/// app uses and answers them with the bundled Material Icons font bytes — a
/// valid font file, which is all the engine needs for layout.
void installGoogleFontsTestHarness() {
  google_fonts_base.assetManifest = _FakeFontManifest();
  google_fonts_base.clearCache();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler('flutter/assets', (message) {
    final key = utf8.decode(message!.buffer.asUint8List());
    if (key.startsWith(_prefix)) {
      return messenger.delegate.send(
        'flutter/assets',
        ByteData.sublistView(utf8.encode('fonts/MaterialIcons-Regular.otf')),
      );
    }
    return messenger.delegate.send('flutter/assets', message);
  });
}

const _prefix = 'test_fonts/';

class _FakeFontManifest implements AssetManifest {
  static const _families = ['Cairo', 'RobotoMono'];
  static const _variants = [
    'Thin',
    'ExtraLight',
    'Light',
    'Regular',
    'Medium',
    'SemiBold',
    'Bold',
    'ExtraBold',
    'Black',
  ];

  @override
  List<String> listAssets() => [
    for (final family in _families)
      for (final variant in _variants) '$_prefix$family-$variant.ttf',
  ];

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}
