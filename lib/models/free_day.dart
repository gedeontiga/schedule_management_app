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
        'date': date.toIso8601String(),
        'start_time': startTime,
        'end_time': endTime,
      };

  factory FreeDay.fromJson(Map<String, dynamic> json) => FreeDay(
        day: json['day'],
        date: DateTime.parse(json['date']),
        startTime: json['start_time'] ?? '',
        endTime: json['end_time'] ?? '',
      );
}
