import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A patient record this sign-in may see: their own, or a child's through proxy access.
class LinkedPatient {
  const LinkedPatient({required this.id, required this.name, required this.isSelf, this.detailsConfirmed = true});
  final String id;
  final String name;
  final bool isSelf;

  /// False until the patient has confirmed their clinic and address in the app.
  final bool detailsConfirmed;

  String get firstName => name.split(' ').first;
}

/// One of the group's open clinics, as patients see it.
class Clinic {
  const Clinic({required this.id, required this.name, required this.address});
  final String id, name, address;
}

/// The preferred clinic (the record's home location) and home address.
class PatientDetails {
  const PatientDetails({this.clinicId, this.line1 = '', this.line2 = '', this.city = '', this.state = '', this.zip = ''});
  final String? clinicId;
  final String line1, line2, city, state, zip;

  @override
  bool operator ==(Object other) =>
      other is PatientDetails &&
      other.clinicId == clinicId &&
      other.line1 == line1 &&
      other.line2 == line2 &&
      other.city == city &&
      other.state == state &&
      other.zip == zip;

  @override
  int get hashCode => Object.hash(clinicId, line1, line2, city, state, zip);
}

/// Seed and staff data name clinics "Back Bay (synthetic)"; the patient app shows the plain name (decision 2026-11-19).
String clinicLabel(String name) => name.replaceAll(' (synthetic)', '');

/// What happened when a patient confirmed their date of birth to link a record.
enum LinkOutcome { linked, noMatch, locked }

/// A message safe to show the patient as it is.
class AccountError implements Exception {
  const AccountError(this.message);
  final String message;
}

/// Sign-in and record linking. Screens depend on this, so section 05b can put the offline layer behind it.
abstract class AccountRepository {
  bool get isSignedIn;
  Stream<bool> signedInChanges();

  /// Checks the password, then emails a 6-digit sign-in code. Patient data stays locked until [verifySignInCode].
  Future<void> signIn(String email, String password);

  /// The signed-in email, for the code screen.
  String? get currentEmail;

  /// True once this session has both factors: password and the emailed code.
  Future<bool> sessionVerified();

  Future<void> verifySignInCode(String email, String code);
  Future<void> resendSignInCode(String email);
  Future<void> signOut();
  Future<List<LinkedPatient>> linkedPatients();

  /// Creates a record for a new adult patient and links it to this account.
  Future<void> registerNewPatient({required String given, required String family, required DateTime birthDate, required String sex});

  /// Links the record that uses this sign-in's confirmed email, if the date of birth matches.
  Future<LinkOutcome> linkByBirthDate(DateTime birthDate);

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

  Future<List<Clinic>> clinics();
  Future<PatientDetails> details(String patientId);

