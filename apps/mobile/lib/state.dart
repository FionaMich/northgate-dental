import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/account_repository.dart';
import 'data/assistant_repository.dart';
import 'data/care_repository.dart';
import 'data/shop_repository.dart';
import 'data/voice_engine.dart';

/// Set in main.dart (Supabase) and in tests (a fake).
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => throw UnimplementedError('override in main or tests'),
);

final signedInProvider = StreamProvider<bool>((ref) async* {
  final repo = ref.watch(accountRepositoryProvider);
  yield repo.isSignedIn;
  yield* repo.signedInChanges();
});

/// True once the session has both factors (password and emailed code); false when signed out.
final sessionVerifiedProvider = FutureProvider<bool>(retry: (_, _) => null, (
  ref,
) async {
  if (!await ref.watch(signedInProvider.future)) return false;
  return ref.watch(accountRepositoryProvider).sessionVerified();
});

final linkedPatientsProvider = FutureProvider<List<LinkedPatient>>((ref) async {
  if (!await ref.watch(sessionVerifiedProvider.future)) return const [];
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

final selectedPatientProvider = NotifierProvider<SelectedPatient, String?>(
  SelectedPatient.new,
);

final currentPatientProvider = Provider<LinkedPatient?>((ref) {
  final people = ref.watch(linkedPatientsProvider).value ?? const [];
  if (people.isEmpty) return null;
  final chosen = ref.watch(selectedPatientProvider);
  return people.where((p) => p.id == chosen).firstOrNull ??
      people.where((p) => p.isSelf).firstOrNull ??
      people.first;
});

/// Set in main.dart (Supabase) and in tests (a fake).
final careRepositoryProvider = Provider<CareRepository>(
  (ref) => throw UnimplementedError('override in main or tests'),
);

/// Upcoming visits, history and plans for the person on screen.
// No automatic retry: a failure shows the retry message at once instead of an endless loading state.
final careSummaryProvider = FutureProvider<CareSummary>(retry: (_, _) => null, (
  ref,
) async {
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

final signedOutNoticeProvider = NotifierProvider<SignedOutNotice, bool>(
  SignedOutNotice.new,
);

/// The group's open clinics, for the clinic picker.
final clinicsProvider = FutureProvider<List<Clinic>>(
  retry: (_, _) => null,
  (ref) => ref.watch(accountRepositoryProvider).clinics(),
);

/// Preferred clinic and home address for one linked record.
final patientDetailsProvider = FutureProvider.family<PatientDetails, String>(
  retry: (_, _) => null,
  (ref, patientId) => ref.watch(accountRepositoryProvider).details(patientId),
);

/// True right after a password reset, so the sign-in screen can say the new password is ready.
final passwordChangedNoticeProvider = NotifierProvider<SignedOutNotice, bool>(
  SignedOutNotice.new,
);

// ---------- shop ----------

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => throw UnimplementedError('override in main or tests'),
);
final shopProductsProvider = FutureProvider<List<ShopProduct>>(
  retry: (_, _) => null,
  (ref) => ref.watch(shopRepositoryProvider).products(),
);
final shopOrdersProvider = FutureProvider<List<ShopOrder>>(
  retry: (_, _) => null,
  (ref) => ref.watch(shopRepositoryProvider).orders(),
);

/// The bag: product IDs, quantities and refill choices, in memory only (no patient data), emptied after checkout.
class Bag extends Notifier<Map<String, BagLine>> {
  @override
  Map<String, BagLine> build() => {};

  void add(ShopProduct p, {int quantity = 1, bool refill = false}) {
    final current = state[p.id];
    state = {
      ...state,
      p.id: BagLine(
        product: p,
        quantity: ((current?.quantity ?? 0) + quantity).clamp(1, 10),
        refill: refill || (current?.refill ?? false),
      ),
    };
  }

  void setQuantity(String productId, int quantity) {
    final line = state[productId];
    if (line == null) return;
    state = quantity < 1
        ? ({...state}..remove(productId))
        : {...state, productId: line.copyWith(quantity: quantity.clamp(1, 10))};
  }

  void setRefill(String productId, bool refill) {
    final line = state[productId];
    if (line != null) {
      state = {...state, productId: line.copyWith(refill: refill)};
    }
  }

  void clear() => state = {};
}

final bagProvider = NotifierProvider<Bag, Map<String, BagLine>>(Bag.new);

/// The receptionist assistant's service (main.dart: HTTP with the patient's token; tests: a fake).
final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => throw UnimplementedError('override in main or tests'),
);

/// The phone's speech recogniser and voice for the Nora voice screen (tests: a fake).
final voiceEngineProvider = Provider<VoiceEngine>((ref) => DeviceVoiceEngine());
