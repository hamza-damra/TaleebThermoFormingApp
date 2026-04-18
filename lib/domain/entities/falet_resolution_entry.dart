import 'handover_falet_action.dart';

class FaletResolutionEntry {
  final int faletId;
  final HandoverFaletAction action;

  const FaletResolutionEntry({
    required this.faletId,
    required this.action,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'faletId': faletId,
      'action': action.toJson(),
    };
  }
}
