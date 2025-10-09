import 'package:cloud_firestore/cloud_firestore.dart';

class FreeDay {
  final String day;
  final DateTime date;
  final String startTime;
  final String endTime;

  FreeDay({
    required this.day,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toJson() => {
        'day': day,
        'date': Timestamp.fromDate(date),
        'start_time': startTime,
        'end_time': endTime,
      };

  factory FreeDay.fromJson(Map<String, dynamic> json) => FreeDay(
        day: json['day'],
        date: (json['date'] as Timestamp).toDate(),
        startTime: json['start_time'] ?? '',
        endTime: json['end_time'] ?? '',
      );
}
