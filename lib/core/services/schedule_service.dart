import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import '../../models/schedule.dart';
import '../../models/participant.dart';
import '../../models/free_day.dart';
import '../utils/firebase_manager.dart';
import 'offline_sync_service.dart';

class ScheduleService {
  final _offlineSync = OfflineSyncService();

  final _schedulesCollection =
      FirebaseManager.firestore.collection('schedules');
  final _participantsCollection =
      FirebaseManager.firestore.collection('participants');
  final _notificationsCollection =
      FirebaseManager.firestore.collection('notifications');

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  ScheduleService() {
    _initConnectivityListener();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (!results.contains(ConnectivityResult.none)) {
        _offlineSync.syncPendingOperations();
      }
    });
  }

  Future<bool> _isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  Future<void> createSchedule(Schedule schedule) async {
    try {
      if (await _isOnline()) {
        // Online: Save to Firestore
        await _schedulesCollection.doc(schedule.id).set(schedule.toJson());

        // Save participants
        for (var participant in schedule.participants) {
          await _participantsCollection.add({
            ...participant.toJson(),
            'schedule_id': schedule.id,
          });
        }
      } else {
        // Offline: Queue for sync
        await _offlineSync.queueOperation({
          'type': 'create_schedule',
          'data': schedule.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      // Fallback to offline queue
      await _offlineSync.queueOperation({
        'type': 'create_schedule',
        'data': schedule.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      rethrow;
    }
  }

  Future<Schedule> copySchedule(String scheduleId, String newName) async {
    try {
      // Fetch original schedule
      final originalDoc = await _schedulesCollection.doc(scheduleId).get();

      if (!originalDoc.exists) {
        throw Exception('Schedule not found');
      }

      final originalSchedule = Schedule.fromJson(
        originalDoc.data() as Map<String, dynamic>,
      );

      // Create new schedule with same configuration
      final newSchedule = Schedule(
        id: const Uuid().v4(),
        name: newName,
        description: originalSchedule.description,
        availableDays: originalSchedule.availableDays,
        duration: originalSchedule.duration,
        ownerId: FirebaseManager.currentUserId!,
        participants: originalSchedule.participants
            .map((p) => Participant(
                  userId: p.userId,
                  scheduleId: '', // Will be set after creation
                  roles: p.roles,
                  freeDays: [], // Empty for new schedule
                ))
            .toList(),
        isFullySet: false,
        createdAt: DateTime.now(),
        startDate: DateTime.now(),
      );

      await createSchedule(newSchedule);

      return newSchedule;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSchedule(Schedule schedule) async {
    try {
      if (await _isOnline()) {
        await _schedulesCollection.doc(schedule.id).update({
          'name': schedule.name,
          'description': schedule.description,
          'available_days':
              schedule.availableDays.map((d) => d.toJson()).toList(),
          'duration': schedule.duration,
          'is_fully_set': schedule.isFullySet,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Sync participants
        await syncParticipants(schedule.id, schedule.participants);
      } else {
        await _offlineSync.queueOperation({
          'type': 'update_schedule',
          'data': schedule.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      await _offlineSync.queueOperation({
        'type': 'update_schedule',
        'data': schedule.toJson(),
        'timestamp': DateTime.now().toIso8601String(),
      });
      rethrow;
    }
  }

  Future<void> updateFreeDays({
    required String scheduleId,
    required String userId,
    required List<FreeDay> freeDays,
  }) async {
    try {
      // Validate free days
      final isValid = await validateFreeDays(scheduleId, userId, freeDays);
      if (!isValid) {
        throw Exception('Selected days are not available or already taken');
      }

      if (await _isOnline()) {
        // Find participant document
        final participantQuery = await _participantsCollection
            .where('schedule_id', isEqualTo: scheduleId)
            .where('user_id', isEqualTo: userId)
            .get();

        if (participantQuery.docs.isEmpty) {
          throw Exception('Participant not found');
        }

        // Update free days
        await participantQuery.docs.first.reference.update({
          'free_days': freeDays.map((d) => d.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Check and update schedule status
        await _checkAndUpdateScheduleStatus(scheduleId);

        // Send notifications to other participants
        await _notifyParticipants(scheduleId, userId, 'free_days_updated');
      } else {
        await _offlineSync.queueOperation({
          'type': 'update_free_days',
          'data': {
            'schedule_id': scheduleId,
            'user_id': userId,
            'free_days': freeDays.map((d) => d.toJson()).toList(),
          },
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteSchedule(String scheduleId) async {
    try {
      if (await _isOnline()) {
        // Delete participants
        final participants = await _participantsCollection
            .where('schedule_id', isEqualTo: scheduleId)
            .get();

        for (var doc in participants.docs) {
          await doc.reference.delete();
        }

        // Delete schedule
        await _schedulesCollection.doc(scheduleId).delete();
      } else {
        await _offlineSync.queueOperation({
          'type': 'delete_schedule',
          'data': {'id': scheduleId},
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      rethrow;
    }
  }

  Stream<List<Schedule>> getUserSchedules(String userId) {
    return _schedulesCollection
        .where('owner_id', isEqualTo: userId)
        .snapshots()
        .asyncMap((ownedSnapshot) async {
      // Get owned schedules
      final ownedSchedules = ownedSnapshot.docs
          .map((doc) => Schedule.fromJson({
                ...doc.data(),
                'id': doc.id,
              }))
          .toList();

      // Get schedules where user is participant
      final participantSnapshot = await _participantsCollection
          .where('user_id', isEqualTo: userId)
          .get();

      final participantScheduleIds = participantSnapshot.docs
          .map((doc) => doc.data()['schedule_id'] as String)
          .where((id) => !ownedSchedules.any((s) => s.id == id))
          .toList();

      List<Schedule> participantSchedules = [];
      if (participantScheduleIds.isNotEmpty) {
        for (var id in participantScheduleIds) {
          final doc = await _schedulesCollection.doc(id).get();
          if (doc.exists) {
            participantSchedules.add(Schedule.fromJson({
              ...doc.data()!,
              'id': doc.id,
            }));
          }
        }
      }

      return [...ownedSchedules, ...participantSchedules];
    });
  }

  Stream<Schedule> getSchedule(String scheduleId) {
    return _schedulesCollection.doc(scheduleId).snapshots().map((doc) {
      if (!doc.exists) {
        throw Exception('Schedule not found');
      }
      return Schedule.fromJson({...doc.data()!, 'id': doc.id});
    });
  }

  Stream<List<Participant>> getParticipants(String scheduleId) {
    return _participantsCollection
        .where('schedule_id', isEqualTo: scheduleId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Participant.fromJson(doc.data()))
            .toList());
  }

  Future<bool> validateFreeDays(
    String scheduleId,
    String userId,
    List<FreeDay> newFreeDays,
  ) async {
    try {
      // Get schedule details
      final scheduleDoc = await _schedulesCollection.doc(scheduleId).get();
      if (!scheduleDoc.exists) return false;

      final schedule = Schedule.fromJson({
        ...scheduleDoc.data()!,
        'id': scheduleDoc.id,
      });

      // Calculate valid dates
      final validDates = _calculateScheduleDates(
        schedule.startDate,
        schedule.availableDays.map((d) => d.day).toList(),
        schedule.duration,
      );

      // Check if dates are valid
      for (var freeDay in newFreeDays) {
        if (!validDates.any((date) =>
            date.year == freeDay.date.year &&
            date.month == freeDay.date.month &&
            date.day == freeDay.date.day)) {
          return false;
        }

        // Check time slot validity
        final availableDay =
            schedule.availableDays.firstWhere((d) => d.day == freeDay.day);

        if (!_isTimeSlotValid(
          freeDay.startTime,
          freeDay.endTime,
          availableDay.startTime,
          availableDay.endTime,
        )) {
          return false;
        }
      }

      // Check for conflicts with other participants
      final participants = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .where('user_id', isNotEqualTo: userId)
          .get();

      for (var freeDay in newFreeDays) {
        for (var participantDoc in participants.docs) {
          final freeDaysList = participantDoc.data()['free_days'] as List?;
          if (freeDaysList == null) continue;

          for (var takenDay in freeDaysList) {
            final takenFreeDay = FreeDay.fromJson(takenDay);

            if (_datesMatch(freeDay.date, takenFreeDay.date) &&
                _timeSlotsOverlap(
                  freeDay.startTime,
                  freeDay.endTime,
                  takenFreeDay.startTime,
                  takenFreeDay.endTime,
                )) {
              return false;
            }
          }
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _checkAndUpdateScheduleStatus(String scheduleId) async {
    try {
      final scheduleDoc = await _schedulesCollection.doc(scheduleId).get();
      if (!scheduleDoc.exists) return;

      final schedule = Schedule.fromJson({
        ...scheduleDoc.data()!,
        'id': scheduleDoc.id,
      });

      // Get all assigned dates
      final participants = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      final assignedDates = <DateTime>{};
      for (var doc in participants.docs) {
        final freeDaysList = doc.data()['free_days'] as List?;
        if (freeDaysList != null) {
          for (var day in freeDaysList) {
            final freeDay = FreeDay.fromJson(day);
            assignedDates.add(DateTime(
              freeDay.date.year,
              freeDay.date.month,
              freeDay.date.day,
            ));
          }
        }
      }

      // Calculate required dates
      final scheduleDates = _calculateScheduleDates(
        schedule.startDate,
        schedule.availableDays.map((d) => d.day).toList(),
        schedule.duration,
      );

      // Check if fully set
      final isFullySet = scheduleDates.every((date) => assignedDates.any(
          (assigned) =>
              assigned.year == date.year &&
              assigned.month == date.month &&
              assigned.day == date.day));

      if (schedule.isFullySet != isFullySet) {
        await _schedulesCollection.doc(scheduleId).update({
          'is_fully_set': isFullySet,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Notify participants
        await _notifyParticipants(scheduleId, null, 'schedule_status_updated');
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> syncParticipants(
    String scheduleId,
    List<Participant> participants,
  ) async {
    try {
      // Get existing participants
      final existingDocs = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      final existingUserIds = existingDocs.docs
          .map((doc) => doc.data()['user_id'] as String)
          .toSet();
      final newUserIds = participants.map((p) => p.userId).toSet();

      // Remove participants no longer in list
      final toRemove = existingUserIds.difference(newUserIds);
      for (var doc in existingDocs.docs) {
        if (toRemove.contains(doc.data()['user_id'])) {
          await doc.reference.delete();
        }
      }

      // Add or update participants
      for (var participant in participants) {
        final existingDoc = existingDocs.docs.firstWhere(
          (doc) => doc.data()['user_id'] == participant.userId,
          orElse: () => throw StateError('Not found'),
        );

        try {
          await existingDoc.reference.update({
            'roles': participant.roles.map((r) => r.toJson()).toList(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          // Document doesn't exist, create it
          await _participantsCollection.add({
            ...participant.toJson(),
            'schedule_id': scheduleId,
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _notifyParticipants(
    String scheduleId,
    String? excludeUserId,
    String notificationType,
  ) async {
    try {
      final participants = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      final scheduleDoc = await _schedulesCollection.doc(scheduleId).get();
      final scheduleName = scheduleDoc.data()?['name'] ?? 'Schedule';

      for (var doc in participants.docs) {
        final userId = doc.data()['user_id'] as String;
        if (userId == excludeUserId) continue;

        await _notificationsCollection.add({
          'user_id': userId,
          'type': notificationType,
          'data': {
            'schedule_id': scheduleId,
            'schedule_name': scheduleName,
          },
          'creator_id': FirebaseManager.currentUserId,
          'created_at': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      // ignore
    }
  }

  List<DateTime> _calculateScheduleDates(
    DateTime startDate,
    List<String> availableDays,
    String duration,
  ) {
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
        date = date.add(const Duration(days: 1))) {
      final dayName = daysOfWeek[date.weekday - 1];
      if (availableDays.contains(dayName)) {
        dates.add(DateTime(date.year, date.month, date.day));
      }
    }

    return dates;
  }

  bool _isTimeSlotValid(
    String startTime,
    String endTime,
    String availableStart,
    String availableEnd,
  ) {
    final start = _timeToMinutes(startTime);
    final end = _timeToMinutes(endTime);
    final availStart = _timeToMinutes(availableStart);
    final availEnd = _timeToMinutes(availableEnd);

    return start >= availStart && end <= availEnd;
  }

  bool _datesMatch(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _timeSlotsOverlap(
    String start1,
    String end1,
    String start2,
    String end2,
  ) {
    final s1 = _timeToMinutes(start1);
    final e1 = _timeToMinutes(end1);
    final s2 = _timeToMinutes(start2);
    final e2 = _timeToMinutes(end2);

    return s1 < e2 && e1 > s2;
  }

  int _timeToMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    final parts = timeString.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
