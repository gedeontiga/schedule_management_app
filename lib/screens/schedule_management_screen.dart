import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scheduling_management_app/core/utils/supabase_manager.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../core/constants/app_colors.dart';
import '../core/services/permission_service.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/pdf_service.dart';
import '../core/widgets/info_tile.dart';
import '../models/free_day.dart';
import '../models/participant.dart';
import '../models/schedule.dart';
import '../models/permutation_request.dart';

class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});
  @override
  ScheduleManagementScreenState createState() =>
      ScheduleManagementScreenState();
}

class ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  final ScheduleService _scheduleService = ScheduleService();
  final NotificationService _notificationService = NotificationService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  late StreamSubscription<Schedule> _scheduleSubscription;
  Schedule? _schedule;
  List<FreeDay> _freeDays = [];
  String? _selectedDay1;
  String? _selectedDay2;
  bool _isLoading = false;
  final Map<String, String> _alarms = {};
  bool _hasFetchedSchedule = false;
  List<Participant> _participants = [];
  late StreamSubscription<List<Participant>> _participantSubscription;
  String? _scheduleId; // Store scheduleId temporarily

  @override
  void initState() {
    super.initState();

    // Initialize with correct types
    _participantSubscription = Stream<List<Participant>>.empty().listen((_) {});
    _scheduleSubscription = Stream<Schedule>.empty().listen((_) {});

    _scheduleService.permutationRequestStream.listen((payload) async {
      if (payload['eventType'] == 'UPDATE' &&
          payload['new']['status'] == 'accepted') {
        await _fetchSchedule();
      }
    });

    _scheduleService.notificationStream.listen((payload) {
      if (payload['type'] == 'free_days_updated' &&
          payload['data']['schedule_id'] == _scheduleId) {
        _fetchSchedule();
      }

      if (payload['type'] == 'schedule_status_updated' &&
          payload['data']['schedule_id'] == _scheduleId) {
        _fetchSchedule();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasFetchedSchedule) {
      _hasFetchedSchedule = true;
      // Access ModalRoute here instead of initState
      _scheduleId = ModalRoute.of(context)!.settings.arguments as String;
      _fetchSchedule();
    }
  }

  Future<void> _updateFreeDays() async {
    setState(() => _isLoading = true);
    try {
      if (!await _scheduleService.validateFreeDays(
          _schedule!.id, SupabaseManager.getCurrentUserId()!, _freeDays)) {
        throw Exception('Selected days are not available or already taken');
      }
      await _scheduleService.updateFreeDays(
        _schedule!.id,
        SupabaseManager.getCurrentUserId()!,
        _freeDays,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Free days updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPermutation() async {
    if (_selectedDay1 == null || _selectedDay2 == null) return;
    setState(() => _isLoading = true);
    try {
      final request = PermutationRequest(
        id: const Uuid().v4(),
        senderId: SupabaseManager.getCurrentUserId()!,
        receiverId: _schedule!.participants
            .firstWhere((p) => p.userId != SupabaseManager.getCurrentUserId()!)
            .userId,
        scheduleId: _schedule!.id,
        senderDay: _selectedDay1!,
        receiverDay: _selectedDay2!,
      );
      await _notificationService.sendPermutationRequest(request);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permutation request sent')),
        );
      }
      setState(() {
        _selectedDay1 = null;
        _selectedDay2 = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _setAlarm(FreeDay day) async {
    final selectedAlarm = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface.withValues(alpha: 0.95),
        title: Text(
            'Set Alarm for ${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['1h', '2h', '24h']
              .map((duration) => ListTile(
                    title: Text('$duration before'),
                    onTap: () => Navigator.pop(context, duration),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selectedAlarm != null) {
      final key = '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}';
      setState(() {
        _alarms[key] = selectedAlarm;
      });
      final alarmBox = Hive.box('alarms');
      await alarmBox.put(key, selectedAlarm);
      final hours = int.parse(selectedAlarm.replaceAll('h', ''));
      final notificationTime = tz.TZDateTime.from(
        day.date.subtract(Duration(hours: hours)),
        tz.local,
      );
      await _notificationsPlugin.zonedSchedule(
        key.hashCode,
        'Schedule Reminder',
        'Reminder for your schedule on ${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})',
        notificationTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'schedule_reminder',
            'Schedule Reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> _exportPdf() async {
    if (!_schedule!.isFullySet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule is not fully set')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final pdfService = PdfService();

      try {
        final file = await pdfService.generateSchedulePdf(_schedule!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('PDF exported to ${file.path}'),
              action: SnackBarAction(
                label: 'OPEN',
                onPressed: () async {
                  final openResult = await OpenFile.open(file.path);
                  if (openResult.type != ResultType.done) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                'Error opening file: ${openResult.message}')),
                      );
                    }
                  }
                },
              ),
            ),
          );
        }
      } on PlatformException catch (e) {
        if (e.code == 'PERMISSION_DENIED') {
          final permissionService = PermissionService();
          final status = await permissionService.requestStoragePermission();

          if (status == PermissionStatus.permanentlyDenied && mounted) {
            // Show a dialog explaining why we need permission and how to grant it
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Storage Permission Required'),
                content: const Text(
                    'To save PDF files, we need permission to access your device storage. '
                    'Please grant this permission in your device settings.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await permissionService.openAppSettings();
                    },
                    child: const Text('OPEN SETTINGS'),
                  ),
                ],
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Storage permission is required to save PDF files')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.message}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<List<FreeDay>> _getWeeklyAvailableDays() {
    if (_schedule == null) return [];

    final daysOfWeek = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final startDate = _schedule!.createdAt;
    int weeks = 0;

    switch (_schedule!.duration) {
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
        weeks = int.parse(_schedule!.duration.split(' ')[0]);
    }

    final weeklyDays = <List<FreeDay>>[];

    // Get days taken by other participants (excluding the current user)
    final otherParticipantsTakenDates = _participants
        .where((p) => p.userId != SupabaseManager.getCurrentUserId())
        .expand((p) => p.freeDays)
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toSet();

    // Get days taken by current user
    final currentUserFreeDays = _participants
        .firstWhere(
          (p) => p.userId == SupabaseManager.getCurrentUserId(),
          orElse: () => Participant(
            userId: SupabaseManager.getCurrentUserId()!,
            scheduleId: _scheduleId!,
            roles: [],
            freeDays: [],
          ),
        )
        .freeDays;

    final currentUserTakenDates = currentUserFreeDays
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toSet();

    for (var week = 0; week < weeks; week++) {
      final weekStart = startDate.add(Duration(days: week * 7));
      final weekDays = <FreeDay>[];

      for (var date = weekStart;
          date.isBefore(weekStart.add(Duration(days: 7)));
          date = date.add(Duration(days: 1))) {
        final dayName = daysOfWeek[date.weekday - 1];
        final normalizedDate = DateTime(date.year, date.month, date.day);

        // Show all available days for the current user's schedule
        if (_schedule!.availableDays.contains(dayName)) {
          // For days the current user has already selected, show them so they can be unselected
          if (currentUserTakenDates.contains(normalizedDate)) {
            final existingDay = currentUserFreeDays.firstWhere((d) =>
                d.date.year == normalizedDate.year &&
                d.date.month == normalizedDate.month &&
                d.date.day == normalizedDate.day);
            weekDays.add(existingDay);
          }
          // For days not taken by other participants, show them as available
          else if (!otherParticipantsTakenDates.contains(normalizedDate)) {
            weekDays.add(FreeDay(
              day: dayName,
              date: normalizedDate,
            ));
          }
        }
      }

      weeklyDays.add(weekDays);
    }

    return weeklyDays;
  }

// Fix for _fetchSchedule() method in ScheduleManagementScreenState class
  Future<void> _fetchSchedule() async {
    setState(() => _isLoading = true);
    try {
      final schedules = await _scheduleService
          .getUserSchedules(SupabaseManager.getCurrentUserId()!)
          .timeout(const Duration(seconds: 10));

      if (schedules.isEmpty) {
        throw Exception('No schedules found for this user');
      }

      _schedule = schedules.firstWhere(
        (s) => s.id == _scheduleId,
        orElse: () =>
            throw Exception('Schedule with ID $_scheduleId not found'),
      );

      final currentParticipant = _schedule!.participants.firstWhere(
        (p) => p.userId == SupabaseManager.getCurrentUserId()!,
      );

      _freeDays = currentParticipant.freeDays;
      _participants = _schedule!.participants;

      try {
        _participantSubscription.cancel();
        _scheduleSubscription.cancel();
      } catch (e) {
        // ignore
      }

      _participantSubscription = _scheduleService
          .getParticipantStream(_scheduleId!)
          .listen((participants) {
        setState(() {
          _participants = participants;

          final currentUser = participants.firstWhere(
            (p) => p.userId == SupabaseManager.getCurrentUserId()!,
            orElse: () => Participant(
              userId: SupabaseManager.getCurrentUserId()!,
              scheduleId: _scheduleId!,
              roles: [],
              freeDays: [],
            ),
          );
          _freeDays = currentUser.freeDays;

          if (_schedule != null) {
            _schedule = _schedule!.copyWith(participants: participants);
          }
        });
      });

      _scheduleSubscription =
          _scheduleService.getScheduleStream(_scheduleId!).listen((schedule) {
        setState(() {
          _schedule = schedule;
        });
      });

      // Listen for free days updates
      _scheduleService.notificationStream.listen((payload) {
        if (payload['type'] == 'free_days_updated' &&
            payload['data']['schedule_id'] == _scheduleId) {
          // Force refresh of available days
          setState(() {});
        }
      });

      final alarmBox = Hive.box('alarms');
      _alarms.addAll(alarmBox.toMap().cast<String, String>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading schedule: $e')),
        );
        Navigator.pop(context);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _participantSubscription.cancel();
    _scheduleSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_schedule == null) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withAlpha(26),
                AppColors.background,
              ],
            ),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final weeklyAvailableDays = _getWeeklyAvailableDays();

    return Scaffold(
      appBar: AppBar(
        title: Text(_schedule!.name,
            style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.6),
                AppColors.secondary.withValues(alpha: 0.5)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download, color: AppColors.textOnPrimary),
            tooltip: 'Export as PDF',
            onPressed: _schedule!.isFullySet ? _exportPdf : null,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withAlpha(13),
              AppColors.secondary.withAlpha(13),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.event_available,
                                      color: AppColors.primary, size: 28),
                                  SizedBox(width: 12),
                                  Text(
                                    'Select Your Free Days',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Spacer(),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withAlpha(52),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_freeDays.length}/${_schedule!.availableDays.length * weeklyAvailableDays.length}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Text(
                                _schedule!.isFullySet
                                    ? 'Schedule is fully set. You can modify your free days.'
                                    : 'Select your available days for each week:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              SizedBox(height: 20),
                              ...weeklyAvailableDays
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final weekIndex = entry.key;
                                final weekDays = entry.value;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Week ${weekIndex + 1}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: weekDays.map((day) {
                                        final isSelected = _freeDays
                                            .any((d) => d.date == day.date);
                                        final hasAlarm = _alarms.containsKey(
                                            '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}');
                                        return GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              if (isSelected) {
                                                _freeDays.removeWhere(
                                                    (d) => d.date == day.date);
                                                _alarms.remove(
                                                    '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}');
                                              } else {
                                                _freeDays.add(day);
                                                _setAlarm(day);
                                              }
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration:
                                                Duration(milliseconds: 300),
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withAlpha(26),
                                                  blurRadius: 6,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Stack(
                                              children: [
                                                Column(
                                                  children: [
                                                    Text(
                                                      day.day,
                                                      style: TextStyle(
                                                        color: isSelected
                                                            ? AppColors
                                                                .textOnPrimary
                                                            : AppColors
                                                                .textPrimary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      DateFormat('dd-MM-yy')
                                                          .format(day.date),
                                                      style: TextStyle(
                                                        color: isSelected
                                                            ? AppColors
                                                                .textOnPrimary
                                                                .withAlpha(204)
                                                            : AppColors
                                                                .textSecondary,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (hasAlarm)
                                                  Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    child: Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration: BoxDecoration(
                                                        color: Colors.red,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    SizedBox(height: 16),
                                  ],
                                );
                              }),
                              SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: GradientButton(
                                      text: 'Save Free Days',
                                      onPressed: _updateFreeDays,
                                      isLoading: _isLoading,
                                      icon: Icons.save,
                                    ),
                                  ),
                                  if (_freeDays.isNotEmpty) ...[
                                    SizedBox(width: 12),
                                    IconButton(
                                      icon: Icon(Icons.alarm,
                                          color: AppColors.primary),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: Text('Configured Alarms'),
                                            content: SizedBox(
                                              width: double.maxFinite,
                                              child: ListView.builder(
                                                shrinkWrap: true,
                                                itemCount: _alarms.length,
                                                itemBuilder: (context, index) {
                                                  final key = _alarms.keys
                                                      .elementAt(index);
                                                  final duration =
                                                      _alarms[key] ?? '';
                                                  final parts = key.split('_');
                                                  final day = parts[0];
                                                  final date = parts[1];
                                                  return ListTile(
                                                    title: Text('$day ($date)'),
                                                    subtitle: Text(
                                                        '$duration before'),
                                                    trailing: IconButton(
                                                      icon: Icon(Icons.delete),
                                                      onPressed: () {
                                                        setState(() {
                                                          _alarms.remove(key);
                                                        });
                                                        Navigator.pop(context);
                                                      },
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: Text('Close'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      tooltip: 'Manage Alarms',
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.swap_horiz,
                                      color: AppColors.primary, size: 28),
                                  SizedBox(width: 12),
                                  Text(
                                    'Request Schedule Swap',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Swap one of your days with another participant:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Your Day:',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w500),
                                        ),
                                        SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                                Icons.calendar_today,
                                                color: AppColors.primary),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          value: _selectedDay1,
                                          hint: Text('Select your day'),
                                          items: _freeDays
                                              .map((day) =>
                                                  DropdownMenuItem<String>(
                                                    value:
                                                        '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                                    child: Text(
                                                        '${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedDay1 = value;
                                            });
                                          },
                                          isExpanded: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Icon(Icons.swap_horiz,
                                      color: AppColors.primary),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Their Day:',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w500),
                                        ),
                                        SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                                Icons.calendar_today,
                                                color: AppColors.primary),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          value: _selectedDay2,
                                          hint: Text('Select their day'),
                                          items: weeklyAvailableDays
                                              .expand((week) => week)
                                              .where((day) => !_freeDays.any(
                                                  (d) => d.date == day.date))
                                              .map((day) =>
                                                  DropdownMenuItem<String>(
                                                    value:
                                                        '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                                    child: Text(
                                                        '${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
                                                  ))
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedDay2 = value;
                                            });
                                          },
                                          isExpanded: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              GradientButton(
                                text: 'Send Swap Request',
                                onPressed: _requestPermutation,
                                isLoading: _isLoading,
                                icon: Icons.send,
                                enabled: _selectedDay1 != null &&
                                    _selectedDay2 != null,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: AppColors.primary, size: 28),
                                  SizedBox(width: 12),
                                  Text(
                                    'Schedule Information',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              InfoTile(
                                icon: Icons.description,
                                label: 'Description',
                                value:
                                    _schedule!.description ?? 'No description',
                              ),
                              InfoTile(
                                icon: Icons.access_time,
                                label: 'Duration',
                                value: _schedule!.duration,
                              ),
                              InfoTile(
                                icon: Icons.calendar_today,
                                label: 'Created At',
                                value: DateFormat('yyyy-MM-dd')
                                    .format(_schedule!.createdAt),
                              ),
                              InfoTile(
                                icon: Icons.group,
                                label: 'Participants',
                                value: '${_schedule!.participants.length}',
                              ),
                              InfoTile(
                                icon: Icons.check_circle_outline,
                                label: 'Status',
                                value: _schedule!.isFullySet
                                    ? 'Fully Set'
                                    : 'Pending',
                                valueColor: _schedule!.isFullySet
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              SizedBox(height: 20),
                              GradientButton(
                                text: 'Export Schedule as PDF',
                                onPressed: _exportPdf,
                                isLoading: _isLoading,
                                icon: Icons.picture_as_pdf,
                                enabled: _schedule!.isFullySet,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
