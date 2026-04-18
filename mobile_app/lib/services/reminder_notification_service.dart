import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';

import 'api_service.dart';

class ReminderNotificationService {
  ReminderNotificationService._();

  static final ReminderNotificationService instance = ReminderNotificationService._();

  static const String _channelId = 'upcoming_events_channel';
  static const String _channelName = 'Upcoming Events';
  static const String _channelDescription =
      'Notifications for important upcoming events';
  static const String _engagementChannelId = 'memory_engagement_channel';
  static const String _engagementChannelName = 'Memory Assistant Nudges';
  static const String _engagementChannelDescription =
      'Friendly reminders to capture conversations and recall memory';
  static const String _scheduledIdsKey = 'scheduled_notification_ids_v1';
  static const String _lastInteractionKey = 'last_memory_interaction_ms_v1';
  static const int _horizonMinutes = 60 * 24 * 30;
  static const List<int> _leadMinutes = <int>[60, 10, 5, 1];
  static const Duration _monitorInterval = Duration(minutes: 3);
  static const List<int> _engagementIntervalsMinutes = <int>[30, 45, 60];
  static const int _engagementHorizonHours = 24;

  static const List<String> _engagementTitles = <String>[
    'Memory check-in',
    'Quick recall moment',
    'Keep your memory fresh',
  ];

  static const List<String> _engagementBodies = <String>[
    'Talking with someone? Tap to start recording so you can recall this later.',
    'You can save this conversation now and revisit it anytime.',
    'A quick recording now can help you remember details later.',
    'If you are chatting right now, capture it here in Memory Assistant.',
  ];

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _scheduling = false;
  Timer? _monitorTimer;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    tz.initializeTimeZones();
    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (e) {
      debugPrint('Timezone setup fallback: $e');
    }

    await _notifications.initialize(settings);
    await _requestPermissions();

