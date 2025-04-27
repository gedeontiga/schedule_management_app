import 'dart:convert';
import 'role.dart';

class Participant {
  final String userId;
  final String scheduleId;
  final List<Role> roles;
  final List<String> freeDays;

  Participant({
    required this.userId,
    required this.scheduleId,
    required this.roles,
    required this.freeDays,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(userId)) {
      throw ArgumentError('Invalid userId format');
    }
    if (!RegExp(r'^[a-zA-Z0-9\-]+$').hasMatch(scheduleId)) {
      throw ArgumentError('Invalid scheduleId format');
    }
  }

  Map<String, dynamic> toJson() {
    final rolesJson = roles.map((r) => r.toJson()).toList();
    try {
      jsonEncode(rolesJson);
    } catch (e) {
      // print('Invalid JSON for roles: $e');
      throw Exception('Failed to serialize roles to JSON');
    }

    return {
      'user_id': userId,
      'schedule_id': scheduleId,
      'roles': rolesJson,
      'free_days': freeDays,
    };
  }

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        userId: json['user_id'],
        scheduleId: json['schedule_id'],
        roles: (json['roles'] as List<dynamic>)
            .map((r) => Role.fromJson(r as Map<String, dynamic>))
            .toList(),
        freeDays: List<String>.from(json['free_days']),
      );
}
