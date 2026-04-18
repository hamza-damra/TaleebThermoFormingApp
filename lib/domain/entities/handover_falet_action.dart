enum HandoverFaletAction {
  carryForward,
  alreadyAccountedInSession;

  String toJson() {
    switch (this) {
      case HandoverFaletAction.carryForward:
        return 'CARRY_FORWARD';
      case HandoverFaletAction.alreadyAccountedInSession:
        return 'ALREADY_ACCOUNTED_IN_SESSION';
    }
  }

  static HandoverFaletAction fromJson(String value) {
    switch (value) {
      case 'CARRY_FORWARD':
        return HandoverFaletAction.carryForward;
      case 'ALREADY_ACCOUNTED_IN_SESSION':
        return HandoverFaletAction.alreadyAccountedInSession;
      default:
        throw ArgumentError('Unknown HandoverFaletAction: $value');
    }
  }
}
