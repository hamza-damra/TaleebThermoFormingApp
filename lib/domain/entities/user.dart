/// The human identity returned by `/auth/login` and `/auth/pin-login`.
///
/// Wave-8 identity contract: [roles] is the complete assigned role set and the
/// only complete role signal; [primaryRole] is the scoped singular value, for
/// display and logging only. There is no singular `role` — it is not read, not
/// stored, and deliberately has no alias getter.
class User {
  final int id;
  final String name;
  final String email;

  /// The scoped singular identity. Display / logging only — never the input to
  /// an allow-list check.
  final String primaryRole;

  /// The complete assigned role set. Semantically a set: the order carries no
  /// meaning and must never be read as priority.
  final List<String> roles;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.primaryRole,
    required this.roles,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.primaryRole == primaryRole &&
        _sameRoleSet(other.roles, roles);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    email,
    primaryRole,
    // Order-independent, to match the set semantics of [roles].
    Object.hashAllUnordered(roles),
  );

  /// `roles` is a set on the wire, so two users holding the same roles in a
  /// different order are the same user.
  static bool _sameRoleSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.toSet().containsAll(b) && b.toSet().containsAll(a);
  }

  @override
  String toString() =>
      'User(id: $id, name: $name, email: $email, '
      'primaryRole: $primaryRole, roles: $roles)';
}
