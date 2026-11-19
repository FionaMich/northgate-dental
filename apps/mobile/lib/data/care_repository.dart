import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Reads one patient's care. Row level security decides what this sign-in may see.
abstract class CareRepository {
  Future<CareSummary> summary(String patientId);
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
          .order('starts_at'),
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
    String loc(Map<String, dynamic> r) => (r['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental';
    return CareSummary(
      upcoming: [
        for (final r in results[0])
          Appointment(
            id: r['id'] as String,
            startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
            endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
            service: _serviceName(r) ?? 'Appointment',
            location: ((r['location_services'] as Map?)?['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental',
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
}
