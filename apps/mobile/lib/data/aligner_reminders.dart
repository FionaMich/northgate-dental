import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Phone notifications that nudge the patient to put aligners back in.
/// The text is generic on purpose: notifications show on the lock screen (no health details there).
abstract class AlignerReminders {
  /// Aligners just came out: remind at 30 minutes and again at 2 hours.
  Future<void> takenOut(DateTime at);

  /// Aligners are back in: cancel the pending reminders.
  Future<void> backIn();

  /// Sign-out: remove every pending reminder from this phone.
  Future<void> clearAll();

  /// Booked visits: a reminder the evening before (6pm) and the morning of (8am, or 2 hours before a visit before 9am).
  /// Replaces earlier visit reminders, so a cancelled visit loses its reminders.
  Future<void> visitsBooked(List<DateTime> starts);
}

/// When to remind about a visit, and what to say. Generic text: no treatment on the lock screen.
List<(DateTime, String)> visitReminderTimes(DateTime start, DateTime now) {
  final hhmm = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
  final eveBefore = DateTime(start.year, start.month, start.day - 1, 18);
  final morning = DateTime(start.year, start.month, start.day, 8);
  final dayOf = start.difference(morning) < const Duration(hours: 1) ? start.subtract(const Duration(hours: 2)) : morning;
  return [(eveBefore, 'Dental visit tomorrow at $hhmm'), (dayOf, 'Dental visit today at $hhmm')].where((r) => r.$1.isAfter(now)).toList();
}

class LocalAlignerReminders implements AlignerReminders {
  static const _first = 1001, _second = 1002;
  static const _visitBase = 2000, _visitSlots = 40; // ids 2000..2039: up to 20 visits, two reminders each
  static const reminders = [(Duration(minutes: 30), _first), (Duration(hours: 2), _second)];
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('ic_tooth')));
    // Android 13 and later ask the person once; if they say no, the timer still works without reminders.
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    _ready = true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'aligner-reminders',
      'Aligner reminders',
      channelDescription: 'Reminders to put your aligners back in',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> takenOut(DateTime at) async {
    await _init();
    for (final (after, id) in reminders) {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at.add(after), tz.local),
        notificationDetails: _details,
        // Inexact: may arrive a few minutes late, and needs no special alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Time to put your aligners back in',
        body: after.inHours >= 2 ? 'They have been out for 2 hours.' : 'They have been out for 30 minutes.',
      );
    }
  }

  @override
  Future<void> backIn() async {
    if (!_ready) await _init();
    for (final (_, id) in reminders) {
      await _plugin.cancel(id: id);
    }
  }

  @override
  Future<void> visitsBooked(List<DateTime> starts) async {
    await _init();
    for (var id = _visitBase; id < _visitBase + _visitSlots; id++) {
      await _plugin.cancel(id: id);
    }
    var id = _visitBase;
    for (final start in starts.take(_visitSlots ~/ 2)) {
      for (final (at, text) in visitReminderTimes(start, DateTime.now())) {
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: _visitDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Northgate Dental',
          body: text,
        );
      }
    }
  }

  static const _visitDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'visit-reminders',
      'Visit reminders',
      channelDescription: 'Reminders about your booked dental visits',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  @override
  Future<void> clearAll() async {
    if (!_ready) await _init();
    await _plugin.cancelAll();
  }
}
