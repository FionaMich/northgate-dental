import 'dart:async';

import 'package:dental/data/account_repository.dart';

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

  @override
  Future<void> redeemCode(String code) async {
    if (code.trim().toUpperCase() != validCode) {
      throw const AccountError('This code is not valid or has expired. Ask the front desk for a new one.');
    }
    patients = patientsAfterLinking;
  }
}
