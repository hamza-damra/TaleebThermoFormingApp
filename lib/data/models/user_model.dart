import '../../core/exceptions/api_exception.dart';
import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    required super.primaryRole,
    required super.roles,
  });

  /// `roles` and `primaryRole` are contractually required on both identity
  /// surfaces. Anything else is a contract error and fails loudly — there is
  /// deliberately no branch that reads a singular `role`, and none may be
  /// added: rebuilding the set from a singular value would hide a backend
  /// regression behind a client that appears to work.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    final Object? rawPrimary = json['primaryRole'];
    final Object? rawRoles = json['roles'];

    if (rawPrimary is! String || rawPrimary.isEmpty || rawRoles is! List) {
      throw ApiException(
        code: 'IDENTITY_CONTRACT_MALFORMED',
        message: 'تعذّر قراءة بيانات الحساب',
      );
    }

    final List<String> roles = rawRoles
        .whereType<String>()
        .toList(growable: false);
    if (roles.isEmpty) {
      throw ApiException(
        code: 'IDENTITY_CONTRACT_MALFORMED',
        message: 'تعذّر قراءة بيانات الحساب',
      );
    }

    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      primaryRole: rawPrimary,
      roles: roles,
    );
  }
}
