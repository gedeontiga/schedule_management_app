import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/free_day.dart';
import '../../models/participant.dart';
import '../../models/schedule.dart';
import '../constants/app_colors.dart';
import '../utils/firebase_manager.dart';

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
    final startDate = schedule.startDate;
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

    final focusedDay =
        DateTime.now().isAfter(startDate) && DateTime.now().isBefore(endDate)
            ? DateTime.now()
            : startDate;

    final events = _buildEventsMap();
    final selectedDayNotifier = ValueNotifier<DateTime?>(null);

    return LayoutBuilder(builder: (context, constraints) {
      // Adjust calendar height based on available space
      final availableHeight = constraints.maxHeight;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d').format(endDate)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: TableCalendar(
                  firstDay: startDate,
                  lastDay: endDate,
                  focusedDay: focusedDay,
                  calendarFormat: CalendarFormat.month,
                  availableCalendarFormats: const {
                    CalendarFormat.month: 'Month',
                  },
                  eventLoader: (day) => events[day] ?? [],
                  calendarStyle: CalendarStyle(
                    markerDecoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    markerSize: 4, // Reduced marker size
                    markersMaxCount: 2,
                    todayDecoration: BoxDecoration(
                      color: AppColors.secondary.withAlpha(150),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle:
                        TextStyle(color: Colors.white, fontSize: 11),
                    selectedTextStyle:
                        TextStyle(color: Colors.white, fontSize: 11),
                    weekendTextStyle:
                        TextStyle(color: AppColors.secondary, fontSize: 11),
                    defaultTextStyle: TextStyle(fontSize: 11),
                    outsideTextStyle: TextStyle(
                      color: AppColors.textSecondary
                          .withValues(alpha: 128), // Fixed deprecation
                      fontSize: 10,
                    ),
                    cellMargin: EdgeInsets.all(1), // Reduced cell margin
                    cellPadding: EdgeInsets.zero, // Removed cell padding
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    leftChevronIcon: Icon(Icons.chevron_left,
                        size: 18, color: AppColors.primary),
                    rightChevronIcon: Icon(Icons.chevron_right,
                        size: 18, color: AppColors.primary),
                    headerMargin:
                        EdgeInsets.only(bottom: 6), // Reduced header margin
                    headerPadding: EdgeInsets.symmetric(
                        vertical: 2), // Reduced header padding
                    // Responsive title formatting
                    formatButtonShowsNext: false,
                    titleTextFormatter: (date, locale) {
                      return DateFormat.yMMM(locale).format(date);
                    },
                  ),
                  daysOfWeekStyle: DaysOfWeekStyle(
                    weekdayStyle: TextStyle(fontSize: 10),
                    weekendStyle:
                        TextStyle(fontSize: 10, color: AppColors.secondary),
                    decoration: BoxDecoration(color: Colors.transparent),
                  ),
                  // Set days of week height based on available space
                  daysOfWeekHeight: availableHeight < 400 ? 16 : 20,
                  // Use available calendar height efficiently
                  rowHeight: availableHeight < 400 ? 36 : 42,
                  sixWeekMonthsEnforced:
                      false, // Allow fewer weeks to be shown when possible
                  shouldFillViewport: false, // Don't force full height
                  onDaySelected: (selectedDay, focusedDay) {
                    selectedDayNotifier.value = selectedDay;
                    final dayOfWeek = [
                      'Sunday',
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday'
                    ][selectedDay.weekday % 7];

                    if (schedule.availableDays
                        .any((availableDay) => availableDay.day == dayOfWeek)) {
                      final availableDay = schedule.availableDays
                          .firstWhere((d) => d.day == dayOfWeek);

                      final freeDay = FreeDay(
                        day: dayOfWeek,
                        date: selectedDay,
                        startTime: availableDay.startTime,
                        endTime: availableDay.endTime,
                      );

                      onDaySelected(freeDay);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '$dayOfWeek is not available in this schedule'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildLegendItem('My', AppColors.primary),
                    const SizedBox(width: 8),
                    _buildLegendItem('Others', AppColors.secondary),
                  ],
                ),
                ValueListenableBuilder<DateTime?>(
                  valueListenable: selectedDayNotifier,
                  builder: (context, selectedDate, _) {
                    if (selectedDate == null) return const SizedBox.shrink();

                    return Text(
                      DateFormat('MMM d').format(selectedDate),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Map<DateTime, List<String>> _buildEventsMap() {
    final events = <DateTime, List<String>>{};

    for (var day in freeDays) {
      final date = DateTime(day.date.year, day.date.month, day.date.day);
      events[date] = ['My day: ${day.startTime} - ${day.endTime}'];
    }

    for (var participant in participants) {
      if (participant.userId != FirebaseManager.currentUserId) {
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

    return events;
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: TextStyle(fontSize: 11)),
      ],
    );
  }
}
