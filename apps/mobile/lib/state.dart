import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/account_repository.dart';

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
    ref.watch(signedInProvider);   // forget the choice on sign-out
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
