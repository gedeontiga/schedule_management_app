import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
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

    // Try to load schedules when service is initialized
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
    _scheduleChannel?.unsubscribe();
    _participantChannel?.unsubscribe();
    _notificationChannel?.unsubscribe();
    _permutationRequestChannel?.unsubscribe();

    _scheduleChannel = supabase
        .channel('public:schedules')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'schedules',
          callback: (payload) async {
            // print('Schedule payload received: $payload'); // Debug print
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              final updatedSchedules = await getUserSchedules(userId);
              // print('Updated schedules: $updatedSchedules'); // Debug print
              scheduleStreamController.add(updatedSchedules);
            }
          },
        )
        .subscribe((status, [error]) {
      // print('Schedule channel status: $status, error: $error'); // Debug print
      if (status == RealtimeSubscribeStatus.subscribed) {
        // print('Subscribed to schedules channel');
      } else if (error != null) {
        // print('Subscription error: $error');
        Future.delayed(const Duration(seconds: 5), _initRealtimeSubscriptions);
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
                _participantStreamController.add(
                    participants.map((p) => Participant.fromJson(p)).toList());
              } catch (e) {
                _participantStreamController.add([]);
              }
            }
          },
        )
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
      } else if (error != null) {
        Future.delayed(const Duration(seconds: 5), _initRealtimeSubscriptions);
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
      } else if (error != null) {
        Future.delayed(const Duration(seconds: 5), _initRealtimeSubscriptions);
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
      } else if (error != null) {
        Future.delayed(const Duration(seconds: 5), _initRealtimeSubscriptions);
      }
    });
  }

  Future<void> createSchedule(Schedule schedule) async {
    // print('Creating schedule: ${schedule.name}'); // Debug print
    if (await isOnline()) {
      try {
        await supabase.from('schedules').insert(schedule.toJson());
        // Also insert participants into participants table
        for (var participant in schedule.participants) {
          await supabase.from('participants').insert(participant.toJson());
        }
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          // print('Post-create schedules: $updatedSchedules'); // Debug print
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        // print('Error creating schedule online: $e'); // Debug print
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        // Insert participants into local participants table
        for (var participant in schedule.participants) {
          await db.insert(
            'participants',
            {
              'id': const Uuid().v4(),
              'schedule_id': schedule.id,
              'user_id': participant.userId,
              'roles':
                  jsonEncode(participant.roles.map((r) => r.toJson()).toList()),
              'free_days': participant.freeDays.join(','),
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
          // print(
          // 'Post-create offline schedules: $updatedSchedules'); // Debug print
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        // print('Error creating schedule offline: $e'); // Debug print
        rethrow;
      }
    }
  }

  Future<void> updateSchedule(Schedule schedule) async {
    // print('Updating schedule: ${schedule.name}');
    if (await isOnline()) {
      try {
        await supabase
            .from('schedules')
            .update(schedule.toJson())
            .eq('id', schedule.id);
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          // print('Post-update schedules: $updatedSchedules');
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        // print('Error updating schedule online: $e');
        await offlineOperationsBox.add({
          'operation': 'update_schedule',
          'data': schedule.toJson(),
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
            'participants': jsonEncode(
                schedule.participants.map((p) => p.toJson()).toList()),
            'is_fully_set': schedule.isFullySet ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [schedule.id],
        );
        await offlineOperationsBox.add({
          'operation': 'update_schedule',
          'data': schedule.toJson(),
        });
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          // print('Post-update offline schedules: $updatedSchedules');
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        // print('Error updating schedule offline: $e');
        rethrow;
      }
    }
  }

  Future<void> syncParticipants(
      String scheduleId, List<Participant> participants) async {
    if (await isOnline()) {
      try {
        // Fetch existing participants
        final existingParticipants = await supabase
            .from('participants')
            .select()
            .eq('schedule_id', scheduleId);

        // Determine participants to remove
        final existingUserIds =
            existingParticipants.map((p) => p['user_id'] as String).toSet();
        final newUserIds = participants.map((p) => p.userId).toSet();
        final userIdsToRemove = existingUserIds.difference(newUserIds);

        // Remove participants not in the new list
        if (userIdsToRemove.isNotEmpty) {
          await supabase
              .from('participants')
              .delete()
              .eq('schedule_id', scheduleId)
              .inFilter('user_id', userIdsToRemove.toList());
        }

        // Add or update participants
        for (var participant in participants) {
          await supabase.from('participants').upsert(participant.toJson());
        }
      } catch (e) {
        // print('Error syncing participants online: $e');
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
        // Clear existing participants
        await db.delete('participants',
            where: 'schedule_id = ?', whereArgs: [scheduleId]);
        // Add new participants
        for (var participant in participants) {
          await db.insert(
            'participants',
            {
              'id': const Uuid().v4(),
              'schedule_id': scheduleId,
              'user_id': participant.userId,
              'roles':
                  jsonEncode(participant.roles.map((r) => r.toJson()).toList()),
              'free_days': participant.freeDays.join(','),
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
        // print('Error syncing participants offline: $e');
        rethrow;
      }
    }
  }

  // Add this method to the ScheduleService class

  Future<bool> deleteSchedule(String scheduleId) async {
    // print('Deleting schedule: $scheduleId');

    if (await isOnline()) {
      try {
        // First delete participants associated with this schedule
        await supabase
            .from('participants')
            .delete()
            .eq('schedule_id', scheduleId);

        // Then delete the schedule itself
        await supabase.from('schedules').delete().eq('id', scheduleId);

        // Update the schedules list
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          // print('Post-delete schedules: $updatedSchedules');
          scheduleStreamController.add(updatedSchedules);
        }

        return true;
      } catch (e) {
        // print('Error deleting schedule online: $e');
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

        // Delete participants
        await db.delete(
          'participants',
          where: 'schedule_id = ?',
          whereArgs: [scheduleId],
        );

        // Delete schedule
        await db.delete(
          'schedules',
          where: 'id = ?',
          whereArgs: [scheduleId],
        );

        // Add to offline operations
        await offlineOperationsBox.add({
          'operation': 'delete_schedule',
          'data': {
            'id': scheduleId,
          },
        });

        // Update the schedules list
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          // print('Post-delete offline schedules: $updatedSchedules');
          scheduleStreamController.add(updatedSchedules);
        }

        return true;
      } catch (e) {
        // print('Error deleting schedule offline: $e');
        return false;
      }
    }
  }

// Fix the getUserSchedules method to properly handle duplicates

  Future<List<Schedule>> getUserSchedules(String userId) async {
    // print('Fetching schedules for user: $userId');

    if (await isOnline()) {
      try {
        // Get schedules owned by the user
        final ownedSchedules =
            await supabase.from('schedules').select().eq('owner_id', userId);
        // print('Owned schedules: $ownedSchedules');

        // Get schedules the user participates in
        final participantSchedules = await supabase
            .from('participants')
            .select('schedule_id')
            .eq('user_id', userId);
        // print('Participant schedule IDs: $participantSchedules');

        final participantScheduleIds = (participantSchedules as List)
            .map((item) => item['schedule_id'].toString())
            .toList();

        // Create a set to track schedule IDs we've already processed
        final processedScheduleIds =
            ownedSchedules.map((schedule) => schedule['id'] as String).toSet();

        // Filter out participant schedules that are already in the owned list
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
        // print('Participant schedules: $participantSchedulesData');

        // Combine the lists without duplicates
        final allSchedules = [...ownedSchedules, ...participantSchedulesData];
        // print('All schedules: $allSchedules');

        final schedules =
            allSchedules.map((json) => Schedule.fromJson(json)).toList();

        // print('Final schedules count: ${schedules.length}');
        scheduleStreamController.add(schedules);
        return schedules;
      } catch (e) {
        // print('Error fetching schedules online: $e');
        return [];
      }
    } else {
      try {
        final db = dbManager.localDatabase;

        // Get schedules owned by the user
        final ownerSchedules = await db.query(
          'schedules',
          where: 'owner_id = ?',
          whereArgs: [userId],
        );

        // Create a set of schedule IDs to track what we've already processed
        final processedScheduleIds =
            ownerSchedules.map((schedule) => schedule['id'] as String).toSet();

        // Get participant schedules
        final participantRows = await db.query(
          'participants',
          columns: ['schedule_id'],
          where: 'user_id = ?',
          whereArgs: [userId],
        );

        // Filter out schedule IDs that are already in the owned list
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

        // Combine the lists (no duplicates because we filtered)
        final allSchedules = [...ownerSchedules, ...participantSchedules];
        // print('Local database schedules: ${allSchedules.length}');

        return allSchedules.map((row) {
          return Schedule(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String?,
            availableDays: (row['available_days'] as String).split(','),
            duration: row['duration'] as String,
            ownerId: row['owner_id'] as String,
            participants: [],
            isFullySet: (row['is_fully_set'] as int) == 1,
          );
        }).toList();
      } catch (e) {
        // print('Error fetching schedules offline: $e');
        return [];
      }
    }
  }

// Update the syncOfflineOperations method to handle schedule deletion

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
            .update({'free_days': op['data']['free_days']})
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
        // Handle offline deletion
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
            .select()
            .eq('schedule_id', scheduleId);

        final existingUserIds =
            existingParticipants.map((p) => p['user_id'] as String).toSet();
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
          await supabase.from('participants').upsert(participant.toJson());
        }
      }

      await offlineOperationsBox.deleteAt(i);
    }
  }

  Future<void> updateFreeDays(
      String scheduleId, String userId, List<String> freeDays) async {
    if (await isOnline()) {
      try {
        await supabase
            .from('participants')
            .update({'free_days': freeDays})
            .eq('schedule_id', scheduleId)
            .eq('user_id', userId);
      } catch (e) {
        await _box.add({
          'operation': 'update_free_days',
          'data': {
            'schedule_id': scheduleId,
            'user_id': userId,
            'free_days': freeDays,
          },
        });
        rethrow;
      }
    } else {
      // try {
      final db = dbManager.localDatabase;
      await db.update(
        'participants',
        {'free_days': freeDays.join(',')},
        where: 'schedule_id = ? AND user_id = ?',
        whereArgs: [scheduleId, userId],
      );
      // } catch (e) {}
      await _box.add({
        'operation': 'update_free_days',
        'data': {
          'schedule_id': scheduleId,
          'user_id': userId,
          'free_days': freeDays,
        },
      });
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
      // try {
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
      // } catch (e) {}
      await _box.add({
        'operation': 'add_participant',
        'data': participant.toJson(),
      });
    }
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
