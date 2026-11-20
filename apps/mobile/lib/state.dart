import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/account_repository.dart';
import 'data/care_repository.dart';

/// Set in main.dart (Supabase) and in tests (a fake).
final accountRepositoryProvider = Provider<AccountRepository>((ref) => throw UnimplementedError('override in main or tests'));

final signedInProvider = StreamProvider<bool>((ref) async* {
  final repo = ref.watch(accountRepositoryProvider);
  yield repo.isSignedIn;
  yield* repo.signedInChanges();
});

final linkedPatientsProvider = FutureProvider<List<LinkedPatient>>((ref) async {
  if (!await ref.watch(signedInProvider.future)) return const [];
  return ref.watch(accountRepositoryProvider).linkedPatients();
});

/// Which linked person the screens show; null means the account holder (or the only person).
class SelectedPatient extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(signedInProvider); // forget the choice on sign-out
    return null;
  }

  void select(String id) => state = id;
}

final selectedPatientProvider = NotifierProvider<SelectedPatient, String?>(SelectedPatient.new);

final currentPatientProvider = Provider<LinkedPatient?>((ref) {
  final people = ref.watch(linkedPatientsProvider).value ?? const [];
  if (people.isEmpty) return null;
  final chosen = ref.watch(selectedPatientProvider);
  return people.where((p) => p.id == chosen).firstOrNull ?? people.where((p) => p.isSelf).firstOrNull ?? people.first;
});

/// Set in main.dart (Supabase) and in tests (a fake).
final careRepositoryProvider = Provider<CareRepository>((ref) => throw UnimplementedError('override in main or tests'));

/// Upcoming visits, history and plans for the person on screen.
// No automatic retry: a failure shows the retry message at once instead of an endless loading state.
final careSummaryProvider = FutureProvider<CareSummary>(retry: (_, _) => null, (ref) async {
  final person = ref.watch(currentPatientProvider);
  if (person == null) return const CareSummary();
  return ref.watch(careRepositoryProvider).summary(person.id);
});

/// True right after the person chose Sign out, so the sign-in screen can confirm it happened.
class SignedOutNotice extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void clear() => state = false;
}

final signedOutNoticeProvider = NotifierProvider<SignedOutNotice, bool>(SignedOutNotice.new);

/// The group's open clinics, for the clinic picker.
final clinicsProvider = FutureProvider<List<Clinic>>(retry: (_, _) => null, (ref) => ref.watch(accountRepositoryProvider).clinics());

/// Preferred clinic and home address for one linked record.
final patientDetailsProvider = FutureProvider.family<PatientDetails, String>(
  retry: (_, _) => null,
  (ref, patientId) => ref.watch(accountRepositoryProvider).details(patientId),
);
