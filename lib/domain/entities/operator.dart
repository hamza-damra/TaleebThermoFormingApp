class Operator {
  final int id;
  final String name;
  final String code;

  const Operator({required this.id, required this.name, required this.code});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Operator && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
