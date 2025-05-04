class AvailableDay {
  final String day;
  final String startTime;
  final String endTime;

  AvailableDay(
      {required this.day, required this.startTime, required this.endTime});

  Map<String, dynamic> toJson() => {
        'day': day,
        'start_time': startTime,
        'end_time': endTime,
      };

  factory AvailableDay.fromJson(Map<String, dynamic> json) => AvailableDay(
        day: json['day'],
        startTime: json['start_time'],
        endTime: json['end_time'],
      );
}
