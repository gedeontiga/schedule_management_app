import 'dart:async';

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
import '../core/widgets/info_tile.dart';
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
  bool _hasFetchedSchedule = false; // Flag to prevent multiple fetches

  @override
  void initState() {
    super.initState();
    // Subscribe to permutation request stream
    _scheduleService.permutationRequestStream.listen((payload) async {
      if (payload['eventType'] == 'UPDATE' &&
          payload['new']['status'] == 'accepted') {
        await _fetchSchedule(); // Refresh schedule after permutation approval
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only fetch the schedule once
    if (!_hasFetchedSchedule) {
      _hasFetchedSchedule = true;
      _fetchSchedule();
    }
  }

  Future<void> _fetchSchedule() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final scheduleId = ModalRoute.of(context)!.settings.arguments as String;
      final schedules = await _scheduleService
          .getUserSchedules(Supabase.instance.client.auth.currentUser!.id)
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException('Failed to fetch schedules: Request timed out');
      });
      if (schedules.isEmpty) {
        throw Exception('No schedules found for this user');
      }
      _schedule = schedules.firstWhere(
        (s) => s.id == scheduleId,
        orElse: () => throw Exception('Schedule with ID $scheduleId not found'),
      );
      final currentParticipant = _schedule!.participants.firstWhere(
        (p) => p.userId == Supabase.instance.client.auth.currentUser!.id,
        orElse: () => throw Exception(
            'Current user is not a participant in this schedule'),
      );
      _freeDays = currentParticipant.freeDays.cast<String>();
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
      return Scaffold(
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
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_schedule!.name),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0, // Remove shadow for modern look
        actions: [
          // Add export button to AppBar for easier access
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Export as PDF',
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: Container(
        // Apply gradient to full container
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
        // Ensure container fills the entire screen
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Free Days Section Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        // Use semi-transparent white to let gradient show through
                        color: Colors.white.withAlpha(230),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Select Your Free Days',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  // Show count of selected days
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withAlpha(26),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_freeDays.length}/${_schedule!.availableDays.length}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Tap on days when you are available:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _schedule!.availableDays.map((day) {
                                  final isSelected = _freeDays.contains(day);
                                  final hasAlarm = _alarms.containsKey(day);

                                  return Stack(
                                    children: [
                                      ChoiceChip(
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
                                        backgroundColor: Colors.grey.shade200,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        labelStyle: TextStyle(
                                          color: isSelected
                                              ? AppColors.textOnPrimary
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                      ),
                                      // Show alarm indicator
                                      if (hasAlarm)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
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
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.alarm,
                                        color: AppColors.primary,
                                      ),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title:
                                                const Text('Configured Alarms'),
                                            content: SizedBox(
                                              width: double.maxFinite,
                                              child: ListView.builder(
                                                shrinkWrap: true,
                                                itemCount: _alarms.length,
                                                itemBuilder: (context, index) {
                                                  final day = _alarms.keys
                                                      .elementAt(index);
                                                  final duration =
                                                      _alarms[day] ?? '';
                                                  return ListTile(
                                                    title: Text(day),
                                                    subtitle: Text(
                                                        '$duration before'),
                                                    trailing: IconButton(
                                                      icon: const Icon(
                                                          Icons.delete),
                                                      onPressed: () {
                                                        setState(() {
                                                          _alarms.remove(day);
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
                                                child: const Text('Close'),
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
                      const SizedBox(height: 20),

                      // Permutation Request Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: Colors.white.withAlpha(230),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Request Schedule Swap',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Swap one of your days with another participant:',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Your Day:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: const Icon(
                                                Icons.calendar_today,
                                                color: AppColors.primary),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          value: _selectedDay1,
                                          hint: const Text('Select your day'),
                                          items: _freeDays
                                              .map((day) =>
                                                  DropdownMenuItem<String>(
                                                      value: day,
                                                      child: Text(day)))
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
                                  const SizedBox(width: 16),
                                  const Icon(
                                    Icons.swap_horiz,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Their Day:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            prefixIcon: const Icon(
                                                Icons.calendar_today,
                                                color: AppColors.primary),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8),
                                          ),
                                          value: _selectedDay2,
                                          hint: const Text('Select their day'),
                                          items: _schedule!.availableDays
                                              .where((day) =>
                                                  !_freeDays.contains(day))
                                              .map((day) =>
                                                  DropdownMenuItem<String>(
                                                      value: day,
                                                      child: Text(day)))
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
                              const SizedBox(height: 16),
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
                      const SizedBox(height: 20),

                      // Schedule Info Card
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: Colors.white.withAlpha(230),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Schedule Information',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Schedule details
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

                              const SizedBox(height: 16),
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
