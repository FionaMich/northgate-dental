import 'package:supabase_flutter/supabase_flutter.dart';

/// A patient record this sign-in may see: their own, or a child's through proxy access.
class LinkedPatient {
  const LinkedPatient({required this.id, required this.name, required this.isSelf});
  final String id;
  final String name;
  final bool isSelf;

  String get firstName => name.split(' ').first;
}

/// A message safe to show the patient as it is.
class AccountError implements Exception {
  const AccountError(this.message);
  final String message;
}

/// Sign-in and record linking. Screens depend on this, so section 05b can put the offline layer behind it.
abstract class AccountRepository {
  bool get isSignedIn;
  Stream<bool> signedInChanges();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<List<LinkedPatient>> linkedPatients();
  Future<void> redeemCode(String code);
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._db);
  final SupabaseClient _db;

  @override
  bool get isSignedIn => _db.auth.currentSession != null;

  @override
  Stream<bool> signedInChanges() => _db.auth.onAuthStateChange.map((s) => s.session != null);

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException {
      throw const AccountError('That email and password do not match.');
    }
    final profile = await _db.from('profiles').select('role').eq('id', _db.auth.currentUser!.id).maybeSingle();
    if (profile?['role'] != 'patient') {
      await _db.auth.signOut();
      throw const AccountError('Staff accounts sign in to the portal, not the patient app.');
    }
  }

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<List<LinkedPatient>> linkedPatients() async {
    final self = await _db.from('patient_links').select('patient_id').eq('profile_id', _db.auth.currentUser!.id).maybeSingle();
    final rows = await _db.from('patients').select('id, given_name, family_name').order('date_of_birth');
    return [
      for (final r in rows)
        LinkedPatient(id: r['id'] as String, name: '${r['given_name']} ${r['family_name']}', isSelf: r['id'] == self?['patient_id']),
    ];
  }

  @override
  Future<void> redeemCode(String code) async {
    try {
      await _db.rpc('redeem_link_invitation', params: {'code': code});
    } on PostgrestException catch (e) {
      throw AccountError(
        e.code == '22023'
            ? 'This code is not valid or has expired. Ask the front desk for a new one.'
            : 'Linking did not work. Please try again.',
      );
    }
  }
}
