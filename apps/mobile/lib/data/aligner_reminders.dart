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
}

class LocalAlignerReminders implements AlignerReminders {
  static const _first = 1001, _second = 1002;
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
  Future<void> clearAll() async {
    if (!_ready) await _init();
    await _plugin.cancelAll();
  }
}
