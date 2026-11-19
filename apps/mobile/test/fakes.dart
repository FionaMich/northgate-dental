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
  final List<LinkedPatient> patientsAfterLinking = const [
    LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true, detailsConfirmed: false),
  ];
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

  // Clinic and address, in memory. Confirmed records already have Back Bay and an address on file.
  final saved = <(String, PatientDetails)>[];
  final _details = <String, PatientDetails>{};

  @override
  Future<List<Clinic>> clinics() async => const [
    Clinic(id: 'back-bay', name: 'Back Bay', address: '1 Example Street, Boston, MA 02116'),
    Clinic(id: 'cambridge', name: 'Cambridge', address: '2 Example Avenue, Cambridge, MA 02139'),
    Clinic(id: 'quincy', name: 'Quincy', address: '3 Example Road, Quincy, MA 02169'),
  ];

  @override
  Future<PatientDetails> details(String patientId) async =>
      _details[patientId] ??
      (patients.any((p) => p.id == patientId && p.detailsConfirmed)
          ? const PatientDetails(clinicId: 'back-bay', line1: '1 Example Street', city: 'Boston', state: 'MA', zip: '02116')
          : const PatientDetails(clinicId: 'back-bay'));

  @override
  Future<void> saveDetails(String patientId, PatientDetails details) async {
    saved.add((patientId, details));
    _details[patientId] = details;
    patients = [for (final p in patients) p.id == patientId ? LinkedPatient(id: p.id, name: p.name, isSelf: p.isSelf) : p];
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