  /// Saves the clinic and address for a record this sign-in may see; marks the details confirmed.
  Future<void> saveDetails(String patientId, PatientDetails details);
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

/// Supabase could not deliver the code email (on staging: any address other than the Resend account owner's).
const emailSendError = 'We could not send a code to that email address. Check it is typed correctly, or try another address.';
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
    await _sendSignInCode(email.trim());
  }

  // Records the password step on the server, then asks Supabase Auth to email the code.
  Future<void> _sendSignInCode(String email) async {
    try {
      await _db.rpc('start_sign_in_code');
      await _db.auth.signInWithOtp(email: email, shouldCreateUser: false);
    } on AuthException catch (e) {
      throw _authError(e);
    } on PostgrestException {
      throw const AccountError('Signing in did not work. Please try again.');
    }
  }

  @override
  String? get currentEmail => _db.auth.currentUser?.email;

  @override
  Future<bool> sessionVerified() async => await _db.rpc('session_is_verified') == true;

  @override
  Future<void> verifySignInCode(String email, String code) async {
    try {
      await _db.auth.verifyOTP(type: OtpType.email, email: email.trim(), token: code.trim());
      await _db.rpc('finish_sign_in_code');
    } on AuthException catch (e) {
      throw _authError(e, fallback: codeError);
    } on PostgrestException {
      throw const AccountError('Your password step has expired. Please sign in again.');
    }
  }

  @override
  Future<void> resendSignInCode(String email) => _sendSignInCode(email.trim());

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<List<LinkedPatient>> linkedPatients() async {
    final self = await _db.from('patient_links').select('patient_id').eq('profile_id', _db.auth.currentUser!.id).maybeSingle();
    final rows = await _db
        .from('patients')
        .select('id, given_name, family_name, details_confirmed_at')
        .order('date_of_birth', ascending: true);
    return [
      for (final r in rows)
        LinkedPatient(
          id: r['id'] as String,
          name: '${r['given_name']} ${r['family_name']}',
          isSelf: r['id'] == self?['patient_id'],
          detailsConfirmed: r['details_confirmed_at'] != null,
        ),
    ];
  }

  @visibleForTesting
  static AccountError authErrorForTest(AuthException e) => _authError(e);

  static AccountError _authError(AuthException e, {String fallback = 'That did not work. Please try again.'}) {
    if (e.statusCode == '429' || (e.code ?? '').contains('rate_limit')) return const AccountError(tooManyError);
    if (e.code == 'weak_password') {
      return const AccountError('Choose a stronger password: 10 or more characters with upper and lower case letters and a number.');
    }
    if (e.code == 'otp_expired' || e.code == 'otp_disabled') return const AccountError(codeError);
    if (e.message.toLowerCase().contains('sending') && e.message.toLowerCase().contains('email')) {
      return const AccountError(emailSendError);
    }
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
      await _db.rpc('finish_sign_in_code'); // the sign-up code verifies a new account's first session
    } on AuthException catch (e) {
      throw _authError(e, fallback: codeError);
    } on PostgrestException {
      throw const AccountError('Your account is ready. Please sign in.');
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
  Future<void> registerNewPatient({required String given, required String family, required DateTime birthDate, required String sex}) async {
    final day =
        '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';
    try {
      await _db.rpc('register_new_patient', params: {'given': given, 'family': family, 'birth_date': day, 'sex': sex});
    } on PostgrestException catch (e) {
      final m = e.message.toLowerCase();
      throw AccountError(switch (m) {
        _ when m.contains('already uses this email') =>
          'A record already uses your email. Choose "I am already a patient" and confirm your date of birth.',
        _ when m.contains('under 18') => 'Patients under 18 are registered by a parent or guardian at the practice.',
        _ when m.contains('already has a record') => 'This account already has a record.',
        _ => 'Registering did not work. Please try again.',
      });
    }
  }

  @override
  Future<List<Clinic>> clinics() async {
    final rows = await _db
        .from('locations')
        .select('id, name, address_line, city, state, postal_code')
        .eq('active', true)
        .order('name', ascending: true);
    return [
      for (final r in rows)
        Clinic(
          id: r['id'] as String,
          name: clinicLabel(r['name'] as String),
          address: [
            r['address_line'],
            r['city'],
            '${r['state'] ?? ''} ${r['postal_code'] ?? ''}'.trim(),
          ].where((s) => s != null && '$s'.isNotEmpty).join(', '),
        ),
    ];
  }

  @override
  Future<PatientDetails> details(String patientId) async {
    final r = await _db
        .from('patients')
        .select('home_location_id, address_line1, address_line2, city, state, postal_code')
        .eq('id', patientId)
        .single();
    return PatientDetails(
      clinicId: r['home_location_id'] as String?,
      line1: r['address_line1'] as String? ?? '',
      line2: r['address_line2'] as String? ?? '',
      city: r['city'] as String? ?? '',
      state: r['state'] as String? ?? '',
      zip: r['postal_code'] as String? ?? '',
    );
  }

  @override
  Future<void> saveDetails(String patientId, PatientDetails d) async {
    try {
      await _db.rpc(
        'update_my_details',
        params: {
          'patient': patientId,
          'location': d.clinicId,
          'line1': d.line1,
          'line2': d.line2,
          'town': d.city,
          'region': d.state,
          'zip': d.zip,
        },
      );
    } on PostgrestException catch (e) {
      throw AccountError(switch (e.code) {
        '22023' => 'That clinic is not taking patients right now. Please choose another.',
        '23514' => 'Please check the address: street, city, a 2-letter state and a 5-digit ZIP code.',
        _ => 'Saving did not work. Please try again.',
      });
    }
  }

  @override
  Future<LinkOutcome> linkByBirthDate(DateTime d) async {
    final day = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final result = await _db.rpc('link_by_birth_date', params: {'birth_date': day});
      return switch (result) {
        'linked' => LinkOutcome.linked,
        'locked' => LinkOutcome.locked,
        _ => LinkOutcome.noMatch,
      };
    } on PostgrestException {
      throw const AccountError('Linking did not work. Please try again.');
    }
  }
}
