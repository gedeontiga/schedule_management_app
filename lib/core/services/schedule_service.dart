import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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
        // Create schedule document
        await _schedulesCollection.doc(schedule.id).set(schedule.toJson());

        // Create participant documents with proper structure
        for (var participant in schedule.participants) {
          await _participantsCollection.add({
            'user_id': participant.userId,
            'schedule_id': schedule.id,
            'roles': participant.roles.map((r) => r.toJson()).toList(),
            'free_days': participant.freeDays.map((d) => d.toJson()).toList(),
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await _offlineSync.queueOperation({
          'type': 'create_schedule',
          'data': schedule.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
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
      final originalDoc = await _schedulesCollection.doc(scheduleId).get();

      if (!originalDoc.exists) {
        throw Exception('Schedule not found');
      }

      final originalSchedule = Schedule.fromJson({
        ...originalDoc.data() as Map<String, dynamic>,
        'id': originalDoc.id,
      });

      final newScheduleId = const Uuid().v4();
      final newSchedule = Schedule(
        id: newScheduleId,
        name: newName,
        description: originalSchedule.description,
        availableDays: originalSchedule.availableDays,
        duration: originalSchedule.duration,
        ownerId: FirebaseManager.currentUserId!,
        participants: originalSchedule.participants
            .map((p) => Participant(
                  userId: p.userId,
                  scheduleId: newScheduleId,
                  roles: p.roles,
                  freeDays: [],
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
          'start_date': Timestamp.fromDate(schedule.startDate),
          'is_fully_set': schedule.isFullySet,
          'updated_at': FieldValue.serverTimestamp(),
        });

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
      final isValid = await validateFreeDays(scheduleId, userId, freeDays);
      if (!isValid) {
        throw Exception('Selected days are not available or already taken');
      }

      if (await _isOnline()) {
        final participantQuery = await _participantsCollection
            .where('schedule_id', isEqualTo: scheduleId)
            .where('user_id', isEqualTo: userId)
            .get();

        if (participantQuery.docs.isEmpty) {
          throw Exception('Participant not found');
        }

        await participantQuery.docs.first.reference.update({
          'free_days': freeDays.map((d) => d.toJson()).toList(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        await _checkAndUpdateScheduleStatus(scheduleId);

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
        final participants = await _participantsCollection
            .where('schedule_id', isEqualTo: scheduleId)
            .get();

        for (var doc in participants.docs) {
          await doc.reference.delete();
        }

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
      final ownedSchedules = await Future.wait(
        ownedSnapshot.docs.map((doc) async {
          final participants = await getParticipants(doc.id).first;
          return Schedule.fromJson({
            ...doc.data(),
            'id': doc.id,
          }).copyWith(participants: participants);
        }),
      );

      final participantSnapshot = await _participantsCollection
          .where('user_id', isEqualTo: userId)
          .get();

      final participantScheduleIds = participantSnapshot.docs
          .map((doc) => doc.data()['schedule_id'] as String)
          .where((id) => !ownedSchedules.any((s) => s.id == id))
          .toSet()
          .toList();

      List<Schedule> participantSchedules = [];
      if (participantScheduleIds.isNotEmpty) {
        for (var id in participantScheduleIds) {
          final doc = await _schedulesCollection.doc(id).get();
          if (doc.exists) {
            final participants = await getParticipants(id).first;
            participantSchedules.add(
              Schedule.fromJson({
                ...doc.data()!,
                'id': doc.id,
              }).copyWith(participants: participants),
            );
          }
        }
      }

      return [...ownedSchedules, ...participantSchedules];
    });
  }

  Stream<Schedule> getSchedule(String scheduleId) {
    return _schedulesCollection
        .doc(scheduleId)
        .snapshots()
        .asyncMap((doc) async {
      if (!doc.exists) {
        throw Exception('Schedule not found');
      }

      final participants = await getParticipants(scheduleId).first;
      return Schedule.fromJson({
        ...doc.data()!,
        'id': doc.id,
      }).copyWith(participants: participants);
    });
  }

  Stream<List<Participant>> getParticipants(String scheduleId) {
    return _participantsCollection
        .where('schedule_id', isEqualTo: scheduleId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Participant.fromJson({
                  ...doc.data(),
                  'id': doc.id,
                }))
            .toList());
  }

  Future<bool> validateFreeDays(
    String scheduleId,
    String userId,
    List<FreeDay> newFreeDays,
  ) async {
    try {
      final scheduleDoc = await _schedulesCollection.doc(scheduleId).get();
      if (!scheduleDoc.exists) {
        debugPrint('Schedule not found');
        return false;
      }

      final schedule = Schedule.fromJson({
        ...scheduleDoc.data()!,
        'id': scheduleDoc.id,
      });

      final validDates = _calculateScheduleDates(
        schedule.startDate,
        schedule.availableDays.map((d) => d.day).toList(),
        schedule.duration,
      );

      debugPrint('Valid dates: ${validDates.length}');
      debugPrint('New free days: ${newFreeDays.length}');

      for (var freeDay in newFreeDays) {
        // Check if date is in valid range
        final dateIsValid = validDates.any((date) =>
            date.year == freeDay.date.year &&
            date.month == freeDay.date.month &&
            date.day == freeDay.date.day);

        if (!dateIsValid) {
          debugPrint('Date ${freeDay.date} is not in valid schedule dates');
          return false;
        }

        // Check if day name matches available days
        final availableDayMatch = schedule.availableDays.firstWhere(
          (d) => d.day == freeDay.day,
          orElse: () => null as dynamic,
        );

        // Check if time slot is within available hours
        final timeSlotValid = _isTimeSlotValid(
          freeDay.startTime,
          freeDay.endTime,
          availableDayMatch.startTime,
          availableDayMatch.endTime,
        );

        if (!timeSlotValid) {
          debugPrint(
              'Time slot ${freeDay.startTime}-${freeDay.endTime} not valid for ${availableDayMatch.startTime}-${availableDayMatch.endTime}');
          return false;
        }
      }

      // Get ALL participants (including current user) - simpler query without inequality
      final allParticipants = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      debugPrint('Total participants: ${allParticipants.docs.length}');

      // Get current user's existing free days
      final currentUserFreeDays = <FreeDay>[];
      for (var doc in allParticipants.docs) {
        if (doc.data()['user_id'] == userId) {
          final freeDaysList = doc.data()['free_days'] as List?;
          if (freeDaysList != null) {
            for (var day in freeDaysList) {
              currentUserFreeDays
                  .add(FreeDay.fromJson(day as Map<String, dynamic>));
            }
          }
          break;
        }
      }

      debugPrint(
          'Current user has ${currentUserFreeDays.length} existing free days');

      // Check for conflicts with other participants
      for (var freeDay in newFreeDays) {
        // Check if this is an update to an existing day (same date)
        final isUpdatingExistingDay = currentUserFreeDays.any((d) =>
            d.date.year == freeDay.date.year &&
            d.date.month == freeDay.date.month &&
            d.date.day == freeDay.date.day);

        debugPrint(
            'Checking day ${freeDay.date} - isUpdate: $isUpdatingExistingDay');

        // Check other participants
        for (var participantDoc in allParticipants.docs) {
          final participantUserId = participantDoc.data()['user_id'] as String;

          // Skip current user
          if (participantUserId == userId) continue;

          final freeDaysList = participantDoc.data()['free_days'] as List?;
          if (freeDaysList == null) continue;

          for (var takenDay in freeDaysList) {
            final takenFreeDay =
                FreeDay.fromJson(takenDay as Map<String, dynamic>);

            // Check if dates match
            if (_datesMatch(freeDay.date, takenFreeDay.date)) {
              // Check if time slots overlap
              final overlap = _timeSlotsOverlap(
                freeDay.startTime,
                freeDay.endTime,
                takenFreeDay.startTime,
                takenFreeDay.endTime,
              );

              if (overlap) {
                debugPrint(
                    'Time slot overlap detected on ${freeDay.date}: ${freeDay.startTime}-${freeDay.endTime} vs ${takenFreeDay.startTime}-${takenFreeDay.endTime} (participant: $participantUserId)');
                return false;
              }
            }
          }
        }
      }

      debugPrint('Validation passed');
      return true;
    } catch (e) {
      debugPrint('Validation error: $e');
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

      final participants = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      debugPrint('Checking schedule status for: $scheduleId');
      debugPrint('Participants count: ${participants.docs.length}');

      // Map to store date -> list of time slots assigned
      final assignedSlotsByDate = <String, List<Map<String, int>>>{};

      for (var doc in participants.docs) {
        final freeDaysList = doc.data()['free_days'] as List?;
        debugPrint(
            'Participant ${doc.data()['user_id']} has ${freeDaysList?.length ?? 0} free days');

        if (freeDaysList != null) {
          for (var day in freeDaysList) {
            final freeDay = FreeDay.fromJson(day as Map<String, dynamic>);
            final dateKey =
                '${freeDay.date.year}-${freeDay.date.month}-${freeDay.date.day}';

            final startMinutes = _timeToMinutes(freeDay.startTime);
            final endMinutes = _timeToMinutes(freeDay.endTime);

            debugPrint(
                'Assigned slot: $dateKey ${freeDay.startTime}-${freeDay.endTime}');

            if (!assignedSlotsByDate.containsKey(dateKey)) {
              assignedSlotsByDate[dateKey] = [];
            }
            assignedSlotsByDate[dateKey]!.add({
              'start': startMinutes,
              'end': endMinutes,
            });
          }
        }
      }

      final scheduleDates = _calculateScheduleDates(
        schedule.startDate,
        schedule.availableDays.map((d) => d.day).toList(),
        schedule.duration,
      );

      debugPrint('Schedule dates count: ${scheduleDates.length}');

      // Check if all dates are fully covered
      bool isFullySet = true;

      final daysOfWeek = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];

      int coveredDays = 0;

      for (var date in scheduleDates) {
        final dateKey = '${date.year}-${date.month}-${date.day}';
        final dayName = daysOfWeek[date.weekday - 1];

        // Get the available day constraints for this day
        final availableDay = schedule.availableDays.firstWhere(
          (d) => d.day == dayName,
          orElse: () => null as dynamic,
        );

        final dayStartMinutes = _timeToMinutes(availableDay.startTime);
        final dayEndMinutes = _timeToMinutes(availableDay.endTime);
        final totalDayMinutes = dayEndMinutes - dayStartMinutes;

        if (!assignedSlotsByDate.containsKey(dateKey)) {
          debugPrint('Date $dateKey has no assignments');
          isFullySet = false;
          break;
        }

        // Calculate total assigned minutes for this date
        final slots = assignedSlotsByDate[dateKey]!;
        int totalAssignedMinutes = 0;

        // Sort slots by start time
        slots.sort((a, b) => a['start']!.compareTo(b['start']!));

        // Merge overlapping slots and calculate coverage
        final mergedSlots = <Map<String, int>>[];
        for (var slot in slots) {
          // Ensure slot is within the day's boundaries
          final slotStart = slot['start']! < dayStartMinutes
              ? dayStartMinutes
              : slot['start']!;
          final slotEnd =
              slot['end']! > dayEndMinutes ? dayEndMinutes : slot['end']!;

          if (slotStart >= slotEnd) continue;

          if (mergedSlots.isEmpty) {
            mergedSlots.add({'start': slotStart, 'end': slotEnd});
          } else {
            final last = mergedSlots.last;
            if (slotStart <= last['end']!) {
              // Overlapping or adjacent, merge them
              last['end'] = slotEnd > last['end']! ? slotEnd : last['end']!;
            } else {
              mergedSlots.add({'start': slotStart, 'end': slotEnd});
            }
          }
        }

        // Calculate total coverage
        for (var slot in mergedSlots) {
          totalAssignedMinutes += slot['end']! - slot['start']!;
        }

        debugPrint(
            'Date $dateKey: $totalAssignedMinutes/$totalDayMinutes minutes covered');

        // Check if the entire day is covered
        if (totalAssignedMinutes >= totalDayMinutes) {
          coveredDays++;
        } else {
          isFullySet = false;
        }
      }

      debugPrint('Covered days: $coveredDays/${scheduleDates.length}');
      debugPrint('Is fully set: $isFullySet');

      if (schedule.isFullySet != isFullySet) {
        debugPrint('Updating schedule status to: $isFullySet');
        await _schedulesCollection.doc(scheduleId).update({
          'is_fully_set': isFullySet,
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (isFullySet) {
          await _notifyParticipants(scheduleId, null, 'schedule_completed');
        }
      }
    } catch (e) {
      debugPrint('Error checking schedule status: $e');
    }
  }

  Future<void> syncParticipants(
    String scheduleId,
    List<Participant> participants,
  ) async {
    try {
      final existingDocs = await _participantsCollection
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      final existingUserIds = existingDocs.docs
          .map((doc) => doc.data()['user_id'] as String)
          .toSet();
      final newUserIds = participants.map((p) => p.userId).toSet();

      final toRemove = existingUserIds.difference(newUserIds);
      for (var doc in existingDocs.docs) {
        if (toRemove.contains(doc.data()['user_id'])) {
          await doc.reference.delete();
        }
      }

      for (var participant in participants) {
        final existingDocList = existingDocs.docs
            .where((doc) => doc.data()['user_id'] == participant.userId)
            .toList();

        if (existingDocList.isNotEmpty) {
          await existingDocList.first.reference.update({
            'roles': participant.roles.map((r) => r.toJson()).toList(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        } else {
          await _participantsCollection.add({
            'user_id': participant.userId,
            'schedule_id': scheduleId,
            'roles': participant.roles.map((r) => r.toJson()).toList(),
            'free_days': participant.freeDays.map((d) => d.toJson()).toList(),
            'created_at': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      // Silent fail
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
      // Silent fail
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
      case '3 weeks':
        weeks = 3;
        break;
      case '1 month':
        weeks = 4;
        break;
      case '2 months':
        weeks = 8;
        break;
      case '3 months':
        weeks = 12;
        break;
      case '6 months':
        weeks = 26;
        break;
      default:
        weeks = int.tryParse(duration.split(' ')[0]) ?? 1;
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

    return start >= availStart && end <= availEnd && start < end;
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
    if (parts.length != 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
