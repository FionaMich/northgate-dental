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

  /// Creates a patient account; Supabase emails a 6-digit code to confirm the address.
  Future<void> signUp({required String name, required String email, required String password});

  /// Confirms the sign-up code; success signs the new patient in.
  Future<void> verifySignUpCode(String email, String code);

  Future<void> resendSignUpCode(String email);

  /// Emails a reset code. Says nothing about whether the account exists.
  Future<void> sendPasswordReset(String email);

  /// Checks the reset code; success opens a short session that may only set a new password.
  Future<void> verifyResetCode(String email, String code);

  Future<void> setNewPassword(String password);
}

/// The rules the server enforces (supabase/config.toml), shown to people before they hit them.
abstract final class PasswordRules {
  static const minLength = 10;
  static bool longEnough(String p) => p.length >= minLength;
  static bool hasUpper(String p) => p.contains(RegExp('[A-Z]'));
  static bool hasLower(String p) => p.contains(RegExp('[a-z]'));
  static bool hasDigit(String p) => p.contains(RegExp('[0-9]'));
  static bool ok(String p) => longEnough(p) && hasUpper(p) && hasLower(p) && hasDigit(p);
}

const codeError = 'That code is not right or has expired. Check the latest email, or ask for a new code.';
const tooManyError = 'Too many tries. Please wait a minute, then try again.';

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

  static AccountError _authError(AuthException e, {String fallback = 'That did not work. Please try again.'}) {
    if (e.statusCode == '429' || (e.code ?? '').contains('rate_limit')) return const AccountError(tooManyError);
    if (e.code == 'weak_password') {
      return const AccountError('Choose a stronger password: 10 or more characters with upper and lower case letters and a number.');
    }
    if (e.code == 'otp_expired' || e.code == 'otp_disabled') return const AccountError(codeError);
    return AccountError(fallback);
  }

  @override
  Future<void> signUp({required String name, required String email, required String password}) async {
    try {
      await _db.auth.signUp(email: email.trim(), password: password, data: {'display_name': name.trim()});
    } on AuthException catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<void> verifySignUpCode(String email, String code) async {
    try {
      await _db.auth.verifyOTP(type: OtpType.signup, email: email.trim(), token: code.trim());
    } on AuthException catch (e) {
      throw _authError(e, fallback: codeError);
    }
  }

  @override
  Future<void> resendSignUpCode(String email) async {
    try {
      await _db.auth.resend(type: OtpType.signup, email: email.trim());
    } on AuthException catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      // Only rate limits are reported; anything else looks the same as success so accounts cannot be probed.
      if (e.statusCode == '429' || (e.code ?? '').contains('rate_limit')) {
        throw const AccountError(tooManyError);
      }
    }
  }

  @override
  Future<void> verifyResetCode(String email, String code) async {
    try {
      await _db.auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim());
    } on AuthException catch (e) {
      throw _authError(e, fallback: codeError);
    }
  }

  @override
  Future<void> setNewPassword(String password) async {
    try {
      await _db.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      throw _authError(e);
    }
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
