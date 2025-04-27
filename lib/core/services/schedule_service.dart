import 'dart:convert';
import 'dart:developer';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final scheduleStreamController = StreamController<List<Schedule>>.broadcast();
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
            final userId = supabase.auth.currentUser?.id;
            if (userId != null) {
              final updatedSchedules = await getUserSchedules(userId);
              scheduleStreamController.add(updatedSchedules);
            }
          },
        )
        .subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
      } else if (error != null) {
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
    log('Creating schedule: ${schedule.name}'); // Debug log
    if (await isOnline()) {
      try {
        await supabase.from('schedules').insert(schedule.toJson());
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          log('Post-create schedules: $updatedSchedules'); // Debug log
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        log('Error creating schedule online: $e'); // Debug log
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
        await offlineOperationsBox.add({
          'operation': 'create_schedule',
          'data': schedule.toJson(),
        });
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          final updatedSchedules = await getUserSchedules(userId);
          log('Post-create offline schedules: $updatedSchedules'); // Debug log
          scheduleStreamController.add(updatedSchedules);
        }
      } catch (e) {
        log('Error creating schedule offline: $e'); // Debug log
        rethrow;
      }
    }
  }

  Future<List<Schedule>> getUserSchedules(String userId) async {
    log('Fetching schedules for user: $userId'); // Debug log
    if (await isOnline()) {
      try {
        final response = await supabase
            .from('schedules')
            .select()
            .or('owner_id.eq.$userId,participants.cs.{$userId}');
        log('Supabase response: $response'); // Debug log
        return (response as List)
            .map((json) => Schedule.fromJson(json))
            .toList();
      } catch (e) {
        log('Error fetching schedules online: $e'); // Debug log
        return [];
      }
    } else {
      try {
        final db = dbManager.localDatabase;
        final result = await db.query(
          'schedules',
          where: 'owner_id = ? OR participants LIKE ?',
          whereArgs: [userId, '%$userId%'],
        );
        log('Local database schedules: $result'); // Debug log
        return result.map((row) {
          return Schedule(
            id: row['id'] as String,
            name: row['name'] as String,
            description: row['description'] as String?,
            availableDays: (row['available_days'] as String).split(','),
            duration: row['duration'] as String,
            ownerId: row['owner_id'] as String,
            participants: [], // Note: Participants may need to be fetched separately
            isFullySet: (row['is_fully_set'] as int) == 1,
          );
        }).toList();
      } catch (e) {
        log('Error fetching schedules offline: $e'); // Debug log
        return [];
      }
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

  Future<void> syncOfflineOperations() async {
    if (!await isOnline()) return;
    final operations = _box.values.toList();
    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      if (op['operation'] == 'create_schedule') {
        await supabase.from('schedules').insert(op['data']);
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
      }
      await _box.deleteAt(i);
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
