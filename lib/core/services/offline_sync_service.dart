import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/firebase_manager.dart';

class OfflineSyncService {
  static const String _operationsBoxName = 'pending_operations';
  static const String _cacheBoxName = 'offline_cache';

  Box? _operationsBox;
  Box? _cacheBox;
  bool _isSyncing = false;

  Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      _operationsBox = await Hive.openBox(_operationsBoxName);
      _cacheBox = await Hive.openBox(_cacheBoxName);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> queueOperation(Map<String, dynamic> operation) async {
    try {
      final box = _operationsBox ?? await Hive.openBox(_operationsBoxName);
      await box.add({
        ...operation,
        'queued_at': DateTime.now().toIso8601String(),
        'status': 'pending',
      });
    } catch (e) {
      // Ignore
    }
  }

  int get pendingOperationsCount {
    return _operationsBox?.values
            .where((op) => op['status'] == 'pending')
            .length ??
        0;
  }

  Future<void> syncPendingOperations() async {
    if (_isSyncing) {
      return;
    }

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return;
    }

    _isSyncing = true;

    try {
      final box = _operationsBox ?? await Hive.openBox(_operationsBoxName);
      final operations = box.values.toList();

      for (var i = 0; i < operations.length; i++) {
        final operation = operations[i] as Map;

        if (operation['status'] != 'pending') continue;

        try {
          await _executeSyncOperation(operation);

          // Mark as completed
          await box.putAt(i, {
            ...operation,
            'status': 'completed',
            'synced_at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          // Mark as failed
          await box.putAt(i, {
            ...operation,
            'status': 'failed',
            'error': e.toString(),
            'failed_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // Clean up completed operations older than 7 days
      await _cleanupOldOperations();
    } catch (e) {
      // Ignore
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _executeSyncOperation(Map operation) async {
    final type = operation['type'] as String;
    final data = operation['data'] as Map<String, dynamic>;

    switch (type) {
      case 'create_schedule':
        await _syncCreateSchedule(data);
        break;
      case 'update_schedule':
        await _syncUpdateSchedule(data);
        break;
      case 'delete_schedule':
        await _syncDeleteSchedule(data);
        break;
      case 'update_free_days':
        await _syncUpdateFreeDays(data);
        break;
      case 'add_participant':
        await _syncAddParticipant(data);
        break;
      default:
    }
  }

  Future<void> _syncCreateSchedule(Map<String, dynamic> data) async {
    final scheduleId = data['id'] as String;
    await FirebaseManager.firestore
        .collection('schedules')
        .doc(scheduleId)
        .set(data);

    // Sync participants if any
    final participants = data['participants'] as List?;
    if (participants != null) {
      for (var participant in participants) {
        await FirebaseManager.firestore.collection('participants').add({
          ...participant,
          'schedule_id': scheduleId,
        });
      }
    }
  }

  Future<void> _syncUpdateSchedule(Map<String, dynamic> data) async {
    final scheduleId = data['id'] as String;
    await FirebaseManager.firestore
        .collection('schedules')
        .doc(scheduleId)
        .update(data);
  }

  Future<void> _syncDeleteSchedule(Map<String, dynamic> data) async {
    final scheduleId = data['id'] as String;

    // Delete participants
    final participants = await FirebaseManager.firestore
        .collection('participants')
        .where('schedule_id', isEqualTo: scheduleId)
        .get();

    for (var doc in participants.docs) {
      await doc.reference.delete();
    }

    // Delete schedule
    await FirebaseManager.firestore
        .collection('schedules')
        .doc(scheduleId)
        .delete();
  }

  Future<void> _syncUpdateFreeDays(Map<String, dynamic> data) async {
    final scheduleId = data['schedule_id'] as String;
    final userId = data['user_id'] as String;
    final freeDays = data['free_days'] as List;

    final participants = await FirebaseManager.firestore
        .collection('participants')
        .where('schedule_id', isEqualTo: scheduleId)
        .where('user_id', isEqualTo: userId)
        .get();

    if (participants.docs.isNotEmpty) {
      await participants.docs.first.reference.update({
        'free_days': freeDays,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _syncAddParticipant(Map<String, dynamic> data) async {
    await FirebaseManager.firestore.collection('participants').add(data);
  }

  Future<void> cacheData(String key, dynamic data) async {
    try {
      final box = _cacheBox ?? await Hive.openBox(_cacheBoxName);
      await box.put(key, {
        'data': data,
        'cached_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Ignore
    }
  }

  dynamic getCachedData(String key) {
    try {
      final box = _cacheBox ?? Hive.box(_cacheBoxName);
      final cached = box.get(key);
      if (cached == null) return null;

      final cachedAt = DateTime.parse(cached['cached_at'] as String);
      final age = DateTime.now().difference(cachedAt);

      // Cache expires after 24 hours
      if (age.inHours > 24) {
        box.delete(key);
        return null;
      }

      return cached['data'];
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final box = _cacheBox ?? await Hive.openBox(_cacheBoxName);
      await box.clear();
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _cleanupOldOperations() async {
    try {
      final box = _operationsBox ?? await Hive.openBox(_operationsBoxName);
      final now = DateTime.now();
      final keysToDelete = <int>[];

      for (var i = 0; i < box.length; i++) {
        final operation = box.getAt(i) as Map;
        final queuedAt = DateTime.parse(operation['queued_at'] as String);
        final age = now.difference(queuedAt);

        if (age.inDays > 7 && operation['status'] == 'completed') {
          keysToDelete.add(i);
        }
      }

      // Delete in reverse order to maintain indices
      for (var i = keysToDelete.length - 1; i >= 0; i--) {
        await box.deleteAt(keysToDelete[i]);
      }

      if (keysToDelete.isNotEmpty) {
        await syncPendingOperations();
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> retryFailedOperations() async {
    try {
      final box = _operationsBox ?? await Hive.openBox(_operationsBoxName);

      for (var i = 0; i < box.length; i++) {
        final operation = box.getAt(i) as Map;

        if (operation['status'] == 'failed') {
          await box.putAt(i, {
            ...operation,
            'status': 'pending',
          });
        }
      }

      await syncPendingOperations();
    } catch (e) {
      // Ignore
    }
  }

  Map<String, int> getSyncStats() {
    try {
      final box = _operationsBox ?? Hive.box(_operationsBoxName);
      final operations = box.values.toList();

      return {
        'pending': operations.where((op) => op['status'] == 'pending').length,
        'completed':
            operations.where((op) => op['status'] == 'completed').length,
        'failed': operations.where((op) => op['status'] == 'failed').length,
        'total': operations.length,
      };
    } catch (e) {
      return {'pending': 0, 'completed': 0, 'failed': 0, 'total': 0};
    }
  }

  Future<void> dispose() async {
    await _operationsBox?.close();
    await _cacheBox?.close();
  }
}
