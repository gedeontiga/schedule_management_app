import 'dart:convert';
import 'free_day.dart';
import 'role.dart';

class Participant {
  final String? id;
  final String userId;
  final String scheduleId;
  final List<Role> roles;
  final List<FreeDay> freeDays;

  Participant({
    this.id,
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
    final freeDaysJson = freeDays.map((d) => d.toJson()).toList();
    try {
      jsonEncode(rolesJson);
      jsonEncode(freeDaysJson);
    } catch (e) {
      throw Exception('Failed to serialize roles or free days to JSON');
    }
    return {
      'user_id': userId,
      'schedule_id': scheduleId,
      'roles': rolesJson,
      'free_days': freeDaysJson,
    };
  }

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        userId: json['user_id'],
        scheduleId: json['schedule_id'],
        roles: (json['roles'] as List<dynamic>)
            .map((r) => Role.fromJson(r as Map<String, dynamic>))
            .toList(),
        freeDays: (json['free_days'] as List<dynamic>)
            .map((d) => FreeDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
