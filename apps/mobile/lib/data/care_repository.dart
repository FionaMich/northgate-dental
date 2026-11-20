import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_repository.dart' show clinicLabel;

class Appointment {
  const Appointment({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.service,
    required this.location,
    required this.status,
  });
  final String id, service, location, status;
  final DateTime startsAt, endsAt;
}

class Procedure {
  const Procedure({required this.service, required this.status, this.tooth});
  final String service, status;
  final String? tooth;
  bool get done => status == 'completed';
}

class Visit {
  const Visit({required this.id, required this.at, required this.kind, required this.location, this.procedures = const []});
  final String id, kind, location;
  final DateTime at;
  final List<Procedure> procedures;
}

class PlanPhase {
  const PlanPhase({required this.sequence, required this.name, this.procedures = const []});
  final int sequence;
  final String name;
  final List<Procedure> procedures;
  bool get done => procedures.isNotEmpty && procedures.every((p) => p.done);
}

class Plan {
  const Plan({required this.id, required this.status, required this.phases});
  final String id, status;
  final List<PlanPhase> phases;
  int get donePhases => phases.where((p) => p.done).length;
  PlanPhase? get current => phases.where((p) => !p.done).firstOrNull;
}

/// Everything the home, records and plan screens show for one person.
class CareSummary {
  const CareSummary({this.upcoming = const [], this.visits = const [], this.plans = const []});
  final List<Appointment> upcoming;
  final List<Visit> visits; // newest first
  final List<Plan> plans;

  /// The plan to feature: one in progress, then accepted, then proposed. Finished and declined plans are history.
  Plan? get activePlan {
    for (final s in const ['in_progress', 'accepted', 'proposed']) {
      final match = plans.where((p) => p.status == s).firstOrNull;
      if (match != null) return match;
    }
    return null;
  }
}

/// A service patients may book themselves at a clinic.
class BookableService {
  const BookableService({required this.id, required this.name, required this.minutes, this.summary = ''});
  final String id, name;
  final int minutes;

  /// One plain sentence about what happens, shown before booking.
  final String summary;
}

/// A free time from `available_slots`, with the dentist the server matched to it.
class Slot {
  const Slot({required this.practitionerId, required this.startsAt, required this.endsAt});
  final String practitionerId;
  final DateTime startsAt, endsAt;
}

/// A booking problem safe to show as it is.
class BookingError implements Exception {
  const BookingError(this.message);
  final String message;
}

const slotTakenError = 'Someone has just taken that time. Please pick another.';
const holdExpiredError = 'Your hold has run out. Please pick a time again.';

/// An insurance card on file; staff check it in the coverage queue.
class Coverage {
  const Coverage({required this.id, required this.payer, required this.memberId, required this.status});
  final String id, payer, memberId, status;
}

/// A dental plan patients can pick when adding a card.
class InsurancePlan {
  const InsurancePlan({required this.id, required this.name, required this.kind});
  final String id, name;

  /// commercial, medicaid (MassHealth) or medicare.
  final String kind;
}

/// A coverage problem safe to show as it is.
class CoverageError implements Exception {
  const CoverageError(this.message);
  final String message;
}

const uploadError = 'We could not save your card. Check your connection and try again.';

/// Reads one patient's care and books visits. Row level security and the booking functions decide what is allowed.
abstract class CareRepository {
  Future<CareSummary> summary(String patientId);
  Future<List<BookableService>> services(String clinicId);

  /// Free times over [days] days from [fromDay], one per start time, soonest first.
  Future<List<Slot>> slots(String clinicId, String serviceId, DateTime fromDay, {int days = 14});

  /// Holds the time for 10 minutes and returns the held appointment's ID. Nothing is booked yet.
  Future<String> hold({required String clinicId, required String serviceId, required Slot slot, required String patientId});

  /// Turns a hold into a booking. Only the server's answer makes it confirmed.
  Future<void> confirm(String appointmentId);
  Future<void> cancel(String appointmentId);

  Future<List<Coverage>> coverages(String patientId);
  Future<List<InsurancePlan>> insurancePlans();

  /// Records the card as waiting for review. Photos are optional; when given, they go to the patient's private folder first.
  Future<void> addCoverage({
    required String patientId,
    String? planId,
    required String payer,
    required String memberId,
    String? group,
    Uint8List? front,
    Uint8List? back,
  });
}

class SupabaseCareRepository implements CareRepository {
  SupabaseCareRepository(this._db);
  final SupabaseClient _db;

  // Services hang off the location's price list (location_services), not the row itself.
  static String? _serviceName(Map<String, dynamic> r) => ((r['location_services'] as Map?)?['services'] as Map?)?['name'] as String?;

  static Procedure _procedure(Map<String, dynamic> r) =>
      Procedure(service: _serviceName(r) ?? 'Procedure', status: r['status'] as String, tooth: r['tooth'] as String?);

