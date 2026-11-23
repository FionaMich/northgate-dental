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
    this.dentist,
    this.dentistPhoto,
    this.clinicId,
    this.serviceId,
    this.dentistId,
    this.priceCents,
  });
  final String id, service, location, status;

  /// The clinic's price for this service, in whole cents; what the patient pays in the app.
  final int? priceCents;
  final String? dentist, dentistPhoto;

  /// For rescheduling: book the same service with the same dentist at the same clinic.
  final String? clinicId, serviceId, dentistId;
  final DateTime startsAt, endsAt;
}

/// A payment for one visit: open (pending) or paid. Expired Checkout attempts are left out.
class Payment {
  const Payment({
    required this.id,
    required this.appointmentId,
    required this.amountCents,
    required this.status,
    required this.service,
    required this.location,
    required this.visitAt,
    this.paidAt,
  });
  final String id, appointmentId, status, service, location;
  final int amountCents;
  final DateTime visitAt;
  final DateTime? paidAt;
  bool get paid => status == 'paid';
}

class PaymentError implements Exception {
  const PaymentError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the pay page lives (n8n's W06 behind the WAF); a build can point elsewhere with --dart-define=LINK_BASE=...
const linkBase = String.fromEnvironment(
  'LINK_BASE',
  defaultValue: 'https://n8n.84-12-126-31.sslip.io/webhook',
);

class Procedure {
  const Procedure({
    required this.service,
    required this.status,
    this.tooth,
    this.surface,
    this.feeCents,
  });
  final String service, status;
  final String? tooth, surface;

  /// Whole cents; null when not shown (plans).
  final int? feeCents;
  bool get done => status == 'completed';
}

/// Something the dentist noted on a tooth at a visit (tooth_conditions).
class Finding {
  const Finding({required this.tooth, required this.condition, this.surface});
  final String tooth, condition;
  final String? surface;
}

class Visit {
  const Visit({
    required this.id,
    required this.at,
    required this.kind,
    required this.location,
    this.dentist,
    this.dentistPhoto,
    this.reason,
    this.procedures = const [],
    this.findings = const [],
  });
  final String id, kind, location;
  final String? dentist, dentistPhoto, reason;
  final DateTime at;
  final List<Procedure> procedures;
  final List<Finding> findings;

  int get totalCents => procedures.fold(0, (sum, p) => sum + (p.feeCents ?? 0));
}

/// A file the practice shared: X-ray images, visit summaries, letters.
class PracticeDocument {
  const PracticeDocument({
    required this.id,
    required this.kind,
    required this.title,
    required this.path,
    required this.contentType,
    required this.sharedAt,
    this.encounterId,
  });
  final String id, kind, title, path, contentType;
  final String? encounterId;
  final DateTime sharedAt;
  bool get isImage => contentType.startsWith('image/');
}

class PlanPhase {
  const PlanPhase({
    required this.sequence,
    required this.name,
    this.procedures = const [],
  });
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
  const CareSummary({
    this.upcoming = const [],
    this.visits = const [],
    this.plans = const [],
    this.documents = const [],
    this.payments = const [],
  });
  final List<Appointment> upcoming;
  final List<Payment> payments; // newest first

  /// The payment for a visit, if one was started.
  Payment? paymentFor(String appointmentId) =>
      payments.where((p) => p.appointmentId == appointmentId).firstOrNull;
  final List<Visit> visits; // newest first
  final List<Plan> plans;
  final List<PracticeDocument> documents; // newest first

  /// The plan to feature: one in progress, then accepted, then proposed. Finished and declined plans are history.
  Plan? get activePlan {
    for (final s in const ['in_progress', 'accepted', 'proposed']) {
      final match = plans.where((p) => p.status == s).firstOrNull;
      if (match != null) return match;
    }
    return null;
  }
}

/// The picture for a patient-facing service group (bundled, graded to the app's teal).
String categoryPhoto(String category) => switch (category) {
  'Check-ups' => 'assets/images/services/checkups.jpg',
  'Cosmetic' => 'assets/images/services/cosmetic.jpg',
  'Orthodontics' => 'assets/images/services/orthodontics.jpg',
  'Surgery and implants' => 'assets/images/services/surgery.jpg',
  _ => 'assets/images/services/fillings.jpg',
};

/// A service patients may book themselves at a clinic.
class BookableService {
  const BookableService({
    required this.id,
    required this.name,
    required this.minutes,
    this.summary = '',
    this.specialty = 'general',
  });
  final String id, name;
  final int minutes;

  /// The specialty code (general, hygiene, orthodontics, ...), used to group services for patients.
  final String specialty;

  /// The patient-facing group for browsing.
  String get category => switch (specialty) {
    'hygiene' || 'paediatric' => 'Check-ups',
    'orthodontics' => 'Orthodontics',
    'oral-surgery' => 'Surgery and implants',
    'endodontics' => 'Fillings and crowns',
    _ when name.toLowerCase().contains('whiten') => 'Cosmetic',
    _ when name.toLowerCase().contains('exam') => 'Check-ups',
    _ when name.toLowerCase().contains('extraction') => 'Surgery and implants',
    _ => 'Fillings and crowns',
  };

  String get photoAsset => categoryPhoto(category);

  /// One plain sentence about what happens, shown before booking.
  final String summary;
}

/// A free time from `available_slots`, with the dentist the server matched to it.
class Slot {
  const Slot({
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
  });
  final String practitionerId;
  final DateTime startsAt, endsAt;
}

/// A dentist or hygienist as patients see them: name, role, a short bio and a photo bundled in the app.
class Dentist {
  const Dentist({
    required this.id,
    required this.name,
    required this.title,
    required this.focus,
    required this.bio,
    required this.clinics,
    this.photoKey,
  });
  final String id, name, title, focus, bio;
  final String? photoKey;

  /// Clinic ID to clinic name, where this person works.
  final Map<String, String> clinics;

  String? get photoAsset =>
      photoKey == null ? null : 'assets/images/team/$photoKey.jpg';
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
  const Coverage({
    required this.id,
    required this.payer,
    required this.memberId,
    required this.status,
  });
  final String id, payer, memberId, status;
}

/// A dental plan patients can pick when adding a card.
class InsurancePlan {
  const InsurancePlan({
    required this.id,
    required this.name,
    required this.kind,
  });
  final String id, name;

  /// commercial, medicaid (MassHealth) or medicare.
  final String kind;
}

/// A coverage problem safe to show as it is.
class CoverageError implements Exception {
  const CoverageError(this.message);
  final String message;
}

const uploadError =
    'We could not save your card. Check your connection and try again.';

/// Reads one patient's care and books visits. Row level security and the booking functions decide what is allowed.
abstract class CareRepository {
  Future<CareSummary> summary(String patientId);

  /// A link to one shared document that works for a few minutes only.
  Future<String> documentLink(String path);
  Future<List<BookableService>> services(String clinicId);

  /// The active team, for choosing a dentist.
  Future<List<Dentist>> dentists();

  /// Free times over [days] days from [fromDay], one per dentist and start time, soonest first.
  Future<List<Slot>> slots(
    String clinicId,
    String serviceId,
    DateTime fromDay, {
    int days = 14,
  });

  /// Holds the time for 10 minutes and returns the held appointment's ID. Nothing is booked yet.
  Future<String> hold({
    required String clinicId,
    required String serviceId,
    required Slot slot,
    required String patientId,
  });

  /// Turns a hold into a booking. Only the server's answer makes it confirmed.
  Future<void> confirm(String appointmentId);
  Future<void> cancel(String appointmentId);

  /// A single-use link to Stripe Checkout for one of the patient's own visits, at the price-list amount.
  Future<Uri> payLink(String appointmentId);

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
  static String? _serviceName(Map<String, dynamic> r) =>
      ((r['location_services'] as Map?)?['services'] as Map?)?['name']
          as String?;

  static Procedure _procedure(Map<String, dynamic> r) => Procedure(
    service: _serviceName(r) ?? 'Procedure',
    status: r['status'] as String,
    tooth: r['tooth'] as String?,
    surface: r['surface'] as String?,
    feeCents: r['fee_cents'] as int?,
  );

  @override
  Future<CareSummary> summary(String patientId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final results = await Future.wait([
      _db
          .from('appointments')
          .select(
            'id, starts_at, ends_at, status, location_id, service_id, practitioner_id, '
            'location_services(price_cents, services(name), locations(name)), practitioners(public_name, photo_key)',
          )
          .eq('patient_id', patientId)
          .inFilter('status', ['booked', 'arrived'])
          .gte('starts_at', now)
          .order(
            'starts_at',
            ascending: true,
          ), // soonest first (the client defaults to descending)
      _db
          .from('encounters')
          .select(
            'id, occurred_at, kind, reason, locations(name), practitioners(public_name, photo_key), '
            'dental_procedures(status, tooth, surface, fee_cents, location_services(services(name))), tooth_conditions(tooth, surface, condition)',
          )
          .eq('patient_id', patientId)
          .order('occurred_at', ascending: false),
      _db
          .from('treatment_plans')
          .select(
            'id, status, created_at, plan_phases(sequence, name, dental_procedures(status, tooth, location_services(services(name))))',
          )
          .eq('patient_id', patientId)
          .order('created_at', ascending: false),
      _db
          .from('patient_documents')
          .select(
            'id, encounter_id, kind, title, file_path, content_type, shared_at',
          )
          .eq('patient_id', patientId)
          .order('shared_at', ascending: false),
      _db
          .from('payments')
          .select(
            'id, appointment_id, amount_cents, status, paid_at, appointments(starts_at, location_services(services(name), locations(name)))',
          )
          .eq('patient_id', patientId)
          .neq('status', 'expired')
          .order('created_at', ascending: false),
    ]);
    String loc(Map<String, dynamic> r) => clinicLabel(
      (r['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental',
    );
    return CareSummary(
      upcoming: [
        for (final r in results[0])
          Appointment(
            id: r['id'] as String,
            startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
            endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
            service: _serviceName(r) ?? 'Appointment',
            location: clinicLabel(
              ((r['location_services'] as Map?)?['locations'] as Map?)?['name']
                      as String? ??
                  'Northgate Dental',
            ),
            status: r['status'] as String,
            dentist: (r['practitioners'] as Map?)?['public_name'] as String?,
            dentistPhoto: (r['practitioners'] as Map?)?['photo_key'] as String?,
            clinicId: r['location_id'] as String?,
            serviceId: r['service_id'] as String?,
            dentistId: r['practitioner_id'] as String?,
            priceCents:
                (r['location_services'] as Map?)?['price_cents'] as int?,
          ),
      ],
      payments: [
        for (final r in results[4])
          Payment(
            id: r['id'] as String,
            appointmentId: r['appointment_id'] as String,
            amountCents: r['amount_cents'] as int,
            status: r['status'] as String,
            paidAt: r['paid_at'] == null
                ? null
                : DateTime.parse(r['paid_at'] as String).toLocal(),
            visitAt: DateTime.parse(
              (r['appointments'] as Map)['starts_at'] as String,
            ).toLocal(),
            service:
                _serviceName(r['appointments'] as Map<String, dynamic>) ??
                'Visit',
            location: clinicLabel(
              (((r['appointments'] as Map)['location_services']
                              as Map?)?['locations']
                          as Map?)?['name']
                      as String? ??
                  'Northgate Dental',
            ),
          ),
      ],
      visits: [
        for (final r in results[1])
          Visit(
            id: r['id'] as String,
            at: DateTime.parse(r['occurred_at'] as String).toLocal(),
            kind: r['kind'] as String,
            location: loc(r),
            dentist: (r['practitioners'] as Map?)?['public_name'] as String?,
            dentistPhoto: (r['practitioners'] as Map?)?['photo_key'] as String?,
            reason: r['reason'] as String?,
            procedures: [
              for (final p in (r['dental_procedures'] as List? ?? const []))
                _procedure(p as Map<String, dynamic>),
            ],
            findings: [
              for (final f in (r['tooth_conditions'] as List? ?? const []))
                Finding(
                  tooth: f['tooth'] as String,
                  surface: f['surface'] as String?,
                  condition: f['condition'] as String,
                ),
            ],
          ),
      ],
      documents: [
        for (final r in results[3])
          PracticeDocument(
            id: r['id'] as String,
            encounterId: r['encounter_id'] as String?,
            kind: r['kind'] as String,
            title: r['title'] as String,
            path: r['file_path'] as String,
            contentType: r['content_type'] as String,
            sharedAt: DateTime.parse(r['shared_at'] as String).toLocal(),
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
                  procedures: [
                    for (final p
                        in (ph['dental_procedures'] as List? ?? const []))
                      _procedure(p as Map<String, dynamic>),
                  ],
                ),
            ]..sort((a, b) => a.sequence.compareTo(b.sequence))),
          ),
      ],
    );
  }

  @override
  Future<String> documentLink(String path) async {
    try {
      return await _db.storage
          .from('patient-documents')
          .createSignedUrl(path, 300); // 5 minutes
    } on StorageException {
      throw const CoverageError(
        'We could not open that document. Check your connection and try again.',
      );
    }
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Never _bookingError(PostgrestException e) =>
      throw BookingError(switch (e.code) {
        '23P01' => slotTakenError,
        '22023' => holdExpiredError,
        '42501' =>
          'This visit cannot be booked in the app. Please call the practice.',
        _ => 'Booking did not work. Please try again.',
      });

  @override
  Future<List<BookableService>> services(String clinicId) async {
    final rows = await _db
        .from('location_services')
        .select(
          'services(id, name, summary, duration_minutes, self_bookable, active, specialties(code))',
        )
        .eq('location_id', clinicId)
        .eq('active', true);
    final list = [
      for (final r in rows)
        if (r['services']
            case {'self_bookable': true, 'active': true} && final s)
          BookableService(
            id: s['id'] as String,
            name: s['name'] as String,
            minutes: s['duration_minutes'] as int,
            summary: s['summary'] as String? ?? '',
            specialty:
                (s['specialties'] as Map?)?['code'] as String? ?? 'general',
          ),
    ];
    return list..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<Slot>> slots(
    String clinicId,
    String serviceId,
    DateTime fromDay, {
    int days = 14,
  }) async {
    final rows = await _db.rpc(
      'available_slots',
      params: {
        'loc': clinicId,
        'service': serviceId,
        'from_day': _day(fromDay),
        'days': days,
      },
    ) as List;
    final seen = <(String, DateTime)>{};
    return [
      for (final r in rows)
        if (seen.add((
          r['practitioner_id'] as String,
          DateTime.parse(r['starts_at'] as String),
        )))
          Slot(
            practitionerId: r['practitioner_id'] as String,
            startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
            endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
          ),
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  @override
  Future<List<Dentist>> dentists() async {
    final rows = await _db
        .from('practitioners')
        .select(
          'id, public_name, title, focus, bio, photo_key, practitioner_roles(locations(id, name))',
        )
        .eq('active', true)
        .order('public_name', ascending: true);
    return [
      for (final r in rows)
        if (r['public_name'] != null)
          Dentist(
            id: r['id'] as String,
            name: r['public_name'] as String,
            title: r['title'] as String? ?? '',
            focus: r['focus'] as String? ?? '',
            bio: r['bio'] as String? ?? '',
            photoKey: r['photo_key'] as String?,
            clinics: {
              for (final role in (r['practitioner_roles'] as List? ?? const []))
                if ((role as Map)['locations'] case {
                  'id': final String id,
                  'name': final String name,
                })
                  id: clinicLabel(name),
            },
          ),
    ];
  }

  @override
  Future<String> hold({
    required String clinicId,
    required String serviceId,
    required Slot slot,
    required String patientId,
  }) async {
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
      await _db.rpc(
        'cancel_appointment',
        params: {'appointment': appointmentId},
      );
    } on PostgrestException catch (e) {
      _bookingError(e);
    }
  }

  @override
  Future<Uri> payLink(String appointmentId) async {
    try {
      final token = await _db.rpc(
        'start_my_payment',
        params: {'appointment': appointmentId},
      ) as String;
      return Uri.parse('$linkBase/pay?t=$token');
    } on PostgrestException catch (e) {
      if (e.message.contains('already paid')) {
        throw const PaymentError('This visit is already paid.');
      }
      throw const PaymentError(
        'We could not start the payment. Please try again, or pay at the clinic.',
      );
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
    final rows = await _db
        .from('insurance_plans')
        .select('id, name, kind')
        .eq('active', true)
        .order('name', ascending: true);
    return [
      for (final r in rows)
        InsurancePlan(
          id: r['id'] as String,
          name: r['name'] as String,
          kind: r['kind'] as String,
        ),
    ];
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
    String? upload(String side, Uint8List? bytes) =>
        bytes == null ? null : '$patientId/$stamp-$side.jpg';
    final frontPath = upload('front', front), backPath = upload('back', back);
    try {
      for (final (path, bytes) in [(frontPath, front), (backPath, back)]) {
        if (path != null) {
          await bucket.uploadBinary(
            path,
            bytes!,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
        }
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
