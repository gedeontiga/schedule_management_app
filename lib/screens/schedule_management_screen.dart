import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../core/constants/app_colors.dart';
import '../core/services/permission_service.dart';
import '../core/utils/firebase_manager.dart';
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

class ScheduleManagementScreenState extends State<ScheduleManagementScreen>
    with SingleTickerProviderStateMixin {
  final ScheduleService _scheduleService = ScheduleService();
  final NotificationService _notificationService = NotificationService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<Schedule?>? _scheduleSubscription;
  StreamSubscription<List<Participant>>? _participantSubscription;

  Schedule? _schedule;
  List<FreeDay> _freeDays = [];
  String? _selectedDay1;
  String? _selectedDay2;
  bool _isLoading = false;
  final Map<String, String> _alarms = {};
  bool _hasFetchedSchedule = false;
  List<Participant> _participants = [];
  String? _scheduleId;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  List<List<FreeDay>> _availableWeeklyDays = [];
  Map<String, List<TimeSlot>> _availableTimeSlots = {};
  List<Map<String, dynamic>> _pendingPermutationRequests = [];
  bool _showPermutationRequestPopup = false;
  Map<String, dynamic>? _currentPermutationRequest;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
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
      final isValid = await _scheduleService.validateFreeDays(
        _schedule!.id,
        FirebaseManager.currentUserId!,
        _freeDays,
      );

      if (!isValid) {
        throw Exception('Selected days are not available or already taken');
      }

      await _scheduleService.updateFreeDays(
        scheduleId: _schedule!.id,
        userId: FirebaseManager.currentUserId!,
        freeDays: _freeDays,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Free days updated successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
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
        senderId: FirebaseManager.currentUserId!,
        receiverId: _schedule!.participants
            .firstWhere((p) => p.userId != FirebaseManager.currentUserId!)
            .userId,
        scheduleId: _schedule!.id,
        senderDay: _selectedDay1!,
        receiverDay: _selectedDay2!,
      );
      await _notificationService.sendPermutationRequest(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.send, color: Colors.white),
                const SizedBox(width: 12),
                Text('Swap request sent successfully'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      setState(() {
        _selectedDay1 = null;
        _selectedDay2 = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
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
          (p) => p.userId == FirebaseManager.currentUserId!,
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
          scheduleId: scheduleId,
          userId: FirebaseManager.currentUserId!,
          freeDays: myNewFreeDays,
        );
        await _scheduleService.updateFreeDays(
          scheduleId: scheduleId,
          userId: senderId,
          freeDays: theirNewFreeDays,
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
      final userId = FirebaseManager.currentUserId;
      if (userId == null || _scheduleId == null) return;

      final snapshot = await FirebaseManager.firestore
          .collection('permutation_requests')
          .where('receiver_id', isEqualTo: userId)
          .where('schedule_id', isEqualTo: _scheduleId!)
          .where('status', isEqualTo: 'pending')
          .get();

      setState(() {
        _pendingPermutationRequests =
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showPermutationRequestDialog() {
    if (_currentPermutationRequest == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.getSurface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.swap_horiz, color: AppColors.primary),
            SizedBox(width: 12),
            Text('Swap Request'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Someone wants to swap days with you:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'They want:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _currentPermutationRequest!['receiver_day'] ?? '',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.swap_horiz, color: AppColors.primary),
                ),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'They offer:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary,
                            fontSize: 12,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          _currentPermutationRequest!['sender_day'] ?? '',
                          style: TextStyle(fontSize: 13),
                        ),
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
              foregroundColor: AppColors.error,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
        backgroundColor: AppColors.getSurface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
            'Set Alarm for ${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['1h', '2h', '24h']
              .map((duration) => ListTile(
                    leading: Icon(Icons.alarm, color: AppColors.primary),
                    title: Text('$duration before'),
                    onTap: () => Navigator.pop(context, duration),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
        .where((p) => p.userId != FirebaseManager.currentUserId)
        .expand((p) => p.freeDays)
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toSet();

    final currentUserFreeDays = _participants
        .firstWhere(
          (p) => p.userId == FirebaseManager.currentUserId,
          orElse: () => Participant(
            userId: FirebaseManager.currentUserId!,
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
            backgroundColor: AppColors.getSurface(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Select Time for ${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppColors.info, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Available time slots:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  ...(_availableTimeSlots[dateKey] ?? []).map(
                    (slot) => Container(
                      margin: EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading:
                            Icon(Icons.access_time, color: AppColors.primary),
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
                            _selectedStartTime!.hour
                                    .toString()
                                    .padLeft(2, '0') ==
                                slot.startTime.split(':')[0] &&
                            _selectedStartTime!.minute
                                    .toString()
                                    .padLeft(2, '0') ==
                                slot.startTime.split(':')[1] &&
                            _selectedEndTime!.hour.toString().padLeft(2, '0') ==
                                slot.endTime.split(':')[0] &&
                            _selectedEndTime!.minute
                                    .toString()
                                    .padLeft(2, '0') ==
                                slot.endTime.split(':')[1],
                        selectedTileColor:
                            AppColors.primary.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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
                                  data: MediaQuery.of(context)
                                      .copyWith(alwaysUse24HourFormat: true),
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
                                      pickedMinutes < slot.endMinutes);
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
                                  data: MediaQuery.of(context)
                                      .copyWith(alwaysUse24HourFormat: true),
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
                                      pickedMinutes <= slot.endMinutes);
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
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
          backgroundColor: AppColors.getSurface(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.event, color: AppColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                    '${day.day} (${DateFormat('yyyy-MM-dd').format(day.date)})'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.access_time, color: AppColors.primary),
                ),
                title: const Text('Select Specific Hours'),
                onTap: () => Navigator.pop(context, 'select_hours'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.alarm, color: AppColors.secondary),
                ),
                title: const Text('Set Alarm'),
                onTap: () => Navigator.pop(context, 'set_alarm'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
      _scheduleSubscription?.cancel();
      _participantSubscription?.cancel();

      _scheduleSubscription =
          _scheduleService.getSchedule(_scheduleId!).listen((schedule) {
        setState(() {
          _schedule = schedule;
          _availableWeeklyDays = _getWeeklyAvailableDays();
          _calculateAvailableTimeSlots();
        });
      });

      _participantSubscription =
          _scheduleService.getParticipants(_scheduleId!).listen((participants) {
        setState(() {
          _participants = participants;
          final currentUser = participants.firstWhere(
            (p) => p.userId == FirebaseManager.currentUserId!,
            orElse: () => Participant(
              userId: FirebaseManager.currentUserId!,
              scheduleId: _scheduleId!,
              roles: [],
              freeDays: [],
            ),
          );
          _freeDays = currentUser.freeDays;
          if (_schedule != null) {
            _schedule = _schedule!.copyWith(participants: participants);
          }
          _availableWeeklyDays = _getWeeklyAvailableDays();
          _calculateAvailableTimeSlots();
        });
      });

      final alarmBox = Hive.box('alarms');
      _alarms.addAll(alarmBox.toMap().cast<String, String>());

      await _fetchPendingPermutationRequests();
      _animationController.forward();
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
    _animationController.dispose();
    _participantSubscription?.cancel();
    _scheduleSubscription?.cancel();
    _scheduleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_schedule == null) {
      return Scaffold(
        backgroundColor: AppColors.getBackground(context),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'Loading schedule...',
                style: TextStyle(
                  color: AppColors.getTextSecondary(context),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final weeklyAvailableDays = _getWeeklyAvailableDays();

    return Scaffold(
      backgroundColor: AppColors.getBackground(context),
      appBar: AppBar(
        title: Text(
          _schedule!.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.getSurface(context),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh Schedule',
            onPressed: _fetchSchedule,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Calendar View Section
                    CalendarView(
                      schedule: _schedule!,
                      freeDays: _freeDays,
                      participants: _participants,
                      onDaySelected: (day) => _selectAvailableDay(day),
                    ),

                    const SizedBox(height: 24),

                    // My Selected Days Card
                    if (_freeDays.isNotEmpty)
                      Container(
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.event_available,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'My Selected Days',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.getTextPrimary(context),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_freeDays.length}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _freeDays.map((day) {
                                final hasAlarm = _alarms.containsKey(
                                  '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.primary
                                            .withValues(alpha: 0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            day.day,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat('MMM d')
                                                .format(day.date),
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.8),
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${day.startTime} - ${day.endTime}',
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.7),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (hasAlarm) ...[
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.alarm,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => _removeFreeDay(day),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Quick Actions Card
                    Container(
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.bolt,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Quick Actions',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.getTextPrimary(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: GradientButton(
                                  text: 'Save Days',
                                  onPressed: _updateFreeDays,
                                  isLoading: _isLoading,
                                  icon: Icons.save,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GradientButton(
                                  text: 'Export PDF',
                                  onPressed: _exportPdf,
                                  isLoading: _isLoading,
                                  icon: Icons.picture_as_pdf,
                                  enabled: _schedule!.isFullySet,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Day Swap Request Card
                    if (_freeDays.isNotEmpty && weeklyAvailableDays.isNotEmpty)
                      Container(
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.secondary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Request Day Swap',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              AppColors.getTextPrimary(context),
                                        ),
                                      ),
                                      Text(
                                        'Exchange one of your days',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.getTextSecondary(
                                              context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
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
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color:
                                              AppColors.getTextPrimary(context),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color:
                                                AppColors.getDivider(context),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                              Icons.calendar_today,
                                              color: AppColors.primary,
                                              size: 18,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          initialValue: _selectedDay1,
                                          hint: Text(
                                            'Select',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          items: _freeDays
                                              .map(
                                                (day) =>
                                                    DropdownMenuItem<String>(
                                                  value:
                                                      '${day.day}_${DateFormat('yyyy-MM-dd').format(day.date)}',
                                                  child: Text(
                                                    '${day.day} (${DateFormat('MMM d').format(day.date)})',
                                                    style:
                                                        TextStyle(fontSize: 13),
                                                  ),
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
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Their Day:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color:
                                              AppColors.getTextPrimary(context),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color:
                                                AppColors.getDivider(context),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                              Icons.calendar_today,
                                              color: AppColors.secondary,
                                              size: 18,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                          initialValue: _selectedDay2,
                                          hint: Text(
                                            'Select',
                                            style: TextStyle(fontSize: 13),
                                          ),
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
                                                    '${day.day} (${DateFormat('MMM d').format(day.date)})',
                                                    style:
                                                        TextStyle(fontSize: 13),
                                                  ),
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
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: GradientButton(
                                text: 'Send Swap Request',
                                onPressed: _requestPermutation,
                                isLoading: _isLoading,
                                icon: Icons.send,
                                enabled: _selectedDay1 != null &&
                                    _selectedDay2 != null,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Schedule Info Card
                    Container(
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.info_outline,
                                  color: AppColors.info,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Schedule Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.getTextPrimary(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          InfoTile(
                            icon: Icons.description,
                            label: 'Description',
                            value: _schedule!.description ?? 'No description',
                          ),
                          InfoTile(
                            icon: Icons.access_time,
                            label: 'Duration',
                            value: _schedule!.duration,
                          ),
                          InfoTile(
                            icon: Icons.calendar_today,
                            label: 'Created At',
                            value: DateFormat('MMM d, yyyy')
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
                            value:
                                _schedule!.isFullySet ? 'Complete' : 'Pending',
                            valueColor: _schedule!.isFullySet
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Participants Progress Card
                    Container(
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.secondary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.people_outline,
                                  color: AppColors.secondary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Participants Progress',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.getTextPrimary(context),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _participants.length,
                            itemBuilder: (context, index) {
                              final participant = _participants[index];
                              final isCurrentUser = participant.userId ==
                                  FirebaseManager.currentUserId;
                              final completionPercentage =
                                  participant.freeDays.length /
                                      (_schedule!.availableDays.length *
                                          weeklyAvailableDays.length) *
                                      100;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isCurrentUser
                                      ? AppColors.primary
                                          .withValues(alpha: 0.05)
                                      : AppColors.getBackground(context)
                                          .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: isCurrentUser
                                      ? Border.all(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.2),
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isCurrentUser
                                                ? AppColors.primary
                                                    .withValues(alpha: 0.1)
                                                : AppColors.getTextSecondary(
                                                        context)
                                                    .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            isCurrentUser
                                                ? Icons.person
                                                : Icons.person_outline,
                                            color: isCurrentUser
                                                ? AppColors.primary
                                                : AppColors.getTextSecondary(
                                                    context),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            isCurrentUser
                                                ? 'You'
                                                : 'Participant ${index + 1}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              color: isCurrentUser
                                                  ? AppColors.primary
                                                  : AppColors.getTextPrimary(
                                                      context),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: completionPercentage >= 100
                                                ? AppColors.success
                                                    .withValues(alpha: 0.1)
                                                : AppColors.secondary
                                                    .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${completionPercentage.toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: completionPercentage >= 100
                                                  ? AppColors.success
                                                  : AppColors.secondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: completionPercentage / 100,
                                        backgroundColor:
                                            AppColors.getDivider(context),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          completionPercentage >= 100
                                              ? AppColors.success
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
                  ],
                ),
              ),
            ),
    );
  }
}