  @override
  Future<CareSummary> summary(String patientId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final results = await Future.wait([
      _db
          .from('appointments')
          .select('id, starts_at, ends_at, status, location_services(services(name), locations(name))')
          .eq('patient_id', patientId)
          .inFilter('status', ['booked', 'arrived'])
          .gte('starts_at', now)
          .order('starts_at', ascending: true), // soonest first (the client defaults to descending)
      _db
          .from('encounters')
          .select('id, occurred_at, kind, locations(name), dental_procedures(status, tooth, location_services(services(name)))')
          .eq('patient_id', patientId)
          .order('occurred_at', ascending: false),
      _db
          .from('treatment_plans')
          .select(
            'id, status, created_at, plan_phases(sequence, name, dental_procedures(status, tooth, location_services(services(name))))',
          )
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
    ]);
    String loc(Map<String, dynamic> r) => clinicLabel((r['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental');
    return CareSummary(
      upcoming: [
        for (final r in results[0])
          Appointment(
            id: r['id'] as String,
            startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
            endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
            service: _serviceName(r) ?? 'Appointment',
            location: clinicLabel(((r['location_services'] as Map?)?['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental'),
            status: r['status'] as String,
          ),
      ],
      visits: [
        for (final r in results[1])
          Visit(
            id: r['id'] as String,
            at: DateTime.parse(r['occurred_at'] as String).toLocal(),
            kind: r['kind'] as String,
            location: loc(r),
            procedures: [for (final p in (r['dental_procedures'] as List? ?? const [])) _procedure(p as Map<String, dynamic>)],
          ),
      ],
      plans: [
        for (final r in results[2])
          Plan(
            id: r['id'] as String,
            status: r['status'] as String,
            phases: ([
              for (final ph in (r['plan_phases'] as List? ?? const []))
                PlanPhase(
                  sequence: ph['sequence'] as int,
                  name: ph['name'] as String,
                  procedures: [for (final p in (ph['dental_procedures'] as List? ?? const [])) _procedure(p as Map<String, dynamic>)],
                ),
            ]..sort((a, b) => a.sequence.compareTo(b.sequence))),
          ),
      ],
    );
  }

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Never _bookingError(PostgrestException e) => throw BookingError(switch (e.code) {
    '23P01' => slotTakenError,
    '22023' => holdExpiredError,
    '42501' => 'This visit cannot be booked in the app. Please call the practice.',
    _ => 'Booking did not work. Please try again.',
  });

  @override
  Future<List<BookableService>> services(String clinicId) async {
    final rows = await _db
        .from('location_services')
        .select('services(id, name, summary, duration_minutes, self_bookable, active)')
        .eq('location_id', clinicId)
        .eq('active', true);
    final list = [
      for (final r in rows)
        if (r['services'] case {'self_bookable': true, 'active': true} && final s)
          BookableService(
            id: s['id'] as String,
            name: s['name'] as String,
            minutes: s['duration_minutes'] as int,
            summary: s['summary'] as String? ?? '',
          ),
    ];
    return list..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<Slot>> slots(String clinicId, String serviceId, DateTime fromDay, {int days = 14}) async {
    final rows =
        await _db.rpc('available_slots', params: {'loc': clinicId, 'service': serviceId, 'from_day': _day(fromDay), 'days': days}) as List;
    final byStart = <DateTime, Slot>{};
    for (final r in rows) {
      final start = DateTime.parse(r['starts_at'] as String).toLocal();
      byStart.putIfAbsent(
        start,
        () =>
            Slot(practitionerId: r['practitioner_id'] as String, startsAt: start, endsAt: DateTime.parse(r['ends_at'] as String).toLocal()),
      );
    }
    return byStart.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<String> hold({required String clinicId, required String serviceId, required Slot slot, required String patientId}) async {
    try {
      return await _db.rpc(
        'hold_slot',
        params: {
          'loc': clinicId,
          'service': serviceId,
          'practitioner': slot.practitionerId,
          'starts': slot.startsAt.toUtc().toIso8601String(),
          'patient': patientId,
        },
      ) as String;
    } on PostgrestException catch (e) {
      _bookingError(e);
    }
  }

  @override
  Future<void> confirm(String appointmentId) async {
    try {
      await _db.rpc('confirm_booking', params: {'appointment': appointmentId});
    } on PostgrestException catch (e) {
      _bookingError(e);
    }
  }

  @override
  Future<void> cancel(String appointmentId) async {
    try {
      await _db.rpc('cancel_appointment', params: {'appointment': appointmentId});
    } on PostgrestException catch (e) {
      _bookingError(e);
    }
  }

  @override
  Future<List<Coverage>> coverages(String patientId) async {
    final rows = await _db
        .from('coverages')
        .select('id, payer_name, member_id, status')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        Coverage(
          id: r['id'] as String,
          payer: r['payer_name'] as String,
          memberId: r['member_id'] as String,
          status: r['status'] as String,
        ),
    ];
  }

  @override
  Future<List<InsurancePlan>> insurancePlans() async {
    final rows = await _db.from('insurance_plans').select('id, name, kind').eq('active', true).order('name', ascending: true);
    return [for (final r in rows) InsurancePlan(id: r['id'] as String, name: r['name'] as String, kind: r['kind'] as String)];
  }

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
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final bucket = _db.storage.from('coverage-cards');
    String? upload(String side, Uint8List? bytes) => bytes == null ? null : '$patientId/$stamp-$side.jpg';
    final frontPath = upload('front', front), backPath = upload('back', back);
    try {
      for (final (path, bytes) in [(frontPath, front), (backPath, back)]) {
        if (path != null) await bucket.uploadBinary(path, bytes!, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      }
      await _db.from('coverages').insert({
        'patient_id': patientId,
        'plan_id': planId,
        'payer_name': payer,
        'member_id': memberId,
        'group_number': (group ?? '').isEmpty ? null : group,
        'front_path': frontPath,
        'back_path': backPath,
      });
    } on StorageException {
      throw const CoverageError(uploadError);
    } on PostgrestException {
      throw const CoverageError(uploadError);
    }
  }
}
