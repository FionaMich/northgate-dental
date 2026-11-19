import 'dart:async';

import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';

/// In-memory stand-in for Supabase, so widget tests run without a network.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.password = 'right', this.patients = const [], this.validCode = 'ABCD1234EFGH5678', this.role = 'patient'});

  final String password;
  final String validCode;
  final String role;
  List<LinkedPatient> patients;
  final List<LinkedPatient> patientsAfterLinking = const [LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true)];
  final _changes = StreamController<bool>.broadcast();
  bool _signedIn = false;
  int signOutCalls = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  Stream<bool> signedInChanges() => _changes.stream;

  @override
  Future<void> signIn(String email, String password) async {
    if (password != this.password) throw const AccountError('That email and password do not match.');
    if (role != 'patient') throw const AccountError('Staff accounts sign in to the portal, not the patient app.');
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _signedIn = false;
    _changes.add(false);
  }

  @override
  Future<List<LinkedPatient>> linkedPatients() async => patients;

  // Sign-up and reset, in memory. The code emailed is always [emailCode].
  final emailCode = '123456';
  final sent = <String>[];
  String? newPassword;
  bool rateLimited = false;

  @override
  Future<void> signUp({required String name, required String email, required String password}) async {
    if (rateLimited) throw const AccountError(tooManyError);
    sent.add('signup:$email');
  }

  @override
  Future<void> verifySignUpCode(String email, String code) async {
    if (code != emailCode) throw const AccountError(codeError);
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> resendSignUpCode(String email) async => sent.add('resend:$email');

  @override
  Future<void> sendPasswordReset(String email) async {
    if (rateLimited) throw const AccountError(tooManyError);
    sent.add('reset:$email');
  }

  @override
  Future<void> verifyResetCode(String email, String code) async {
    if (code != emailCode) throw const AccountError(codeError);
  }

  @override
  Future<void> setNewPassword(String password) async {
    newPassword = password;
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> redeemCode(String code) async {
    if (code.trim().toUpperCase() != validCode) {
      throw const AccountError('This code is not valid or has expired. Ask the front desk for a new one.');
    }
    patients = patientsAfterLinking;
  }
}

/// Care data for widget tests, keyed by patient ID.
class FakeCareRepository implements CareRepository {
  FakeCareRepository([this.byPatient = const {}, this.fail = false]);
  final Map<String, CareSummary> byPatient;
  final bool fail;

  @override
  Future<CareSummary> summary(String patientId) async {
    if (fail) throw Exception('server refused the query');
    return byPatient[patientId] ?? const CareSummary();
  }
}
