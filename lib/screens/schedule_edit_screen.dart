import 'package:flutter/material.dart';
import '../../models/schedule.dart';
import '../core/constants/app_colors.dart';
import '../core/services/schedule_service.dart';
import '../core/utils/supabase_manager.dart';
import '../core/widgets/custom_text_field.dart';
import '../core/widgets/gradient_button.dart';

class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({super.key});

  @override
  ScheduleEditScreenState createState() => ScheduleEditScreenState();
}

class ScheduleEditScreenState extends State<ScheduleEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ScheduleService _scheduleService = ScheduleService();
  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  late List<bool> _selectedDays;
  final List<String> _durations = [
    '1 day',
    '2 days',
    '3 days',
    '4 days',
    '5 days',
    '1 week',
    '2 weeks',
    '1 month'
  ];
  String? _selectedDuration;
  bool _isLoading = false;
  Schedule? _schedule;

  @override
  void initState() {
    super.initState();
    // Get schedule from arguments
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _schedule = ModalRoute.of(context)!.settings.arguments as Schedule;
      _nameController.text = _schedule!.name;
      _descriptionController.text = _schedule!.description ?? '';
      _selectedDuration = _schedule!.duration;
      _selectedDays =
          _days.map((day) => _schedule!.availableDays.contains(day)).toList();
    });
  }

  Future<void> _updateSchedule() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDays.every((selected) => !selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one day')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final selectedDays = _days
          .asMap()
          .entries
          .where((entry) => _selectedDays[entry.key])
          .map((entry) => entry.value)
          .toList();

      final updatedSchedule = Schedule(
        id: _schedule!.id,
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        availableDays: selectedDays,
        duration: _selectedDuration!,
        ownerId: _schedule!.ownerId,
        participants: _schedule!.participants,
        isFullySet: _schedule!.isFullySet,
      );

      // Update schedule in Supabase
      if (await _scheduleService.isOnline()) {
        await _scheduleService.supabase
            .from('schedules')
            .update(updatedSchedule.toJson())
            .eq('id', _schedule!.id);
        // Manually fetch schedules to update stream
        final userId = SupabaseManager.getCurrentUserId();
        if (userId != null) {
          final updatedSchedules =
              await _scheduleService.getUserSchedules(userId);
          _scheduleService.scheduleStreamController.add(updatedSchedules);
        }
      } else {
        // Update local database
        final db = _scheduleService.dbManager.localDatabase;
        await db.update(
          'schedules',
          {
            'name': updatedSchedule.name,
            'description': updatedSchedule.description,
            'available_days': updatedSchedule.availableDays.join(','),
            'duration': updatedSchedule.duration,
            'is_fully_set': updatedSchedule.isFullySet ? 1 : 0,
          },
          where: 'id = ?',
          whereArgs: [updatedSchedule.id],
        );
        await _scheduleService.offlineOperationsBox.add({
          'operation': 'update_schedule',
          'data': updatedSchedule.toJson(),
        });
        // Update local stream
        final userId = SupabaseManager.getCurrentUserId();
        if (userId != null) {
          final updatedSchedules =
              await _scheduleService.getUserSchedules(userId);
          _scheduleService.scheduleStreamController.add(updatedSchedules);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule updated successfully')),
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
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_schedule == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Schedule'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
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
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      title: const Text(
                        'Basic Information',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              CustomTextField(
                                label: 'Schedule Name',
                                hintText: 'Enter schedule name',
                                controller: _nameController,
                                prefixIcon: Icons.event,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter a schedule name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              CustomTextField(
                                label: 'Description (Optional)',
                                hintText: 'Enter description',
                                controller: _descriptionController,
                                prefixIcon: Icons.description,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ExpansionTile(
                      title: const Text(
                        'Days & Duration',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Available Days',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _days.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final day = entry.value;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    child: ChoiceChip(
                                      label: Text(day),
                                      selected: _selectedDays[index],
                                      onSelected: (selected) {
                                        setState(() {
                                          _selectedDays[index] = selected;
                                        });
                                      },
                                      selectedColor: AppColors.primary,
                                      labelStyle: TextStyle(
                                        color: _selectedDays[index]
                                            ? AppColors.textOnPrimary
                                            : AppColors.textPrimary,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                decoration: InputDecoration(
                                  labelText: 'Duration',
                                  prefixIcon: const Icon(Icons.timer,
                                      color: AppColors.primary),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                value: _selectedDuration,
                                items: _durations
                                    .map((duration) => DropdownMenuItem(
                                          value: duration,
                                          child: Text(duration),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedDuration = value;
                                  });
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Please select a duration';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    text: 'Update Schedule',
                    onPressed: _updateSchedule,
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