    // Avoid immediate nudge on first launch.
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_lastInteractionKey, prefs.getInt(_lastInteractionKey) ?? DateTime.now().millisecondsSinceEpoch);

    _initialized = true;
  }

  Future<void> markInteraction({String reason = 'user_action'}) async {
    await initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastInteractionKey, DateTime.now().millisecondsSinceEpoch);
    debugPrint('Memory interaction marked: $reason');
    await refreshSchedules();
  }

  Future<void> startMonitoring() async {
    await initialize();
    _monitorTimer?.cancel();
    await refreshSchedules();
    _monitorTimer = Timer.periodic(_monitorInterval, (_) {
      refreshSchedules();
    });
  }

  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  Future<void> refreshSchedules() async {
    if (!_initialized || _scheduling) return;
    _scheduling = true;

    try {
      final result = await ApiService.getUpcoming(minutes: _horizonMinutes);
      final events = (result['events'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map>()
          .toList();

      final oldIds = await _loadScheduledIds();

      final newIds = <int>{};
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (final event in events) {
        final key = _eventKey(event);
        final eventEpochMs = _toInt(event['event_epoch_ms']);
        if (eventEpochMs == null || eventEpochMs <= nowMs) continue;

        final eventTime = DateTime.fromMillisecondsSinceEpoch(eventEpochMs);
        final description =
            (event['description'] ?? 'Upcoming event').toString().trim();

        for (final lead in _leadMinutes) {
          final triggerEpochMs = eventEpochMs - (lead * 60 * 1000);
          if (triggerEpochMs <= nowMs) {
            // For very near events, fire only the immediate lead (1 minute) if missed by a short window.
            if (lead != 1 || nowMs - triggerEpochMs > 60 * 1000) continue;
          }

          final triggerTime = DateTime.fromMillisecondsSinceEpoch(triggerEpochMs);
          final notificationId = _notificationId(key, lead);
            final title = lead == 60
              ? 'Reminder: in 1 hour'
              : 'Reminder: in $lead minute${lead == 1 ? '' : 's'}';
          final body = '$description\n'
              'Event at ${eventTime.toLocal().year.toString().padLeft(4, '0')}-'
              '${eventTime.toLocal().month.toString().padLeft(2, '0')}-'
              '${eventTime.toLocal().day.toString().padLeft(2, '0')} '
              '${eventTime.toLocal().hour.toString().padLeft(2, '0')}:'
              '${eventTime.toLocal().minute.toString().padLeft(2, '0')}';

          await _notifications.zonedSchedule(
            notificationId,
            title,
            body,
            tz.TZDateTime.from(triggerTime, tz.local),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                _channelName,
                channelDescription: _channelDescription,
                importance: Importance.max,
                priority: Priority.high,
                category: AndroidNotificationCategory.reminder,
                visibility: NotificationVisibility.public,
                playSound: true,
                enableVibration: true,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );

          newIds.add(notificationId);
        }
      }

      // Add intelligent engagement nudges so users don't forget to capture memories.
      final engagementIds = await _scheduleEngagementNudges(nowMs: nowMs);
      newIds.addAll(engagementIds);

      // Cancel only stale notifications after new schedules are in place.
      for (final id in oldIds.difference(newIds)) {
        await _notifications.cancel(id);
      }

      await _saveScheduledIds(newIds);
    } catch (e) {
      debugPrint('Reminder schedule refresh failed: $e');
    } finally {
      _scheduling = false;
    }
  }

  Future<Set<int>> _scheduleEngagementNudges({required int nowMs}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastInteractionMs = prefs.getInt(_lastInteractionKey) ?? nowMs;

    final endMs = nowMs + _engagementHorizonHours * 60 * 60 * 1000;
    var cursorMs = lastInteractionMs > nowMs ? lastInteractionMs : nowMs;
    var i = 0;
    final ids = <int>{};

    while (true) {
      final gapMin = _engagementIntervalsMinutes[i % _engagementIntervalsMinutes.length];
      cursorMs += gapMin * 60 * 1000;
      if (cursorMs > endMs) break;

      // Skip triggers that are too close to avoid accidental instant spam.
      if (cursorMs <= nowMs + 2 * 60 * 1000) {
        i++;
        continue;
      }

      final trigger = DateTime.fromMillisecondsSinceEpoch(cursorMs);
      final id = _notificationId('engage|$cursorMs', 0);

      final title = _engagementTitles[i % _engagementTitles.length];
      final body = _engagementBodies[i % _engagementBodies.length];

      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(trigger, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _engagementChannelId,
            _engagementChannelName,
            channelDescription: _engagementChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      ids.add(id);
      i++;
    }

    return ids;
  }

  Future<Map<String, dynamic>> diagnostics() async {
    await initialize();

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final notificationsEnabled =
        await androidPlugin?.areNotificationsEnabled() ?? false;
    final exactAlarmsAllowed =
        await androidPlugin?.canScheduleExactNotifications() ?? false;
    final pending = await _notifications.pendingNotificationRequests();

    return <String, dynamic>{
      'initialized': _initialized,
      'monitoring': _monitorTimer?.isActive ?? false,
      'notifications_enabled': notificationsEnabled,
      'exact_alarms_allowed': exactAlarmsAllowed,
      'pending_count': pending.length,
      'pending_ids': pending.map((p) => p.id).take(30).toList(),
    };
  }

  int _notificationId(String eventKey, int lead) {
    return '$eventKey|$lead'.hashCode & 0x7fffffff;
  }

  Future<void> _requestPermissions() async {
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  Future<Set<int>> _loadScheduledIds() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_scheduledIdsKey) ?? <String>[];
    return saved.map(int.tryParse).whereType<int>().toSet();
  }

  Future<void> _saveScheduledIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scheduledIdsKey,
      ids.take(1000).map((e) => e.toString()).toList(),
    );
  }

  String _eventKey(Map<dynamic, dynamic> event) {
    final id = (event['id'] ?? '').toString();
    if (id.isNotEmpty) return id;

    final type = (event['type'] ?? '').toString();
    final description = (event['description'] ?? '').toString();
    final date = (event['parsed_date'] ?? event['raw_date'] ?? '').toString();
    final time = (event['parsed_time'] ?? event['raw_time'] ?? '').toString();
    return '$type|$description|$date|$time';
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
