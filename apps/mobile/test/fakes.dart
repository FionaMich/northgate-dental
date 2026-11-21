import 'dart:async';
import 'dart:typed_data';

import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:dental/data/aligner_reminders.dart';
import 'package:dental/data/wear_log.dart';

/// In-memory stand-in for Supabase, so widget tests run without a network.
class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({this.password = 'right', this.patients = const [], this.role = 'patient'});

  final String password;
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
    _verified = false; // password only: the emailed code is still needed
    _email = email;
    sent.add('signin:$email');
    _changes.add(true);
  }

  // Second factor, in memory: the code emailed at sign-in is always [emailCode].
  bool _verified = false;
  String? _email;

  @override
  String? get currentEmail => _email;

  @override
  Future<bool> sessionVerified() async => _signedIn && _verified;

  @override
  Future<void> verifySignInCode(String email, String code) async {
    if (code != emailCode) throw const AccountError(codeError);
    _verified = true;
  }

  @override
  Future<void> resendSignInCode(String email) async => sent.add('signin-resend:$email');

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _signedIn = false;
    _verified = false;
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
    _verified = true;
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
  }

  final registered = <String>[];

  @override
  Future<void> registerNewPatient({required String given, required String family, required DateTime birthDate, required String sex}) async {
    if (DateTime(birthDate.year + 18, birthDate.month, birthDate.day).isAfter(DateTime.now())) {
      throw const AccountError('Patients under 18 are registered by a parent or guardian at the practice.');
    }
    registered.add('$given $family ${birthDate.year}-${birthDate.month}-${birthDate.day} $sex');
    patients = [LinkedPatient(id: 'p-new', name: '$given $family', isSelf: true, detailsConfirmed: false)];
  }

  // Date-of-birth linking: Elena's record matches 04/12/1988; five misses lock it.
  int birthDateMisses = 0;

  @override
  Future<LinkOutcome> linkByBirthDate(DateTime birthDate) async {
    if (birthDateMisses >= 5) return LinkOutcome.locked;
    if (birthDate == DateTime(1988, 4, 12)) {
      patients = patientsAfterLinking;
      return LinkOutcome.linked;
    }
    return ++birthDateMisses >= 5 ? LinkOutcome.locked : LinkOutcome.noMatch;
  }

  // Address check: Boston City Hall exists (and comes back in its official form); anything else does not.
  @override
  Future<List<AddressMatch>> verifyAddress({
    required String line1,
    required String city,
    required String state,
    required String zip,
  }) async => line1.toLowerCase().contains('city hall')
      ? const [AddressMatch(line1: '1 City Hall Ave', city: 'Boston', state: 'MA', zip: '02108')]
      : const [];

  // Clinic and address, in memory. Confirmed records already have Back Bay and an address on file.
  final saved = <(String, PatientDetails)>[];
  final _details = <String, PatientDetails>{};

  @override
  Future<List<Clinic>> clinics() async => const [
    Clinic(
      id: 'back-bay',
      name: 'Back Bay',
      address: '1 Example Street, Boston, MA 02116',
      phone: '+16175550110',
      photoKey: 'back-bay',
      hours: [(1, '08:00', '18:00'), (2, '08:00', '18:00'), (3, '08:00', '18:00'), (4, '08:00', '18:00'), (5, '08:00', '16:00')],
    ),
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

/// Care data and booking for widget tests, keyed by patient ID.
class FakeCareRepository implements CareRepository {
  FakeCareRepository([Map<String, CareSummary> byPatient = const {}, this.fail = false]) : byPatient = {...byPatient};
  final Map<String, CareSummary> byPatient;
  final bool fail;
  final calls = <String>[];
  bool takeNextHold = false;
  String? heldWith;
  ({String patient, String service, Slot slot})? _held;

  @override
  Future<CareSummary> summary(String patientId) async {
    if (fail) throw Exception('server refused the query');
    return byPatient[patientId] ?? const CareSummary();
  }

  @override
  Future<Uri> payLink(String appointmentId) async {
    calls.add('pay:$appointmentId');
    return Uri.parse('https://pay.test/pay?t=token');
  }

  @override
  Future<String> documentLink(String path) async {
    calls.add('link:$path');
    return 'https://files.test/$path?token=short';
  }

  @override
  Future<List<BookableService>> services(String clinicId) async => const [
    BookableService(
      id: 'cleaning',
      name: 'Adult cleaning',
      minutes: 60,
      summary: 'A hygienist removes plaque and tartar and polishes your teeth.',
    ),
    BookableService(id: 'exam', name: 'Comprehensive oral exam', minutes: 45),
  ];

  @override
  Future<List<Slot>> slots(String clinicId, String serviceId, DateTime fromDay, {int days = 14}) async {
    final day = DateTime(fromDay.year, fromDay.month, fromDay.day + 1);
    return [
      for (final (h, dr) in [(9, 'dr-1'), (10, 'dr-2'), (14, 'dr-1')])
        Slot(
          practitionerId: dr,
          startsAt: day.add(Duration(hours: h)),
          endsAt: day.add(Duration(hours: h + 1)),
        ),
    ];
  }

  @override
  Future<List<Dentist>> dentists() async => const [
    Dentist(
      id: 'dr-1',
      name: 'Priya Raman, RDH',
      title: 'Dental hygienist',
      focus: 'Cleanings and gum health',
      bio: 'Priya gives thorough, gentle cleanings.',
      clinics: {'back-bay': 'Back Bay'},
      photoKey: 'priya-raman',
    ),
    Dentist(
      id: 'dr-2',
      name: 'Dr Hannah Brooks',
      title: 'General dentist',
      focus: 'Check-ups, fillings and crowns',
      bio: 'Hannah looks after the whole family.',
      clinics: {'back-bay': 'Back Bay'},
      photoKey: 'hannah-brooks',
    ),
  ];

  @override
  Future<String> hold({required String clinicId, required String serviceId, required Slot slot, required String patientId}) async {
    calls.add('hold:$clinicId:$serviceId');
    heldWith = slot.practitionerId;
    if (takeNextHold) throw const BookingError(slotTakenError);
    _held = (patient: patientId, service: serviceId, slot: slot);
    return 'a-1';
  }

  @override
  Future<void> confirm(String appointmentId) async {
    calls.add('confirm:$appointmentId');
    final h = _held!;
    final before = byPatient[h.patient] ?? const CareSummary();
    byPatient[h.patient] = CareSummary(
      upcoming: [
        Appointment(
          id: appointmentId,
          startsAt: h.slot.startsAt,
          endsAt: h.slot.endsAt,
          service: 'Adult cleaning',
          location: 'Back Bay',
          status: 'booked',
        ),
      ],
      visits: before.visits,
      plans: before.plans,
      documents: before.documents,
    );
  }

  bool failUpload = false;
  final _coverages = <String, List<Coverage>>{};

  @override
  Future<List<Coverage>> coverages(String patientId) async => _coverages[patientId] ?? const [];

  @override
  Future<List<InsurancePlan>> insurancePlans() async => const [
    InsurancePlan(id: 'plan-ppo', name: 'Harborline Dental PPO', kind: 'commercial'),
    InsurancePlan(id: 'plan-masshealth', name: 'MassHealth Dental', kind: 'medicaid'),
  ];

  @override
  Future<void> addCoverage({
    required String patientId,
    String? planId,
    required String payer,
    required String memberId,
    String? group,
    Uint8List? front,
    Uint8List? back,
  }) async {
    if (failUpload) throw const CoverageError(uploadError);
    calls.add('coverage:$patientId:${planId ?? 'none'}:$payer:$memberId:front=${front?.length ?? 0}:back=${back?.length ?? 0}');
    _coverages
        .putIfAbsent(patientId, () => [])
        .insert(0, Coverage(id: 'c-${calls.length}', payer: payer, memberId: memberId, status: 'pending_review'));
  }

  @override
  Future<void> cancel(String appointmentId) async {
    calls.add('cancel:$appointmentId');
    byPatient.updateAll(
      (_, c) => CareSummary(
        upcoming: [
          for (final a in c.upcoming)
            if (a.id != appointmentId) a,
        ],
        visits: c.visits,
        plans: c.plans,
      ),
    );
  }
}

/// Wear logs in memory instead of the phone's keystore.
class MemoryWearStore implements WearStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> clearAll() async => values.removeWhere((k, _) => k.startsWith('aligner:'));
}

/// Records reminders instead of scheduling phone notifications.
class FakeAlignerReminders implements AlignerReminders {
  final calls = <String>[];

  @override
  Future<void> takenOut(DateTime at) async => calls.add('out:${at.hour}:${at.minute}');

  @override
  Future<void> backIn() async => calls.add('in');

  @override
  Future<void> clearAll() async => calls.add('clear');

  @override
  Future<void> visitsBooked(List<DateTime> starts) async => calls.add('visits:${starts.length}');
}
