// services/notification_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/permutation_request.dart';
import '../utils/firebase_manager.dart';

class NotificationService {
  final _functions = FirebaseFunctions.instance;

  Future<void> sendInvitation(
      String scheduleId, String userId, String roles) async {
    try {
      final callable = _functions.httpsCallable('sendInvitation');
      await callable.call({
        'scheduleId': scheduleId,
        'userId': userId,
        'roles': roles,
      });
    } catch (e) {
      throw Exception('Failed to send invitation: $e');
    }
  }

  Future<void> updateInvitationStatus(
      String notificationId, String status) async {
    try {
      final callable = _functions.httpsCallable('updateInvitationStatus');
      await callable.call({
        'notificationId': notificationId,
        'status': status,
      });
    } catch (e) {
      throw Exception('Failed to update invitation status: $e');
    }
  }

  Future<void> sendPermutationRequest(PermutationRequest request) async {
    try {
      final callable = _functions.httpsCallable('sendPermutationRequest');
      await callable.call(request.toJson());
    } catch (e) {
      throw Exception('Failed to send permutation request: $e');
    }
  }

  Future<void> updatePermutationRequestStatus(String requestId, String status,
      String scheduleId, String senderId, String receiverId) async {
    try {
      final callable =
          _functions.httpsCallable('updatePermutationRequestStatus');
      await callable.call({
        'requestId': requestId,
        'status': status,
        'scheduleId': scheduleId,
        'senderId': senderId,
        'receiverId': receiverId,
      });
    } catch (e) {
      throw Exception('Failed to update permutation request: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getNotifications(String userId) {
    return FirebaseManager.firestore
        .collection('notifications')
        .where('user_id', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }
}
