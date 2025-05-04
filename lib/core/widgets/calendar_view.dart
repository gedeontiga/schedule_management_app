import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/free_day.dart';
import '../../models/participant.dart';
import '../../models/schedule.dart';
import '../constants/app_colors.dart';
import '../utils/supabase_manager.dart';

class CalendarView extends StatelessWidget {
  final Schedule schedule;
  final List<FreeDay> freeDays;
  final List<Participant> participants;
  final Function(FreeDay) onDaySelected;

  const CalendarView({
    super.key,
    required this.schedule,
    required this.freeDays,
    required this.participants,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate first and last day of the schedule
    final startDate = schedule.createdAt;
    int weeks = 0;

    switch (schedule.duration) {
      case '1 week':
        weeks = 1;
        break;
      case '2 weeks':
        weeks = 2;
        break;
      case '1 month':
        weeks = 5;
        break;
      default:
        weeks = int.parse(schedule.duration.split(' ')[0]);
    }

    final endDate = startDate.add(Duration(days: weeks * 7));

    // Create event markers for free days
    final events = {
      for (var day in freeDays)
        DateTime(day.date.year, day.date.month, day.date.day): [
          'My day: ${day.startTime} - ${day.endTime}'
        ],
    };

    // Add other participants' days
    for (var participant in participants) {
      if (participant.userId != SupabaseManager.getCurrentUserId()) {
        for (var day in participant.freeDays) {
          final date = DateTime(day.date.year, day.date.month, day.date.day);
          if (events.containsKey(date)) {
            events[date]!.add('Other: ${day.startTime} - ${day.endTime}');
          } else {
            events[date] = ['Other: ${day.startTime} - ${day.endTime}'];
          }
        }
      }
    }

    return Column(
      children: [
        TableCalendar(
          firstDay: startDate,
          lastDay: endDate,
          focusedDay: DateTime.now().isAfter(startDate) &&
                  DateTime.now().isBefore(endDate)
              ? DateTime.now()
              : startDate,
          calendarFormat: CalendarFormat.month,
          eventLoader: (day) => events[day] ?? [],
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            todayDecoration: BoxDecoration(
              color: AppColors.secondary.withAlpha(150),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          onDaySelected: (selectedDay, focusedDay) {
            // Create a FreeDay object from the selected date and pass to callback
            final dayOfWeek = [
              'Sunday',
              'Monday',
              'Tuesday',
              'Wednesday',
              'Thursday',
              'Friday',
              'Saturday'
            ][selectedDay.weekday % 7];

            // Only allow selection of days that are in the schedule's available days
            if (schedule.availableDays
                .any((availableDay) => availableDay.day == dayOfWeek)) {
              final availableDay =
                  schedule.availableDays.firstWhere((d) => d.day == dayOfWeek);

              final freeDay = FreeDay(
                day: dayOfWeek,
                date: selectedDay,
                startTime: availableDay.startTime,
                endTime: availableDay.endTime,
              );

              onDaySelected(freeDay);
            }
          },
        ),
      ],
    );
  }
}
