class FreeDay {
  final String day;
  final DateTime date;

  FreeDay({required this.day, required this.date});

  Map<String, dynamic> toJson() => {
        'day': day,
        'date': date.toIso8601String(),
      };

  factory FreeDay.fromJson(Map<String, dynamic> json) => FreeDay(
        day: json['day'],
        date: DateTime.parse(json['date']),
      );
}
