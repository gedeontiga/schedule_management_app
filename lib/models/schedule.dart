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
  final DateTime createdAt;

  Schedule({
    required this.id,
    required this.name,
    this.description,
    required this.availableDays,
    required this.duration,
    required this.ownerId,
    required this.participants,
    required this.isFullySet,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    final participantsJson = participants.map((p) => p.toJson()).toList();
    try {
      jsonEncode(participantsJson);
    } catch (e) {
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
      'created_at': createdAt.toIso8601String(),
    };
  }

  Schedule copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    List<String>? availableDays,
    String? duration,
    List<Participant>? participants,
    bool? isFullySet,
    DateTime? createdAt,
  }) {
    return Schedule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      availableDays: availableDays ?? this.availableDays,
      duration: duration ?? this.duration,
      participants: participants ?? this.participants,
      isFullySet: isFullySet ?? this.isFullySet,
      createdAt: createdAt ?? this.createdAt,
    );
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
        createdAt: DateTime.parse(json['created_at']),
      );
}
