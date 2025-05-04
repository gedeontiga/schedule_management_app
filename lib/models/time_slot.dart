class TimeSlot {
  final String startTime;
  final String endTime;

  TimeSlot({required this.startTime, required this.endTime});

  int get startMinutes => _timeToMinutes(startTime);
  int get endMinutes => _timeToMinutes(endTime);

  bool overlaps(TimeSlot other) {
    return startMinutes < other.endMinutes && endMinutes > other.startMinutes;
  }

  static int _timeToMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    final parts = timeString.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  @override
  String toString() => '$startTime-$endTime';
}
