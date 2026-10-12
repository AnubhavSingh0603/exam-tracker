import 'package:flutter/foundation.dart';

/// Non-secret identifiers kept in SQLite. The portal password lives in
/// [SecretStore] (Android Keystore), never in this row.
@immutable
class VaultEntry {
  const VaultEntry({required this.appId, this.registrationId, this.rollNumber, this.notes});

  final String appId;
  final String? registrationId;
  final String? rollNumber;
  final String? notes;

  bool get isEmpty =>
      (registrationId ?? '').isEmpty && (rollNumber ?? '').isEmpty && (notes ?? '').isEmpty;

  Map<String, Object?> toRow(DateTime now) => {
        'app_id': appId,
        'registration_id': registrationId,
        'roll_number': rollNumber,
        'notes': notes,
        'updated_at': now.toUtc().millisecondsSinceEpoch,
      };

  factory VaultEntry.fromRow(Map<String, Object?> r) => VaultEntry(
        appId: r['app_id']! as String,
        registrationId: r['registration_id'] as String?,
        rollNumber: r['roll_number'] as String?,
        notes: r['notes'] as String?,
      );
}

/// What the Application Tracker sheet returns. Blank strings mean "leave unset".
@immutable
class CredentialsInput {
  const CredentialsInput({this.registrationId = '', this.rollNumber = '', this.password = ''});

  final String registrationId;
  final String rollNumber;
  final String password;

  static String? _orNull(String s) => s.trim().isEmpty ? null : s.trim();

  VaultEntry toEntry(String appId) => VaultEntry(
        appId: appId,
        registrationId: _orNull(registrationId),
        rollNumber: _orNull(rollNumber),
      );
}
