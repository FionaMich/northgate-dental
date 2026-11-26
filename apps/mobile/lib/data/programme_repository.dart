import 'package:supabase_flutter/supabase_flutter.dart';

/// Continuous care (W24 to W28): the programmes a clinician invited the patient to. The patient joins with recorded
/// consent and can leave at any time; check-ins and shared aligner wear are written by database functions that check
/// the session, so the app never decides what counts as urgent.
class CareProgramme {
  const CareProgramme({
    required this.id,
    required this.programme,
    required this.status,
    required this.endsOn,
    this.todayCheckinId,
    this.todayAnswered = false,
    this.wearTargetHours = 22,
  });

  final String id;
  final String programme; // post_procedure, aligners, recall
  final String status; // invited, active
  final DateTime endsOn;
  final String? todayCheckinId;
  final bool todayAnswered;
  final double wearTargetHours;

  bool get invited => status == 'invited';
}

abstract class ProgrammeRepository {
  Future<List<CareProgramme>> mine();
  Future<void> join(String enrolmentId);
  Future<void> leave(String enrolmentId);

  /// The level the clinic's rules gave the answer: ok, nudge, task or emergency.
  Future<String> answer(
    String checkinId, {
    required int pain,
    required String feeling,
    required List<String> symptoms,
    String? note,
  });
  Future<void> shareWear(String enrolmentId, DateTime day, double hours);
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SupabaseProgrammeRepository implements ProgrammeRepository {
  SupabaseProgrammeRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<CareProgramme>> mine() async {
    final today = _day(DateTime.now());
    final rows = await _db
        .from('care_enrolments')
        .select(
          'id, programme, status, ends_on, wear_target_hours, care_checkins(id, due_on, answered_at)',
        )
        .inFilter('status', ['invited', 'active']);
    return [
      for (final r in rows)
        () {
          final checkins = (r['care_checkins'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final now = checkins.where((c) => c['due_on'] == today).firstOrNull;
          return CareProgramme(
            id: r['id'] as String,
            programme: r['programme'] as String,
            status: r['status'] as String,
            endsOn: DateTime.parse(r['ends_on'] as String),
            todayCheckinId: now?['id'] as String?,
            todayAnswered: now?['answered_at'] != null,
            wearTargetHours: (r['wear_target_hours'] as num?)?.toDouble() ?? 22,
          );
        }(),
    ];
  }

  @override
  Future<void> join(String enrolmentId) =>
      _db.rpc('join_care_programme', params: {'enrolment': enrolmentId});

  @override
  Future<void> leave(String enrolmentId) =>
      _db.rpc('leave_care_programme', params: {'enrolment': enrolmentId});

  @override
  Future<String> answer(
    String checkinId, {
    required int pain,
    required String feeling,
    required List<String> symptoms,
    String? note,
  }) async => await _db.rpc(
    'answer_care_checkin',
    params: {
      'checkin': checkinId,
      'pain': pain,
      'feeling': feeling,
      'symptoms': symptoms,
      'note': note,
    },
  ) as String;

  @override
  Future<void> shareWear(String enrolmentId, DateTime day, double hours) =>
      _db.rpc(
        'record_aligner_wear',
        params: {'enrolment': enrolmentId, 'day': _day(day), 'hours': hours},
      );
}
