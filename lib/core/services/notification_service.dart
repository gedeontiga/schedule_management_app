import '../../models/permutation_request.dart';
import '../utils/supabase_manager.dart';

class NotificationService {
  final _supabase = SupabaseManager.client;

  Future<void> sendInvitation(
      String scheduleId, String userId, String roles) async {
    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'type': 'invitation',
        'data': {
          'schedule_id': scheduleId,
          'roles': roles,
          'status': 'pending',
        },
      });
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
          'message':
              'Please swap ${request.senderDay} with ${request.receiverDay}',
        },
      });
    } catch (e) {
      throw Exception('Failed to send permutation request: $e');
    }
  }

  Future<void> updatePermutationRequestStatus(
      String requestId, String status) async {
    try {
      await _supabase
          .from('permutation_requests')
          .update({'status': status}).eq('id', requestId);
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
