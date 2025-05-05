import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import '../../models/available_day.dart';
import '../../models/free_day.dart';
import '../../models/schedule.dart';
import '../../models/participant.dart';
import '../../models/role.dart';
import '../utils/supabase_manager.dart';
import 'db_manager_service.dart';
import 'dart:async';

class ScheduleService {
  final supabase = SupabaseManager.client;
  final _box = Hive.box('offline_operations');
  final DbManagerService dbManager = DbManagerService();
  final BehaviorSubject<List<Schedule>> scheduleStreamController =
      BehaviorSubject<List<Schedule>>();
  final _participantStreamController =
      StreamController<List<Participant>>.broadcast();
  final _notificationStreamController = StreamController<dynamic>.broadcast();
  final _permutationRequestStreamController =
      StreamController<dynamic>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Stream<List<Schedule>> get scheduleStream => scheduleStreamController.stream;
  Stream<List<Participant>> get participantStream =>
      _participantStreamController.stream;
  Stream<dynamic> get notificationStream =>
      _notificationStreamController.stream;
  Stream<dynamic> get permutationRequestStream =>
      _permutationRequestStreamController.stream;
  Box get offlineOperationsBox => _box;
  RealtimeChannel? _scheduleChannel;
  RealtimeChannel? _participantChannel;
  RealtimeChannel? _notificationChannel;
  RealtimeChannel? _permutationRequestChannel;
  ScheduleService() {
    _initRealtimeSubscriptions();
    _initConnectivityListener();
    scheduleStreamController.add([]);
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      getUserSchedules(userId).then((schedules) {
        scheduleStreamController.add(schedules);
      });
    }
  }
  Future<bool> isOnline() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return !connectivityResult.contains(ConnectivityResult.none);
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        _initRealtimeSubscriptions();
        syncOfflineOperations();
      } else {
        _scheduleChannel?.unsubscribe();
        _participantChannel?.unsubscribe();
        _notificationChannel?.unsubscribe();
        _permutationRequestChannel?.unsubscribe();
      }
    });
  }

  void _initRealtimeSubscriptions() {
    // Cancel existing subscriptions first
    _scheduleChannel?.unsubscribe();
    _participantChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    _permutationRequestChannel?.unsubscribe();

    // Add error handling and retry logic
    try {
      _scheduleChannel = supabase
          .channel('public:schedules')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'schedules',
            callback: (payload) async {
              final userId = supabase.auth.currentUser?.id;
              if (userId != null) {
                final updatedSchedules = await getUserSchedules(userId);
                scheduleStreamController.add(updatedSchedules);
              }
            },
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('Successfully subscribed to schedules channel');
        } else if (error != null) {
          debugPrint('Error subscribing to schedules channel: $error');
          Future.delayed(
              const Duration(seconds: 5), _initRealtimeSubscriptions);
        }
      });

      _participantChannel = supabase
          .channel('public:participants')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'participants',
            callback: (payload) async {
              final userId = supabase.auth.currentUser?.id;
              if (userId != null) {
                try {
                  final participants = await supabase
                      .from('participants')
                      .select()
                      .eq('user_id', userId);
                  _participantStreamController.add(participants
                      .map((p) => Participant.fromJson(p))
                      .toList());
                } catch (e) {
                  debugPrint('Error fetching participants: $e');
                  _participantStreamController.add([]);
                }
              }
            },
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('Successfully subscribed to participants channel');
        } else if (error != null) {
          debugPrint('Error subscribing to participants channel: $error');
          Future.delayed(
              const Duration(seconds: 5), _initRealtimeSubscriptions);
        }
      });

      _notificationChannel = supabase
          .channel('public:notifications')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              _notificationStreamController.add(payload);
            },
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('Successfully subscribed to notifications channel');
        } else if (error != null) {
          debugPrint('Error subscribing to notifications channel: $error');
          Future.delayed(
              const Duration(seconds: 5), _initRealtimeSubscriptions);
        }
      });

      _permutationRequestChannel = supabase
          .channel('public:permutation_requests')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'permutation_requests',
            callback: (payload) {
              _permutationRequestStreamController.add(payload);
            },
          )
          .subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('Successfully subscribed to permutation requests channel');
        } else if (error != null) {
          debugPrint(
              'Error subscribing to permutation requests channel: $error');
          Future.delayed(
              const Duration(seconds: 5), _initRealtimeSubscriptions);
        }
      });
    } catch (e) {
      debugPrint('Error initializing realtime subscriptions: $e');
      Future.delayed(const Duration(seconds: 5), _initRealtimeSubscriptions);
    }
  }

  Future<void> createSchedule(Schedule schedule) async {
    if (await isOnline()) {
      try {
        await supabase.from('schedules').insert(schedule.toJson());
        for (var participant in schedule.participants) {
          await supabase.from('participants').insert(participant.toJson());
        }
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        await offlineOperationsBox.add({
          'operation': 'create_schedule',
          'data': schedule.toJson(),
        });
        rethrow;
      }
    } else {
      try {
        final db = dbManager.localDatabase;
        await db.insert(
          'schedules',
          {
            'id': schedule.id,
            'name': schedule.name,
            'description': schedule.description,
            'available_days': schedule.availableDays.join(','),
            'duration': schedule.duration,
            'owner_id': schedule.ownerId,
            'participants': jsonEncode(
                schedule.participants.map((p) => p.toJson()).toList()),
            'is_fully_set': schedule.isFullySet ? 1 : 0,
            'created_at': schedule.createdAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        for (var participant in schedule.participants) {
          await db.insert(
            'participants',
            {
              'id': const Uuid().v4(),
              'schedule_id': schedule.id,
              'user_id': participant.userId,
              'roles':
                  jsonEncode(participant.roles.map((r) => r.toJson()).toList()),
              'free_days': jsonEncode(
                  participant.freeDays.map((d) => d.toJson()).toList()),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await offlineOperationsBox.add({
          'operation': 'create_schedule',
          'data': schedule.toJson(),
        });
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        rethrow;
      }
    }
  }

  Future<bool> validateFreeDays(
      String scheduleId, String userId, List<FreeDay> newFreeDays) async {
    try {
      final scheduleData = await supabase
          .from('schedules')
          .select('available_days, duration, start_date')
          .eq('id', scheduleId)
          .single();

      final availableDaysRaw = scheduleData['available_days'] as List<dynamic>;
      final availableDays = availableDaysRaw
          .map((d) => AvailableDay.fromJson(d as Map<String, dynamic>))
          .toList();
      final startDate = DateTime.parse(scheduleData['start_date']);
      final duration = scheduleData['duration'] as String;

      final availableDayNames = availableDays.map((d) => d.day).toList();
      final validDates =
          _calculateScheduleDates(startDate, availableDayNames, duration);

      // First check that all new free days are within the valid date range
      for (var freeDay in newFreeDays) {
        bool dateIsValid = validDates.any((date) =>
            date.year == freeDay.date.year &&
            date.month == freeDay.date.month &&
            date.day == freeDay.date.day);

        if (!dateIsValid) {
          debugPrint('Date not in valid range: ${freeDay.date}');
          return false;
        }

        // Check time constraints
        final dayName = freeDay.day;
        final availableDay = availableDays.firstWhere((d) => d.day == dayName);
        final startMinutes = _timeToMinutes(availableDay.startTime);
        final endMinutes = _timeToMinutes(availableDay.endTime);
        final freeDayStartMinutes = _timeToMinutes(freeDay.startTime);
        final freeDayEndMinutes = _timeToMinutes(freeDay.endTime);

        if (freeDayStartMinutes < startMinutes ||
            freeDayEndMinutes > endMinutes) {
          debugPrint(
              'Time not in valid range: ${freeDay.startTime}-${freeDay.endTime}');
          return false;
        }
      }

      // Get existing taken slots
      final participantsData = await supabase
          .from('participants')
          .select()
          .eq('schedule_id', scheduleId)
          .neq('user_id', userId);

      final participants =
          participantsData.map((p) => Participant.fromJson(p)).toList();
      final takenTimeSlots = participants.expand((p) => p.freeDays).toList();

      // Check for time slot conflicts
      for (var freeDay in newFreeDays) {
        final conflictingSlots = takenTimeSlots.where((takenDay) {
          // Check if dates match
          if (takenDay.date.year != freeDay.date.year ||
              takenDay.date.month != freeDay.date.month ||
              takenDay.date.day != freeDay.date.day) {
            return false;
          }

          // Check for time overlap
          final freeDayStart = _timeToMinutes(freeDay.startTime);
          final freeDayEnd = _timeToMinutes(freeDay.endTime);
          final takenDayStart = _timeToMinutes(takenDay.startTime);
          final takenDayEnd = _timeToMinutes(takenDay.endTime);

          return (freeDayStart < takenDayEnd && freeDayEnd > takenDayStart);
        }).toList();

        if (conflictingSlots.isNotEmpty) {
          debugPrint(
              'Conflict detected for ${freeDay.date}: ${conflictingSlots.length} conflicts');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error validating free days: $e');
      return false;
    }
  }

  Future<void> checkAndUpdateScheduleStatus(String scheduleId) async {
    try {
      final scheduleData = await supabase
          .from('schedules')
          .select()
          .eq('id', scheduleId)
          .single();

      final schedule = Schedule.fromJson(scheduleData);

      final participants = await supabase
          .from('participants')
          .select()
          .eq('schedule_id', scheduleId);

      final assignedDates = participants
          .map((p) =>
              (p['free_days'] as List<dynamic>?)
                  ?.map((d) => FreeDay.fromJson(d as Map<String, dynamic>))
                  .toList() ??
              [])
          .expand((days) => days)
          .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
          .toSet();

      final scheduleDates = _calculateScheduleDates(
        schedule.startDate,
        schedule.availableDays.map((d) => d.day).toList(),
        schedule.duration,
      );

      final isFullySet = scheduleDates.every((date) => assignedDates.any(
          (assigned) =>
              assigned.year == date.year &&
              assigned.month == date.month &&
              assigned.day == date.day));

      if (schedule.isFullySet != isFullySet) {
        if (await isOnline()) {
          await supabase
              .from('schedules')
              .update({'is_fully_set': isFullySet}).eq('id', scheduleId);

          final participantsData = await supabase
              .from('participants')
              .select('user_id')
              .eq('schedule_id', scheduleId);

          final currentUserId = supabase.auth.currentUser?.id;

          for (var participant in participantsData) {
            await supabase.from('notifications').insert({
              'user_id': participant['user_id'],
              'type': 'schedule_status_updated',
              'data': {
                'schedule_id': scheduleId,
                'schedule_name': scheduleData['name'],
                'is_fully_set': isFullySet,
              },
              'creator_id': currentUserId,
            });
          }
        } else {
          final db = dbManager.localDatabase;
          await db.update(
            'schedules',
            {'is_fully_set': isFullySet ? 1 : 0},
            where: 'id = ?',
            whereArgs: [scheduleId],
          );

          await offlineOperationsBox.add({
            'operation': 'update_schedule',
            'data': {'id': scheduleId, 'is_fully_set': isFullySet},
          });
        }

        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> updateFreeDays(
      String scheduleId, String userId, List<FreeDay> freeDays) async {
    if (await isOnline()) {
      try {
        if (!await validateFreeDays(scheduleId, userId, freeDays)) {
          throw Exception('Selected days are not available or already taken');
        }

        await supabase
            .from('participants')
            .update({
              'free_days': freeDays.map((d) => d.toJson()).toList(),
            })
            .eq('schedule_id', scheduleId)
            .eq('user_id', userId);

        await checkAndUpdateScheduleStatus(scheduleId);

        final schedule = await supabase
            .from('schedules')
            .select('name')
            .eq('id', scheduleId)
            .single();

        final participants = await supabase
            .from('participants')
            .select('user_id')
            .eq('schedule_id', scheduleId);

        for (var participant in participants) {
          if (participant['user_id'] != userId) {
            await supabase.from('notifications').insert({
              'user_id': participant['user_id'],
              'type': 'free_days_updated',
              'data': {
                'schedule_id': scheduleId,
                'schedule_name': schedule['name'],
                'updated_by': userId,
              },
              'creator_id': userId,
            });
          }
        }

        final currentUserId = supabase.auth.currentUser?.id;
        if (currentUserId != null) {
          final updatedSchedules = await getUserSchedules(currentUserId);
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        await _box.add({
          'operation': 'update_free_days',
          'data': {
            'schedule_id': scheduleId,
            'user_id': userId,
            'free_days': freeDays.map((d) => d.toJson()).toList(),
          },
        });
        rethrow;
      }
    } else {
      final db = dbManager.localDatabase;
      await db.update(
        'participants',
        {'free_days': jsonEncode(freeDays.map((d) => d.toJson()).toList())},
        where: 'schedule_id = ? AND user_id = ?',
        whereArgs: [scheduleId, userId],
      );

      await _box.add({
        'operation': 'update_free_days',
        'data': {
          'schedule_id': scheduleId,
          'user_id': userId,
          'free_days': freeDays.map((d) => d.toJson()).toList(),
        },
      });

      await _box.add({
        'operation': 'check_schedule_status',
        'data': {'schedule_id': scheduleId},
      });
    }
  }

  Future<void> updateSchedule(Schedule schedule) async {
    if (await isOnline()) {
      try {
        await supabase.from('schedules').update({
          'name': schedule.name,
          'description': schedule.description,
          'available_days': schedule.availableDays,
          'duration': schedule.duration,
          'is_fully_set': schedule.isFullySet,
        }).eq('id', schedule.id);

        await syncParticipants(schedule.id, schedule.participants);

        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        await offlineOperationsBox.add({
          'operation': 'update_schedule',
          'data': {
            'id': schedule.id,
            'name': schedule.name,
            'description': schedule.description,
            'available_days': schedule.availableDays,
            'duration': schedule.duration,
            'is_fully_set': schedule.isFullySet,
          },
        });
        rethrow;
      }
    } else {
      try {
        final db = dbManager.localDatabase;
        await db.update(
          'schedules',
          {
            'id': schedule.id,
            'name': schedule.name,
            'description': schedule.description,
            'available_days': schedule.availableDays.join(','),
            'duration': schedule.duration,
            'owner_id': schedule.ownerId,
            'is_fully_set': schedule.isFullySet ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [schedule.id],
        );

        await offlineOperationsBox.add({
          'operation': 'update_schedule',
          'data': {
            'id': schedule.id,
            'name': schedule.name,
            'description': schedule.description,
            'available_days': schedule.availableDays,
            'duration': schedule.duration,
            'is_fully_set': schedule.isFullySet,
          },
        });

        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        rethrow;
      }
    }
  }

  Future<void> syncParticipants(
      String scheduleId, List<Participant> participants) async {
    if (await isOnline()) {
      try {
        final existingParticipants = await supabase
            .from('participants')
            .select('user_id, free_days')
            .eq('schedule_id', scheduleId);

        final existingFreeDaysMap = {
          for (var p in existingParticipants)
            p['user_id'] as String: (p['free_days'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                []
        };

        final existingUserIds = existingFreeDaysMap.keys.toSet();
        final newUserIds = participants.map((p) => p.userId).toSet();

        final userIdsToRemove = existingUserIds.difference(newUserIds);
        if (userIdsToRemove.isNotEmpty) {
          await supabase
              .from('participants')
              .delete()
              .eq('schedule_id', scheduleId)
              .inFilter('user_id', userIdsToRemove.toList());
        }

        for (var participant in participants) {
          final freeDays = existingUserIds.contains(participant.userId)
              ? participant.freeDays.isEmpty
                  ? existingFreeDaysMap[participant.userId]!
                      .map((d) => FreeDay.fromJson(d))
                      .toList()
                  : participant.freeDays
              : participant.freeDays;

          final updatedParticipant = Participant(
            userId: participant.userId,
            scheduleId: scheduleId,
            roles: participant.roles,
            freeDays: freeDays,
          );

          if (existingUserIds.contains(participant.userId)) {
            await supabase
                .from('participants')
                .update({
                  'roles':
                      updatedParticipant.roles.map((r) => r.toJson()).toList(),
                  'free_days': updatedParticipant.freeDays
                      .map((d) => d.toJson())
                      .toList(),
                })
                .eq('schedule_id', scheduleId)
                .eq('user_id', participant.userId);
          } else {
            await supabase
                .from('participants')
                .insert(updatedParticipant.toJson());
          }
        }

        final schedule = await supabase
            .from('schedules')
            .select('name')
            .eq('id', scheduleId)
            .single();

        final currentUserId = supabase.auth.currentUser?.id;

        for (var participant in participants) {
          if (participant.userId != currentUserId) {
            await supabase.from('notifications').insert({
              'user_id': participant.userId,
              'type': 'participant_updated',
              'data': {
                'schedule_id': scheduleId,
                'schedule_name': schedule['name'],
              },
              'creator_id': currentUserId,
            });
          }
        }

        await checkAndUpdateScheduleStatus(scheduleId);
      } catch (e) {
        await offlineOperationsBox.add({
          'operation': 'sync_participants',
          'data': {
            'schedule_id': scheduleId,
            'participants': participants.map((p) => p.toJson()).toList(),
          },
        });
        rethrow;
      }
    } else {
      try {
        final db = dbManager.localDatabase;

        final existingParticipantsRows = await db.query(
          'participants',
          where: 'schedule_id = ?',
          whereArgs: [scheduleId],
        );

        final existingFreeDaysMap = {
          for (var row in existingParticipantsRows)
            row['user_id'] as String: row['free_days'] as String
        };

        await db.delete(
          'participants',
          where: 'schedule_id = ?',
          whereArgs: [scheduleId],
        );

        for (var participant in participants) {
          final existingFreeDays =
              existingFreeDaysMap[participant.userId] ?? '[]';

          await db.insert(
            'participants',
            {
              'id': const Uuid().v4(),
              'schedule_id': scheduleId,
              'user_id': participant.userId,
              'roles':
                  jsonEncode(participant.roles.map((r) => r.toJson()).toList()),
              'free_days': existingFreeDays,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        await offlineOperationsBox.add({
          'operation': 'sync_participants',
          'data': {
            'schedule_id': scheduleId,
            'participants': participants.map((p) => p.toJson()).toList(),
          },
        });
      } catch (e) {
        rethrow;
      }
    }
  }

  void listenForParticipantChanges(String scheduleId) {
    supabase
        .from('participants')
        .stream(primaryKey: ['id'])
        .eq('schedule_id', scheduleId)
        .listen((data) {
          _participantStreamController.add(
            data.map((json) => Participant.fromJson(json)).toList(),
          );

          checkAndUpdateScheduleStatus(scheduleId);
        });
  }

  List<DateTime> _calculateScheduleDates(
      DateTime startDate, List<String> availableDays, String duration) {
    final daysOfWeek = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    int weeks = 0;

    switch (duration) {
      case '1 week':
        weeks = 1;
        break;
      case '2 weeks':
        weeks = 2;
        break;
      case '1 month':
        weeks = 5;
        break;
      default:
        weeks = int.parse(duration.split(' ')[0]);
    }

    final endDate = startDate.add(Duration(days: weeks * 7));
    final dates = <DateTime>[];

    for (var date = startDate;
        date.isBefore(endDate);
        date = date.add(Duration(days: 1))) {
      final dayName = daysOfWeek[date.weekday - 1];
      if (availableDays.contains(dayName)) {
        dates.add(DateTime(date.year, date.month, date.day));
      }
    }

    return dates;
  }

  int _timeToMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    final parts = timeString.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  List<AvailableDay> _parseAvailableDays(String availableDaysString) {
    try {
      final List<dynamic> availableDaysJson = jsonDecode(availableDaysString);
      return availableDaysJson
          .map((json) => AvailableDay.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return availableDaysString
          .split(',')
          .map((day) => AvailableDay(
              day: day.trim(), startTime: '08:00', endTime: '18:00'))
          .toList();
    }
  }

  Future<bool> deleteSchedule(String scheduleId) async {
    if (await isOnline()) {
      try {
        await supabase
            .from('participants')
            .delete()
            .eq('schedule_id', scheduleId);
        await supabase.from('schedules').delete().eq('id', scheduleId);
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
        return true;
      } catch (e) {
        await offlineOperationsBox.add({
          'operation': 'delete_schedule',
          'data': {
            'id': scheduleId,
          },
        });
        return false;
      }
    } else {
      try {
        final db = dbManager.localDatabase;
        await db.delete(
          'participants',
          where: 'schedule_id = ?',
          whereArgs: [scheduleId],
        );
        await db.delete(
          'schedules',
          where: 'id = ?',
          whereArgs: [scheduleId],
        );
        await offlineOperationsBox.add({
          'operation': 'delete_schedule',
          'data': {
            'id': scheduleId,
          },
        });
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          scheduleStreamController.add(updatedSchedules);
        }
        return true;
      } catch (e) {
        return false;
      }
    }
  }

  Future<List<Schedule>> getUserSchedules(String userId) async {
    if (await isOnline()) {
      try {
        final ownedSchedules =
            await supabase.from('schedules').select().eq('owner_id', userId);

        final participantSchedules = await supabase
            .from('participants')
            .select('schedule_id')
            .eq('user_id', userId);

        final participantScheduleIds = (participantSchedules as List)
            .map((item) => item['schedule_id'].toString())
            .toList();

        final processedScheduleIds =
            ownedSchedules.map((schedule) => schedule['id'] as String).toSet();

        final uniqueParticipantScheduleIds = participantScheduleIds
            .where((id) => !processedScheduleIds.contains(id))
            .toList();

        List participantSchedulesData = [];

        if (uniqueParticipantScheduleIds.isNotEmpty) {
          participantSchedulesData = await supabase
              .from('schedules')
              .select()
              .inFilter('id', uniqueParticipantScheduleIds);
        }

        final allSchedules = [...ownedSchedules, ...participantSchedulesData];
        final schedules =
            allSchedules.map((json) => Schedule.fromJson(json)).toList();

        scheduleStreamController.add(schedules);
        return schedules;
      } catch (e) {
        return [];
      }
    } else {
      try {
        final db = dbManager.localDatabase;
        final ownerSchedules = await db.query(
          'schedules',
          where: 'owner_id = ?',
          whereArgs: [userId],
        );

        final processedScheduleIds =
            ownerSchedules.map((schedule) => schedule['id'] as String).toSet();

        final participantRows = await db.query(
          'participants',
          columns: ['schedule_id'],
          where: 'user_id = ?',
          whereArgs: [userId],
        );

        final uniqueParticipantScheduleIds = participantRows
            .map((row) => row['schedule_id'] as String)
            .where((id) => !processedScheduleIds.contains(id))
            .toList();

        List<Map<String, dynamic>> participantSchedules = [];

        for (var id in uniqueParticipantScheduleIds) {
          final rows = await db.query(
            'schedules',
            where: 'id = ?',
            whereArgs: [id],
          );
          participantSchedules.addAll(rows);
        }

        final allSchedules = [...ownerSchedules, ...participantSchedules];

        return allSchedules.map((row) {
          return Schedule(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String?,
            availableDays: _parseAvailableDays(row['available_days'] as String),
            duration: row['duration'] as String,
            ownerId: row['owner_id'] as String,
            participants: [],
            isFullySet: (row['is_fully_set'] as int) == 1,
            createdAt: DateTime.parse(row['created_at'] as String),
            startDate: DateTime.parse(row['start_date'] as String),
          );
        }).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> syncOfflineOperations() async {
    if (!await isOnline()) return;
    final operations = offlineOperationsBox.values.toList();
    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      if (op['operation'] == 'create_schedule') {
        await supabase.from('schedules').insert(op['data']);
        final participants = (op['data']['participants'] as List<dynamic>)
            .map((p) => Participant.fromJson(p as Map<String, dynamic>))
            .toList();
        for (var participant in participants) {
          await supabase.from('participants').insert(participant.toJson());
        }
      } else if (op['operation'] == 'update_free_days') {
        await supabase
            .from('participants')
            .update({
              'free_days': op['data']['free_days'],
            })
            .eq('schedule_id', op['data']['schedule_id'])
            .eq('user_id', op['data']['user_id']);
      } else if (op['operation'] == 'add_participant') {
        await supabase.from('participants').insert(op['data']);
      } else if (op['operation'] == 'update_schedule') {
        await supabase
            .from('schedules')
            .update(op['data'])
            .eq('id', op['data']['id']);
      } else if (op['operation'] == 'delete_schedule') {
        await supabase
            .from('participants')
            .delete()
            .eq('schedule_id', op['data']['id']);
        await supabase.from('schedules').delete().eq('id', op['data']['id']);
      } else if (op['operation'] == 'sync_participants') {
        final scheduleId = op['data']['schedule_id'];
        final participants = (op['data']['participants'] as List<dynamic>)
            .map((p) => Participant.fromJson(p as Map<String, dynamic>))
            .toList();

        final existingParticipants = await supabase
            .from('participants')
            .select('user_id, free_days')
            .eq('schedule_id', scheduleId);

        final existingFreeDaysMap = {
          for (var p in existingParticipants)
            p['user_id'] as String: (p['free_days'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                []
        };

        final existingUserIds = existingFreeDaysMap.keys.toSet();
        final newUserIds = participants.map((p) => p.userId).toSet();

        final userIdsToRemove = existingUserIds.difference(newUserIds);
        if (userIdsToRemove.isNotEmpty) {
          await supabase
              .from('participants')
              .delete()
              .eq('schedule_id', scheduleId)
              .inFilter('user_id', userIdsToRemove.toList());
        }

        for (var participant in participants) {
          final freeDays = existingUserIds.contains(participant.userId) &&
                  participant.freeDays.isEmpty
              ? existingFreeDaysMap[participant.userId]!
                  .map((d) => FreeDay.fromJson(d))
                  .toList()
              : participant.freeDays;

          if (existingUserIds.contains(participant.userId)) {
            await supabase
                .from('participants')
                .update({
                  'roles': participant.roles.map((r) => r.toJson()).toList(),
                  'free_days': freeDays.map((d) => d.toJson()).toList(),
                })
                .eq('schedule_id', scheduleId)
                .eq('user_id', participant.userId);
          } else {
            await supabase.from('participants').insert({
              'schedule_id': scheduleId,
              'user_id': participant.userId,
              'roles': participant.roles.map((r) => r.toJson()).toList(),
              'free_days': freeDays.map((d) => d.toJson()).toList(),
            });
          }
        }
      }
    }
  }

  Future<void> addParticipant(
      String scheduleId, String userId, List<Role> roles) async {
    final participant = Participant(
      userId: userId,
      scheduleId: scheduleId,
      roles: roles,
      freeDays: [],
    );
    if (await isOnline()) {
      try {
        await supabase.from('participants').insert(participant.toJson());
      } catch (e) {
        await _box.add({
          'operation': 'add_participant',
          'data': participant.toJson(),
        });
        rethrow;
      }
    } else {
      final db = dbManager.localDatabase;
      await db.insert(
        'participants',
        {
          'id': const Uuid().v4(),
          'schedule_id': scheduleId,
          'user_id': userId,
          'roles': jsonEncode(roles.map((r) => r.toJson()).toList()),
          'free_days': '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _box.add({
        'operation': 'add_participant',
        'data': participant.toJson(),
      });
    }
  }

  Stream<List<Participant>> getParticipantStream(String scheduleId) {
    return supabase
        .from('participants')
        .stream(primaryKey: ['id'])
        .eq('schedule_id', scheduleId)
        .map((data) => data.map((json) => Participant.fromJson(json)).toList());
  }

  Stream<Schedule> getScheduleStream(String scheduleId) {
    return supabase
        .from('schedules')
        .stream(primaryKey: ['id'])
        .eq('id', scheduleId)
        .map((data) => Schedule.fromJson(data.first));
  }

  void dispose() {
    _scheduleChannel?.unsubscribe();
    _participantChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    _permutationRequestChannel?.unsubscribe();
    _connectivitySubscription?.cancel();
    scheduleStreamController.close();
    _participantStreamController.close();
    _notificationStreamController.close();
    _permutationRequestStreamController.close();
  }
}
