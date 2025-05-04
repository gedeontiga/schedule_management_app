import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';

import '../../models/permutation_request.dart';
import '../utils/supabase_manager.dart';

class NotificationService {
  final _supabase = SupabaseManager.client;

  Future<void> sendInvitation(
      String scheduleId, String userId, String roles) async {
    try {
      final notification = {
        'id': const Uuid().v4(),
        'user_id': userId,
        'creator_id': SupabaseManager.getCurrentUserId(),
        'type': 'invitation',
        'data': {
          'schedule_id': scheduleId,
          'roles': roles,
        },
        'created_at': DateTime.now().toIso8601String(),
      };
      await _supabase.from('notifications').insert(notification);
    } catch (e) {
      throw Exception('Failed to send invitation: $e');
    }
  }

  Future<void> updateInvitationStatus(
      String notificationId, String status) async {
    try {
      await _supabase.from('notifications').update({
        'data': {'status': status}
      }).eq('id', notificationId);
    } catch (e) {
      throw Exception('Failed to update invitation status: $e');
    }
  }

  Future<void> sendPermutationRequest(PermutationRequest request) async {
    try {
      await _supabase.from('permutation_requests').insert(request.toJson());
      await _supabase.from('notifications').insert({
        'user_id': request.receiverId,
        'type': 'permutation_request',
        'data': {
          'request_id': request.id,
          'schedule_id': request.scheduleId,
          'message':
              'User requests to swap your ${request.receiverDay} with their ${request.senderDay}.',
        },
        'creator_id': request.senderId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Send mobile push notification
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin.show(
        request.id.hashCode,
        'Permutation Request',
        'User requests to swap your ${request.receiverDay} with their ${request.senderDay}.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'permutation_request',
            'Permutation Requests',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      throw Exception('Failed to send permutation request: $e');
    }
  }

  Future<void> updatePermutationRequestStatus(String requestId, String status,
      String scheduleId, String senderId, String receiverId) async {
    try {
      await _supabase
          .from('permutation_requests')
          .update({'status': status}).eq('id', requestId);

      // Notify the initiator of the decision
      final message = status == 'accepted'
          ? 'Your permutation request for schedule $scheduleId has been accepted.'
          : 'Your permutation request for schedule $scheduleId has been rejected.';
      await _supabase.from('notifications').insert({
        'user_id': senderId,
        'type': 'permutation_response',
        'data': {
          'request_id': requestId,
          'schedule_id': scheduleId,
          'status': status,
          'message': message,
        },
        'creator_id': receiverId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Send mobile push notification to initiator
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin.show(
        requestId.hashCode,
        'Permutation Request Response',
        message,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'permutation_response',
            'Permutation Responses',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      throw Exception('Failed to update permutation request: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getNotifications(String userId) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id']).eq('user_id', userId);
  }
}
