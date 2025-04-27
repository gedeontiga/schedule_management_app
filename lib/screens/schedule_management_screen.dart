import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../core/constants/app_colors.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/pdf_service.dart';
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
  final PdfService _pdfService = PdfService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Schedule? _schedule;
  List<String> _freeDays = [];
  String? _selectedDay1;
  String? _selectedDay2;
  bool _isLoading = false;
  final Map<String, String> _alarms = {};

  @override
  void initState() {
    super.initState();
    _fetchSchedule();
    _scheduleService.permutationRequestStream.listen((payload) async {
      if (payload['eventType'] == 'UPDATE' &&
          payload['new']['status'] == 'accepted') {
        await _fetchSchedule(); // Refresh schedule after permutation approval
      }
    });
  }

  Future<void> _fetchSchedule() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final scheduleId = ModalRoute.of(context)!.settings.arguments as String;
      final schedules = await _scheduleService
          .getUserSchedules(Supabase.instance.client.auth.currentUser!.id);
      _schedule = schedules.firstWhere((s) => s.id == scheduleId);
      _freeDays = _schedule!.participants
          .firstWhere(
              (p) => p.userId == Supabase.instance.client.auth.currentUser!.id)
          .freeDays
          .cast<String>();
      final alarmBox = Hive.box('alarms');
      _alarms.addAll(alarmBox.toMap().cast<String, String>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateFreeDays() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _scheduleService.updateFreeDays(
        _schedule!.id,
        Supabase.instance.client.auth.currentUser!.id,
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermutation() async {
    if (_selectedDay1 == null || _selectedDay2 == null) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final request = PermutationRequest(
        id: const Uuid().v4(),
        senderId: Supabase.instance.client.auth.currentUser!.id,
        receiverId: _schedule!.participants
            .firstWhere((p) =>
                p.userId != Supabase.instance.client.auth.currentUser!.id)
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setAlarm(String day) async {
    final selectedAlarm = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set Alarm for $day'),
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
      setState(() {
        _alarms[day] = selectedAlarm;
      });
      final alarmBox = Hive.box('alarms');
      await alarmBox.put(day, selectedAlarm);
      final hours = int.parse(selectedAlarm.replaceAll('h', ''));
      final now = DateTime.now();
      final notificationTime = tz.TZDateTime.from(
        now.add(Duration(hours: hours)),
        tz.local,
      );
      await _notificationsPlugin.zonedSchedule(
        day.hashCode,
        'Schedule Reminder',
        'Reminder for your schedule on $day',
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
    setState(() {
      _isLoading = true;
    });
    try {
      final file = await _pdfService.generateSchedulePdf(_schedule!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF exported to ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_schedule == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_schedule!.name),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withAlpha(50),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select Free Days',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _schedule!.availableDays.map((day) {
                    final isSelected = _freeDays.contains(day);
                    return ChoiceChip(
                      label: Text(day),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _freeDays.add(day);
                            _setAlarm(day);
                          } else {
                            _freeDays.remove(day);
                            _alarms.remove(day);
                          }
                        });
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  text: 'Save Free Days',
                  onPressed: _updateFreeDays,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Request Permutation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Your Day',
                    prefixIcon: const Icon(Icons.calendar_today,
                        color: AppColors.primary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  value: _selectedDay1,
                  items: _freeDays
                      .map((day) => DropdownMenuItem<String>(
                          value: day, child: Text(day)))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedDay1 = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: "Other User's Day",
                    prefixIcon: const Icon(Icons.calendar_today,
                        color: AppColors.primary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  value: _selectedDay2,
                  items: _schedule!.availableDays
                      .map((day) => DropdownMenuItem<String>(
                          value: day, child: Text(day)))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedDay2 = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                GradientButton(
                  text: 'Request Permutation',
                  onPressed: _requestPermutation,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
                GradientButton(
                  text: 'Export as PDF',
                  onPressed: _exportPdf,
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
