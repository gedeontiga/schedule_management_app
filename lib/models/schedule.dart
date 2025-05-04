import 'available_day.dart';
import 'participant.dart';

class Schedule {
  final String id;
  final String name;
  final String? description;
  final List<AvailableDay> availableDays;
  final String duration;
  final String ownerId;
  final List<Participant> participants;
  final bool isFullySet;
  final DateTime createdAt;
  final DateTime startDate;

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
    required this.startDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'available_days': availableDays.map((d) => d.toJson()).toList(),
      'duration': duration,
      'owner_id': ownerId,
      'participants': participants.map((p) => p.toJson()).toList(),
      'is_fully_set': isFullySet,
      'created_at': createdAt.toIso8601String(),
      'start_date': startDate.toIso8601String(),
    };
  }

  factory Schedule.fromJson(Map<String, dynamic> json) {
    return Schedule(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      availableDays: (json['available_days'] as List<dynamic>)
          .map((d) => AvailableDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      duration: json['duration'],
      ownerId: json['owner_id'],
      participants: (json['participants'] as List<dynamic>?)
              ?.map((p) => Participant.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      isFullySet: json['is_fully_set'],
      createdAt: DateTime.parse(json['created_at']),
      startDate: DateTime.parse(json['start_date']),
    );
  }

  Schedule copyWith({
    String? id,
    String? name,
    String? description,
    List<AvailableDay>? availableDays,
    String? duration,
    String? ownerId,
    List<Participant>? participants,
    bool? isFullySet,
    DateTime? createdAt,
    DateTime? startDate,
  }) {
    return Schedule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      availableDays: availableDays ?? this.availableDays,
      duration: duration ?? this.duration,
      ownerId: ownerId ?? this.ownerId,
      participants: participants ?? this.participants,
      isFullySet: isFullySet ?? this.isFullySet,
      createdAt: createdAt ?? this.createdAt,
      startDate: startDate ?? this.startDate,
    );
  }
}
