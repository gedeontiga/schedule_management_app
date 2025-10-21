import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/free_day.dart';
import '../../models/participant.dart';
import '../../models/schedule.dart';
import '../constants/app_colors.dart';
import '../utils/firebase_manager.dart';

class CalendarView extends StatefulWidget {
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
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView>
    with SingleTickerProviderStateMixin {
  DateTime? _selectedDay;
  late DateTime _focusedDay;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeFocusedDay();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _initializeFocusedDay() {
    final startDate = widget.schedule.startDate;
    final endDate = _getEndDate();
    final now = DateTime.now();

    // Focus on current date if it's within schedule range
    if (now.isAfter(startDate) && now.isBefore(endDate)) {
      _focusedDay = now;
    } else if (now.isBefore(startDate)) {
      // If schedule hasn't started, focus on start date
      _focusedDay = startDate;
    } else {
      // If schedule has ended, focus on end date
      _focusedDay = endDate;
    }
  }

  @override
  void didUpdateWidget(CalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only reset focus if schedule changed, not on free days update
    if (oldWidget.schedule.id != widget.schedule.id ||
        oldWidget.schedule.startDate != widget.schedule.startDate ||
        oldWidget.schedule.duration != widget.schedule.duration) {
      _initializeFocusedDay();
    }
    // Keep current focus when only free days are updated
    else if (oldWidget.freeDays.length != widget.freeDays.length) {
      // Don't change _focusedDay - keep current view
    }
  }

  DateTime _getEndDate() {
    int weeks = 0;
    switch (widget.schedule.duration) {
      case '1 week':
        weeks = 1;
        break;
      case '2 weeks':
        weeks = 2;
        break;
      case '3 weeks':
        weeks = 3;
        break;
      case '1 month':
        weeks = 4;
        break;
      case '2 months':
        weeks = 8;
        break;
      case '3 months':
        weeks = 12;
        break;
      case '6 months':
        weeks = 26;
        break;
      default:
        weeks = int.tryParse(widget.schedule.duration.split(' ')[0]) ?? 1;
    }
    return widget.schedule.startDate.add(Duration(days: weeks * 7));
  }

  Map<DateTime, List<Map<String, dynamic>>> _buildEventsMap() {
    final events = <DateTime, List<Map<String, dynamic>>>{};

    // Add my free days
    for (var day in widget.freeDays) {
      final date = DateTime(day.date.year, day.date.month, day.date.day);
      events[date] = [
        {
          'type': 'my',
          'time': '${day.startTime} - ${day.endTime}',
          'day': day,
        }
      ];
    }

    // Add other participants' days
    for (var participant in widget.participants) {
      if (participant.userId != FirebaseManager.currentUserId) {
        for (var day in participant.freeDays) {
          final date = DateTime(day.date.year, day.date.month, day.date.day);
          if (events.containsKey(date)) {
            events[date]!.add({
              'type': 'other',
              'time': '${day.startTime} - ${day.endTime}',
            });
          } else {
            events[date] = [
              {
                'type': 'other',
                'time': '${day.startTime} - ${day.endTime}',
              }
            ];
          }
        }
      }
    }

    return events;
  }

  Color _getCellColor(DateTime day, BuildContext context) {
    final events = _buildEventsMap();
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final dayEvents = events[normalizedDay];

    if (dayEvents == null || dayEvents.isEmpty) {
      return Colors.transparent;
    }

    final hasMyEvent = dayEvents.any((e) => e['type'] == 'my');
    final hasOtherEvent = dayEvents.any((e) => e['type'] == 'other');

    if (hasMyEvent && hasOtherEvent) {
      return AppColors.primary.withValues(alpha: 0.15);
    } else if (hasMyEvent) {
      return AppColors.primary.withValues(alpha: 0.1);
    } else {
      return AppColors.secondary.withValues(alpha: 0.08);
    }
  }

  List<Widget> _buildEventMarkers(DateTime day) {
    final events = _buildEventsMap();
    final normalizedDay = DateTime(day.year, day.month, day.day);
    final dayEvents = events[normalizedDay] ?? [];

    if (dayEvents.isEmpty) return [];

    final hasMyEvent = dayEvents.any((e) => e['type'] == 'my');
    final hasOtherEvent = dayEvents.any((e) => e['type'] == 'other');

    List<Widget> markers = [];

    if (hasMyEvent) {
      markers.add(
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 3,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    if (hasOtherEvent) {
      markers.add(
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: AppColors.secondary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.4),
                blurRadius: 3,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    return markers;
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    final dayOfWeek = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ][selectedDay.weekday % 7];

    if (widget.schedule.availableDays
        .any((availableDay) => availableDay.day == dayOfWeek)) {
      final availableDay =
          widget.schedule.availableDays.firstWhere((d) => d.day == dayOfWeek);

      final freeDay = FreeDay(
        day: dayOfWeek,
        date: selectedDay,
        startTime: availableDay.startTime,
        endTime: availableDay.endTime,
      );

      widget.onDaySelected(freeDay);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('$dayOfWeek is not available in this schedule'),
              ),
            ],
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _buildEventsMap();
    final endDate = _getEndDate();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.getSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with date range
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.secondary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.calendar_month,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Your Free Days',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.getTextPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${DateFormat('MMM d').format(widget.schedule.startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.getTextSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${widget.freeDays.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Calendar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TableCalendar(
              firstDay: widget.schedule.startDate,
              lastDay: endDate,
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: CalendarFormat.month,
              availableCalendarFormats: const {
                CalendarFormat.month: 'Month',
              },
              eventLoader: (day) {
                final normalizedDay = DateTime(day.year, day.month, day.day);
                return events[normalizedDay] ?? [];
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  final markers = _buildEventMarkers(day);
                  if (markers.isEmpty) return const SizedBox.shrink();

                  return Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: markers,
                    ),
                  );
                },
                defaultBuilder: (context, day, focusedDay) {
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _getCellColor(day, context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: AppColors.getTextPrimary(context),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _getCellColor(day, context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: AppColors.getTextPrimary(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
                outsideBuilder: (context, day, focusedDay) {
                  return Container(
                    margin: const EdgeInsets.all(4),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: AppColors.getTextSecondary(context)
                              .withValues(alpha: 0.3),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
              calendarStyle: CalendarStyle(
                cellMargin: const EdgeInsets.all(2),
                cellPadding: EdgeInsets.zero,
                weekendTextStyle: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                  color: AppColors.getTextPrimary(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: AppColors.primary,
                  size: 24,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: AppColors.primary,
                  size: 24,
                ),
                headerPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.getTextPrimary(context),
                ),
                weekendStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: AppColors.secondary,
                ),
              ),
              daysOfWeekHeight: 32,
              rowHeight: 52,
              onDaySelected: _onDaySelected,
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
            ),
          ),

          // Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.getBackground(context).withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem(context, 'My Days', AppColors.primary),
                const SizedBox(width: 24),
                _buildLegendItem(context, 'Others', AppColors.secondary),
                const SizedBox(width: 24),
                _buildLegendItem(
                  context,
                  'Today',
                  AppColors.secondary.withValues(alpha: 0.5),
                  borderColor: AppColors.secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(
    BuildContext context,
    String label,
    Color color, {
    Color? borderColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: borderColor != null
                ? Border.all(color: borderColor, width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.getTextSecondary(context),
          ),
        ),
      ],
    );
  }
}
