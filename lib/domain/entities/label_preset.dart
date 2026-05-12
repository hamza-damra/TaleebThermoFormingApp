import 'package:equatable/equatable.dart';

import '../../core/constants/printing_constants.dart';

class LabelPreset extends Equatable {
  final String id;
  final String name;
  final double widthMm;
  final double heightMm;
  final double marginMm;

  const LabelPreset({
    required this.id,
    required this.name,
    required this.widthMm,
    required this.heightMm,
    this.marginMm = PrintingConstants.defaultMarginMm,
  });

  double get printableWidthMm => widthMm - (marginMm * 2);
  double get printableHeightMm => heightMm - (marginMm * 2);

  LabelPreset copyWith({
    String? id,
    String? name,
    double? widthMm,
    double? heightMm,
    double? marginMm,
  }) {
    return LabelPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      widthMm: widthMm ?? this.widthMm,
      heightMm: heightMm ?? this.heightMm,
      marginMm: marginMm ?? this.marginMm,
    );
  }

  @override
  List<Object?> get props => [id, name, widthMm, heightMm, marginMm];
}

class DefaultPresets {
  DefaultPresets._();

  static const LabelPreset preset30x40 = LabelPreset(
    id: 'default_30x40',
    name: '30×40 مم',
    widthMm: 30,
    heightMm: 40,
    marginMm: 2,
  );

  static const LabelPreset preset25x50 = LabelPreset(
    id: 'default_25x50',
    name: '25×50 مم',
    widthMm: 25,
    heightMm: 50,
    marginMm: 2,
  );

  static const LabelPreset preset30x50 = LabelPreset(
    id: 'default_30x50',
    name: '30×50 مم',
    widthMm: 30,
    heightMm: 50,
    marginMm: 2,
  );

  static const LabelPreset preset40x60 = LabelPreset(
    id: 'default_40x60',
    name: '40×60 مم',
    widthMm: 40,
    heightMm: 60,
    marginMm: 3,
  );

  static const LabelPreset preset50x100 = LabelPreset(
    id: 'default_50x100',
    name: '50×100 مم',
    widthMm: 50,
    heightMm: 100,
    marginMm: 4,
  );

  static const LabelPreset preset100x100 = LabelPreset(
    id: 'default_100x100',
    name: '100×100 مم',
    widthMm: 100,
    heightMm: 100,
    marginMm: 4,
  );

  static const List<LabelPreset> all = [
    preset30x40,
    preset25x50,
    preset30x50,
    preset40x60,
    preset50x100,
    preset100x100,
  ];

  static const LabelPreset defaultPreset = preset100x100;

  // Legacy presets kept so that existing printer configs persisted with the
  // previous size catalogue still resolve to a real width/height instead of
  // silently snapping to the new default. Not shown in pickers.
  static const List<LabelPreset> _legacy = [
    LabelPreset(
      id: 'default_40x30',
      name: '40×30 مم',
      widthMm: 40,
      heightMm: 30,
      marginMm: 2,
    ),
    LabelPreset(
      id: 'default_50x25',
      name: '50×25 مم',
      widthMm: 50,
      heightMm: 25,
      marginMm: 2,
    ),
    LabelPreset(
      id: 'default_50x30',
      name: '50×30 مم',
      widthMm: 50,
      heightMm: 30,
      marginMm: 2,
    ),
    LabelPreset(
      id: 'default_60x40',
      name: '60×40 مم',
      widthMm: 60,
      heightMm: 40,
      marginMm: 3,
    ),
    LabelPreset(
      id: 'default_100x50',
      name: '100×50 مم',
      widthMm: 100,
      heightMm: 50,
      marginMm: 4,
    ),
  ];

  static LabelPreset? getById(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    for (final p in _legacy) {
      if (p.id == id) return p;
    }
    return null;
  }
}
