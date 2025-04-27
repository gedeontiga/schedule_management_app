import 'dart:convert';
import 'participant.dart';

class Schedule {
  final String id;
  final String name;
  final String? description;
  final List<String> availableDays;
  final String duration;
  final String ownerId;
  final List<Participant> participants;
  final bool isFullySet;

  Schedule({
    required this.id,
    required this.name,
    this.description,
    required this.availableDays,
    required this.duration,
    required this.ownerId,
    required this.participants,
    required this.isFullySet,
  });

  Map<String, dynamic> toJson() {
    final participantsJson = participants.map((p) => p.toJson()).toList();
    try {
      jsonEncode(participantsJson);
    } catch (e) {
      // print('Invalid JSON for participants: $e');
      throw Exception('Failed to serialize participants to JSON');
    }

    return {
      'id': id,
      'name': name,
      'description': description,
      'available_days': availableDays,
      'duration': duration,
      'owner_id': ownerId,
      'participants': participantsJson,
      'is_fully_set': isFullySet,
    };
  }

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        availableDays: List<String>.from(json['available_days']),
        duration: json['duration'],
        ownerId: json['owner_id'],
        participants: (json['participants'] as List<dynamic>)
            .map((p) => Participant.fromJson(p as Map<String, dynamic>))
            .toList(),
        isFullySet: json['is_fully_set'],
      );
}
