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
import '../core/widgets/calendar_view.dart';
import '../models/time_slot.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/pdf_service.dart';
import '../core/widgets/info_tile.dart';
import '../models/available_day.dart';
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
  StreamSubscription<Schedule?>? _scheduleSubscription;
  Schedule? _schedule;
  List<FreeDay> _freeDays = [];
  String? _selectedDay1;
  String? _selectedDay2;
  bool _isLoading = false;
  final Map<String, String> _alarms = {};
  bool _hasFetchedSchedule = false;
  bool _showCalendarView = false;
  List<Participant> _participants = [];
  StreamSubscription<List<Participant>>? _participantSubscription;
  String? _scheduleId;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  List<List<FreeDay>> _availableWeeklyDays = [];
  Map<String, List<TimeSlot>> _availableTimeSlots = {};
  List<Map<String, dynamic>> _pendingPermutationRequests = [];
  bool _showPermutationRequestPopup = false;
  Map<String, dynamic>? _currentPermutationRequest;

  @override
  void initState() {
    super.initState();
    _scheduleService.permutationRequestStream.listen((payload) async {
      if (payload['eventType'] == 'UPDATE' &&
          payload['new']['status'] == 'accepted') {
        await _fetchSchedule();
      }
      if (payload['eventType'] == 'INSERT' &&
          payload['new']['receiver_id'] == SupabaseManager.getCurrentUserId() &&
          payload['new']['schedule_id'] == _scheduleId) {
        await _fetchPendingPermutationRequests();
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
      if (payload['type'] == 'permutation_request' &&
          payload['data']['schedule_id'] == _scheduleId) {
        _fetchPendingPermutationRequests();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasFetchedSchedule) {
      _hasFetchedSchedule = true;

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

  Future<void> _handlePermutationResponse(String status) async {
    if (_currentPermutationRequest == null || _schedule == null) return;
    setState(() => _isLoading = true);
    try {
      final requestId = _currentPermutationRequest!['id'];
      final scheduleId = _currentPermutationRequest!['schedule_id'];
      final senderId = _currentPermutationRequest!['sender_id'];
      final receiverId = _currentPermutationRequest!['receiver_id'];

      await _notificationService.updatePermutationRequestStatus(
        requestId,
        status,
        scheduleId,
        senderId,
        receiverId,
      );

      if (status == 'accepted') {
        final senderDay = _currentPermutationRequest!['sender_day'];
        final receiverDay = _currentPermutationRequest!['receiver_day'];
        final senderDayParts = senderDay.split('_');
        final receiverDayParts = receiverDay.split('_');
        final senderDayName = senderDayParts[0];
        final senderDayDate = DateTime.parse(senderDayParts[1]);
        final receiverDayName = receiverDayParts[0];
        final receiverDayDate = DateTime.parse(receiverDayParts[1]);

        final currentUser = _participants.firstWhere(
          (p) => p.userId == SupabaseManager.getCurrentUserId()!,
          orElse: () => throw Exception('Current user not found'),
        );
        final requester = _participants.firstWhere(
          (p) => p.userId == senderId,
          orElse: () => throw Exception('Requester not found'),
        );

        final myDayToGive = currentUser.freeDays.firstWhere(
          (d) =>
              d.day == receiverDayName &&
              d.date.year == receiverDayDate.year &&
              d.date.month == receiverDayDate.month &&
              d.date.day == receiverDayDate.day,
          orElse: () => throw Exception('Receiver day not found'),
        );
        final theirDayToGive = requester.freeDays.firstWhere(
          (d) =>
              d.day == senderDayName &&
              d.date.year == senderDayDate.year &&
              d.date.month == senderDayDate.month &&
              d.date.day == senderDayDate.day,
          orElse: () => throw Exception('Sender day not found'),
        );

        final myNewFreeDays = currentUser.freeDays
            .where((d) => d.date != myDayToGive.date)
            .toList()
          ..add(theirDayToGive);
        final theirNewFreeDays = requester.freeDays
            .where((d) => d.date != theirDayToGive.date)
            .toList()
          ..add(myDayToGive);

        await _scheduleService.updateFreeDays(
          scheduleId,
          SupabaseManager.getCurrentUserId()!,
          myNewFreeDays,
        );
        await _scheduleService.updateFreeDays(
          scheduleId,
          senderId,
          theirNewFreeDays,
        );
      }

      setState(() {
        _showPermutationRequestPopup = false;
        _currentPermutationRequest = null;
      });
      await _fetchPendingPermutationRequests();
      await _fetchSchedule();
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

  Future<void> _fetchPendingPermutationRequests() async {
    try {
      final userId = SupabaseManager.getCurrentUserId();
      if (userId == null || _scheduleId == null) return;
      final requests = await _scheduleService.supabase
          .from('permutation_requests')
          .select()
          .eq('receiver_id', userId)
          .eq('schedule_id', _scheduleId!)
          .eq('status', 'pending');

      setState(() {
        _pendingPermutationRequests = List<Map<String, dynamic>>.from(requests);
        if (_pendingPermutationRequests.isNotEmpty &&
            !_showPermutationRequestPopup) {
          _currentPermutationRequest = _pendingPermutationRequests.first;
          _showPermutationRequestPopup = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showPermutationRequestDialog();
            }
          });
        }
      });
    } catch (e) {
      // Log error silently
    }
  }

  void _showPermutationRequestDialog() {
    if (_currentPermutationRequest == null) return;

    showDialog(
      context: context,
      barrierDismissible: true, // Make it dismissible
      builder: (context) => AlertDialog(
        title: Text('Permutation Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Someone wants to swap days with you:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'They want your:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(_currentPermutationRequest!['receiver_day'] ?? ''),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Icon(Icons.swap_horiz, color: AppColors.primary),
                SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withAlpha(50),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'They offer:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(_currentPermutationRequest!['sender_day'] ?? ''),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Don't change the status, just dismiss the dialog
              setState(() {
                _showPermutationRequestPopup = false;
              });
            },
            child: Text('Later'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handlePermutationResponse('rejected');
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _handlePermutationResponse('accepted');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text('Accept'),
          ),
        ],
      ),
    );
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
    if (_schedule == null || !_schedule!.isFullySet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Schedule is not fully set')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final pdfService = PdfService();
      final file = await pdfService.generateSchedulePdf(_schedule!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF exported to ${file.path}'),
            action: SnackBarAction(
              label: 'OPEN',
              onPressed: () async {
                final openResult = await OpenFile.open(file.path);
                if (openResult.type != ResultType.done && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('Error opening file: ${openResult.message}'),
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED' && mounted) {
        final permissionService = PermissionService();
        final status = await permissionService.requestStoragePermission();
        if (status == PermissionStatus.permanentlyDenied && mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Storage Permission Required'),
              content: const Text(
                'To save PDF files, we need permission to access your device storage. '
                'Please grant this permission in your device settings.',
              ),
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
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('Storage permission is required to save PDF files'),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting PDF: $e')),
        );
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
    final startDate = _schedule!.startDate;
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
    final otherParticipantsTakenDates = _participants
        .where((p) => p.userId != SupabaseManager.getCurrentUserId())
        .expand((p) => p.freeDays)
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toSet();

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

        if (_schedule!.availableDays
            .any((availableDay) => availableDay.day == dayName)) {
          final availableDay =
              _schedule!.availableDays.firstWhere((d) => d.day == dayName);

          // Check if the day has available time slots
          final dateKey = DateFormat('yyyy-MM-dd').format(normalizedDate);
          final hasAvailableSlots = _availableTimeSlots.containsKey(dateKey) &&
              _availableTimeSlots[dateKey]!.isNotEmpty;

          if (currentUserTakenDates.contains(normalizedDate)) {
            final existingDay = currentUserFreeDays.firstWhere(
              (d) =>
                  d.date.year == normalizedDate.year &&
                  d.date.month == normalizedDate.month &&
                  d.date.day == normalizedDate.day,
            );
            weekDays.add(existingDay);
          } else if (!otherParticipantsTakenDates.contains(normalizedDate) ||
              hasAvailableSlots) {
            weekDays.add(FreeDay(
              day: dayName,
              date: normalizedDate,
              startTime: availableDay.startTime,
              endTime: availableDay.endTime,
            ));
          }
        }
      }

      if (weekDays.isNotEmpty) {
        weeklyDays.add(weekDays);
      }
    }

    return weeklyDays;
  }

  void _calculateAvailableTimeSlots() {
    if (_schedule == null) return;
    _availableTimeSlots = {};
    final allTakenSlots = <String, List<TimeSlot>>{};

    for (var participant in _participants) {
      for (var freeDay in participant.freeDays) {
        final dateKey = DateFormat('yyyy-MM-dd').format(freeDay.date);
        try {
          final timeSlot = TimeSlot(
            startTime: freeDay.startTime,
            endTime: freeDay.endTime,
          );
          if (allTakenSlots.containsKey(dateKey)) {
            allTakenSlots[dateKey]!.add(timeSlot);
          } else {
            allTakenSlots[dateKey] = [timeSlot];
          }
        } catch (e) {
          // Skip invalid time slots
          continue;
        }
      }
    }

    for (var weekDays in _availableWeeklyDays) {
      for (var availableDay in weekDays) {
        final dateKey = DateFormat('yyyy-MM-dd').format(availableDay.date);
        final dayConstraint = _schedule!.availableDays.firstWhere(
          (d) => d.day == availableDay.day,
          orElse: () => AvailableDay(
            day: availableDay.day,
            startTime: '08:00',
            endTime: '18:00',
          ),
        );

        final fullDaySlot = TimeSlot(
          startTime: dayConstraint.startTime,
          endTime: dayConstraint.endTime,
        );
        List<TimeSlot> availableSlots = [fullDaySlot];

        if (allTakenSlots.containsKey(dateKey)) {
          final takenSlots = allTakenSlots[dateKey]!;
          takenSlots.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));

          for (var takenSlot in takenSlots) {
            List<TimeSlot> newAvailableSlots = [];
            for (var availableSlot in availableSlots) {
              if (availableSlot.endMinutes <= takenSlot.startMinutes ||
                  availableSlot.startMinutes >= takenSlot.endMinutes) {
                newAvailableSlots.add(availableSlot);
                continue;
              }
              if (takenSlot.startMinutes <= availableSlot.startMinutes &&
                  takenSlot.endMinutes >= availableSlot.endMinutes) {
                continue;
              }
              if (takenSlot.startMinutes > availableSlot.startMinutes &&
                  takenSlot.endMinutes < availableSlot.endMinutes) {
                newAvailableSlots.add(TimeSlot(
                  startTime: availableSlot.startTime,
                  endTime: takenSlot.startTime,
                ));
                newAvailableSlots.add(TimeSlot(
                  startTime: takenSlot.endTime,
                  endTime: availableSlot.endTime,
                ));
                continue;
              }
              if (takenSlot.startMinutes <= availableSlot.startMinutes &&
                  takenSlot.endMinutes > availableSlot.startMinutes) {
                newAvailableSlots.add(TimeSlot(
                  startTime: _minutesToTimeString(takenSlot.endMinutes),
                  endTime: availableSlot.endTime,
                ));
                continue;
              }
              if (takenSlot.startMinutes < availableSlot.endMinutes &&
                  takenSlot.endMinutes >= availableSlot.endMinutes) {
                newAvailableSlots.add(TimeSlot(
                  startTime: availableSlot.startTime,
                  endTime: _minutesToTimeString(takenSlot.startMinutes),
                ));
                continue;
              }
            }
            availableSlots = newAvailableSlots;
          }
        }

        availableSlots = availableSlots
            .where((slot) => slot.endMinutes - slot.startMinutes >= 30)
            .toList();

        if (availableSlots.isNotEmpty) {
          _availableTimeSlots[dateKey] = availableSlots;
        }
      }
    }
  }

  String _minutesToTimeString(int minutes) {
    final hours = (minutes / 60).floor();
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  Future<void> _selectSpecificHours(FreeDay day) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(day.date);
    if (!_availableTimeSlots.containsKey(dateKey) ||
        _availableTimeSlots[dateKey]!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available time slots for this day')),
      );
      return;
    }

    final availableDay = _schedule!.availableDays.firstWhere(
      (d) => d.day == day.day,
      orElse: () =>
          AvailableDay(day: day.day, startTime: '08:00', endTime: '18:00'),
    );

    _selectedStartTime = null;
    _selectedEndTime = null;

    final result = await showDialog<Map<String, TimeOfDay>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface.withValues(alpha: 0.95),
            title: Text(
              'Select Time for ${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Available time slots:'),
                ...(_availableTimeSlots[dateKey] ?? []).map(
                  (slot) => ListTile(
                    title: Text('${slot.startTime} - ${slot.endTime}'),
                    onTap: () {
                      final startParts = slot.startTime.split(':');
                      final endParts = slot.endTime.split(':');
                      setDialogState(() {
                        _selectedStartTime = TimeOfDay(
                          hour: int.parse(startParts[0]),
                          minute: int.parse(startParts[1]),
                        );
                        _selectedEndTime = TimeOfDay(
                          hour: int.parse(endParts[0]),
                          minute: int.parse(endParts[1]),
                        );
                      });
                    },
                    selected: _selectedStartTime != null &&
                        _selectedEndTime != null &&
                        _selectedStartTime!.hour.toString().padLeft(2, '0') ==
                            slot.startTime.split(':')[0] &&
                        _selectedStartTime!.minute.toString().padLeft(2, '0') ==
                            slot.startTime.split(':')[1] &&
                        _selectedEndTime!.hour.toString().padLeft(2, '0') ==
                            slot.endTime.split(':')[0] &&
                        _selectedEndTime!.minute.toString().padLeft(2, '0') ==
                            slot.endTime.split(':')[1],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _selectedStartTime ??
                                TimeOfDay(
                                  hour: int.parse(
                                      availableDay.startTime.split(':')[0]),
                                  minute: int.parse(
                                      availableDay.startTime.split(':')[1]),
                                ),
                            builder: (context, child) {
                              return MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  alwaysUse24HourFormat: true,
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            final pickedMinutes =
                                picked.hour * 60 + picked.minute;
                            final isValid = _availableTimeSlots[dateKey]!.any(
                              (slot) =>
                                  pickedMinutes >= slot.startMinutes &&
                                  pickedMinutes < slot.endMinutes,
                            );
                            if (isValid) {
                              setDialogState(() {
                                _selectedStartTime = picked;
                              });
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Selected start time is not available'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Time',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedStartTime != null
                                ? '${_selectedStartTime!.hour.toString().padLeft(2, '0')}:${_selectedStartTime!.minute.toString().padLeft(2, '0')}'
                                : 'Select',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _selectedEndTime ??
                                TimeOfDay(
                                  hour: int.parse(
                                      availableDay.endTime.split(':')[0]),
                                  minute: int.parse(
                                      availableDay.endTime.split(':')[1]),
                                ),
                            builder: (context, child) {
                              return MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  alwaysUse24HourFormat: true,
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            final pickedMinutes =
                                picked.hour * 60 + picked.minute;
                            final isValid = _availableTimeSlots[dateKey]!.any(
                              (slot) =>
                                  pickedMinutes > slot.startMinutes &&
                                  pickedMinutes <= slot.endMinutes,
                            );
                            if (isValid) {
                              setDialogState(() {
                                _selectedEndTime = picked;
                              });
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Selected end time is not available'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Time',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            _selectedEndTime != null
                                ? '${_selectedEndTime!.hour.toString().padLeft(2, '0')}:${_selectedEndTime!.minute.toString().padLeft(2, '0')}'
                                : 'Select',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              TextButton(
                onPressed: () {
                  if (_selectedStartTime == null || _selectedEndTime == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select both start and end time'),
                      ),
                    );
                    return;
                  }

                  final startMinutes = _selectedStartTime!.hour * 60 +
                      _selectedStartTime!.minute;
                  final endMinutes =
                      _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;

                  if (startMinutes >= endMinutes) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('End time must be after start time'),
                      ),
                    );
                    return;
                  }

                  final selectedSlot = TimeSlot(
                    startTime:
                        '${_selectedStartTime!.hour.toString().padLeft(2, '0')}:${_selectedStartTime!.minute.toString().padLeft(2, '0')}',
                    endTime:
                        '${_selectedEndTime!.hour.toString().padLeft(2, '0')}:${_selectedEndTime!.minute.toString().padLeft(2, '0')}',
                  );

                  final isValidSelection = _availableTimeSlots[dateKey]!.any(
                    (slot) =>
                        selectedSlot.startMinutes >= slot.startMinutes &&
                        selectedSlot.endMinutes <= slot.endMinutes,
                  );

                  if (!isValidSelection) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Selected time is not available'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(context, {
                    'startTime': _selectedStartTime!,
                    'endTime': _selectedEndTime!,
                  });
                },
                child: const Text('CONFIRM'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final selectedStartTime = result['startTime']!;
      final selectedEndTime = result['endTime']!;

      final startTimeStr =
          '${selectedStartTime.hour.toString().padLeft(2, '0')}:${selectedStartTime.minute.toString().padLeft(2, '0')}';
      final endTimeStr =
          '${selectedEndTime.hour.toString().padLeft(2, '0')}:${selectedEndTime.minute.toString().padLeft(2, '0')}';

      final updatedFreeDay = FreeDay(
        day: day.day,
        date: day.date,
        startTime: startTimeStr,
        endTime: endTimeStr,
      );

      setState(() {
        final existingIndex = _freeDays.indexWhere((d) =>
            d.date.year == day.date.year &&
            d.date.month == day.date.month &&
            d.date.day == day.date.day);
        if (existingIndex >= 0) {
          _freeDays[existingIndex] = updatedFreeDay;
        } else {
          _freeDays.add(updatedFreeDay);
        }
      });

      try {
        await _updateFreeDays();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating free days: $e')),
          );
        }
      }
    }
  }

  Future<void> _selectAvailableDay(FreeDay day) async {
    try {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface.withValues(alpha: 0.95),
          title:
              Text('${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Select Specific Hours'),
                onTap: () => Navigator.pop(context, 'select_hours'),
              ),
              ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('Set Alarm'),
                onTap: () => Navigator.pop(context, 'set_alarm'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
          ],
        ),
      );

      if (action == 'select_hours') {
        await _selectSpecificHours(day);
      } else if (action == 'set_alarm') {
        await _setAlarm(day);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeFreeDay(FreeDay day) async {
    setState(() {
      _freeDays.removeWhere((d) =>
          d.date.year == day.date.year &&
          d.date.month == day.date.month &&
          d.date.day == day.date.day);
    });

    await _updateFreeDays();
  }

  Future<void> _fetchSchedule() async {
    setState(() => _isLoading = true);
    try {
      final schedules = await _scheduleService
          .getUserSchedules(SupabaseManager.getCurrentUserId()!)
          .timeout(const Duration(seconds: 5));
      if (schedules.isEmpty) {
        throw Exception('No schedules found for this user');
      }
      _schedule = schedules.firstWhere((s) => s.id == _scheduleId,
          orElse: () =>
              throw Exception('Schedule with ID $_scheduleId not found'));
      final currentParticipant = _schedule!.participants
          .firstWhere((p) => p.userId == SupabaseManager.getCurrentUserId()!);
      _freeDays = currentParticipant.freeDays;
      _participants = _schedule!.participants;

      // Cancel existing subscriptions safely using null-aware operator
      _participantSubscription?.cancel();
      _scheduleSubscription?.cancel();

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
                  freeDays: []));
          _freeDays = currentUser.freeDays;
          if (_schedule != null) {
            _schedule = _schedule!.copyWith(participants: participants);
          }
          _availableWeeklyDays = _getWeeklyAvailableDays();
          _calculateAvailableTimeSlots();
        });
      });

      _scheduleSubscription =
          _scheduleService.getScheduleStream(_scheduleId!).listen((schedule) {
        setState(() {
          _schedule = schedule;
          _availableWeeklyDays = _getWeeklyAvailableDays();
          _calculateAvailableTimeSlots();
        });
      });

      _scheduleService.notificationStream.listen((payload) {
        if (payload['type'] == 'free_days_updated' &&
            payload['data']['schedule_id'] == _scheduleId) {
          setState(() {
            _availableWeeklyDays = _getWeeklyAvailableDays();
            _calculateAvailableTimeSlots();
          });
        }
      });

      final alarmBox = Hive.box('alarms');
      _alarms.addAll(alarmBox.toMap().cast<String, String>());
      _availableWeeklyDays = _getWeeklyAvailableDays();
      _calculateAvailableTimeSlots();
      await _fetchPendingPermutationRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading schedule: $e')));
        Navigator.pop(context);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _participantSubscription?.cancel();
    _scheduleSubscription?.cancel();
    _scheduleService.dispose();
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
        title: Text(
          _schedule!.name,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.6),
                AppColors.secondary.withValues(alpha: 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon:
                Icon(Icons.calendar_view_month, color: AppColors.textOnPrimary),
            tooltip: 'Toggle Calendar View',
            onPressed: () {
              setState(() {
                _showCalendarView = !_showCalendarView;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh_sharp, color: AppColors.textOnPrimary),
            tooltip: 'Refresh Schedule',
            onPressed: _fetchSchedule,
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
                      // Conditionally show either the Calendar View or the Select Free Days card
                      if (_showCalendarView)
                        Card(
                          elevation: 8,
                          shadowColor:
                              AppColors.secondary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          color: Colors.white.withAlpha(243),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_view_month,
                                      color: AppColors.primary,
                                      size: 28,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Calendar View',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                SizedBox(
                                  height: 340,
                                  child: CalendarView(
                                    schedule: _schedule!,
                                    freeDays: _freeDays,
                                    participants: _participants,
                                    onDaySelected: (day) =>
                                        _selectAvailableDay(day),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Card(
                          elevation: 8,
                          shadowColor:
                              AppColors.secondary.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          color: Colors.white.withAlpha(243),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.event_available,
                                      color: AppColors.primary,
                                      size: 28,
                                    ),
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
                                    color: _schedule!.isFullySet
                                        ? AppColors.tertiary
                                        : AppColors.textSecondary,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          final selectedDay = isSelected
                                              ? _freeDays.firstWhere(
                                                  (d) =>
                                                      d.date.year ==
                                                          day.date.year &&
                                                      d.date.month ==
                                                          day.date.month &&
                                                      d.date.day ==
                                                          day.date.day,
                                                  orElse: () => day)
                                              : day;
                                          return GestureDetector(
                                            onTap: () =>
                                                _selectAvailableDay(day),
                                            onLongPress: isSelected
                                                ? () => _removeFreeDay(day)
                                                : null,
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
                                                    color: isSelected
                                                        ? AppColors.primary
                                                            .withAlpha(100)
                                                        : Colors.black
                                                            .withAlpha(26),
                                                    blurRadius: 8,
                                                    offset: Offset(0, 3),
                                                    spreadRadius: 1,
                                                  ),
                                                ],
                                                border: isSelected
                                                    ? Border.all(
                                                        color: AppColors
                                                            .secondary
                                                            .withAlpha(150),
                                                        width: 2)
                                                    : null,
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
                                                              FontWeight.w600,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      SizedBox(height: 6),
                                                      Text(
                                                        DateFormat('dd-MM-yy')
                                                            .format(day.date),
                                                        style: TextStyle(
                                                          color: isSelected
                                                              ? AppColors
                                                                  .textOnPrimary
                                                                  .withAlpha(
                                                                      220)
                                                              : AppColors
                                                                  .textSecondary,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if (isSelected)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(top: 6),
                                                          child: Text(
                                                            '${selectedDay.startTime} - ${selectedDay.endTime}',
                                                            style: TextStyle(
                                                              color: isSelected
                                                                  ? AppColors
                                                                      .textOnPrimary
                                                                      .withAlpha(
                                                                          180)
                                                                  : AppColors
                                                                      .textSecondary
                                                                      .withAlpha(
                                                                          180),
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (hasAlarm)
                                                    Positioned(
                                                      right: 0,
                                                      top: 0,
                                                      child: Container(
                                                        width: 12,
                                                        height: 12,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.red,
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                            color: Colors.white,
                                                            width: 1,
                                                          ),
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
                                        icon: Icon(
                                          Icons.alarm,
                                          color: AppColors.primary,
                                        ),
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
                                                  itemBuilder:
                                                      (context, index) {
                                                    final key = _alarms.keys
                                                        .elementAt(index);
                                                    final duration =
                                                        _alarms[key] ?? '';
                                                    final parts =
                                                        key.split('_');
                                                    final day = parts[0];
                                                    final date = parts[1];
                                                    return ListTile(
                                                      title:
                                                          Text('$day ($date)'),
                                                      subtitle: Text(
                                                          '$duration before'),
                                                      trailing: IconButton(
                                                        icon:
                                                            Icon(Icons.delete),
                                                        onPressed: () {
                                                          setState(() {
                                                            _alarms.remove(key);
                                                          });
                                                          Navigator.pop(
                                                              context);
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
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
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
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                              Icons.calendar_today,
                                              color: AppColors.primary,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          value: _selectedDay1,
                                          hint: Text('Select your day'),
                                          items: _freeDays
                                              .map(
                                                (day) =>
                                                    DropdownMenuItem<String>(
                                                  value:
                                                      '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                                  child: Text(
                                                      '${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
                                                ),
                                              )
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
                                  Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Their Day:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                              Icons.calendar_today,
                                              color: AppColors.primary,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          value: _selectedDay2,
                                          hint: Text('Select their day'),
                                          items: weeklyAvailableDays
                                              .expand((week) => week)
                                              .where((day) => !_freeDays.any(
                                                  (d) => d.date == day.date))
                                              .map(
                                                (day) =>
                                                    DropdownMenuItem<String>(
                                                  value:
                                                      '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                                  child: Text(
                                                      '${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
                                                ),
                                              )
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
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
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
                      SizedBox(height: 24),
                      Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: Colors.white.withAlpha(243),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Participants Status',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 20),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                itemCount: _participants.length,
                                itemBuilder: (context, index) {
                                  final participant = _participants[index];
                                  final isCurrentUser = participant.userId ==
                                      SupabaseManager.getCurrentUserId();
                                  final completionPercentage =
                                      participant.freeDays.length /
                                          (_schedule!.availableDays.length *
                                              weeklyAvailableDays.length) *
                                          100;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              isCurrentUser
                                                  ? Icons.person
                                                  : Icons.person_outline,
                                              color: isCurrentUser
                                                  ? AppColors.primary
                                                  : AppColors.textSecondary,
                                              size: 20,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              isCurrentUser
                                                  ? 'You'
                                                  : 'Participant ${index + 1}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: isCurrentUser
                                                    ? AppColors.primary
                                                    : AppColors.textPrimary,
                                              ),
                                            ),
                                            Spacer(),
                                            Text(
                                              '${completionPercentage.toStringAsFixed(0)}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    completionPercentage >= 100
                                                        ? Colors.green
                                                        : AppColors.secondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: completionPercentage / 100,
                                            backgroundColor:
                                                Colors.grey.shade200,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              completionPercentage >= 100
                                                  ? Colors.green
                                                  : AppColors.secondary,
                                            ),
                                            minHeight: 8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
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
