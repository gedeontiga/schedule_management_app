import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/custom_text_field.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/utils/supabase_manager.dart';
import '../models/schedule.dart';
import '../models/participant.dart';
import '../models/role.dart';

class ScheduleCreationScreen extends StatefulWidget {
  const ScheduleCreationScreen({super.key});

  @override
  ScheduleCreationScreenState createState() => ScheduleCreationScreenState();
}

class ScheduleCreationScreenState extends State<ScheduleCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _participantController = TextEditingController();
  final _roleController = TextEditingController();
  final ScheduleService _scheduleService = ScheduleService();
  final NotificationService _notificationService = NotificationService();

  final List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  final List<bool> _selectedDays = List.filled(7, false);
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
  final List<Participant> _participants = [];
  bool _isLoading = false;

  Future<String?> _findUserId(String input) async {
    final normalizedInput = input.trim().toLowerCase();
    log('Searching for user with input: "$normalizedInput"');
    try {
      final response = await SupabaseManager.client
          .from('user_profiles') // Use view instead of auth.users
          .select('id, email')
          .eq('email', normalizedInput)
          .single();
      log('Found user: $response');
      return response['id'];
    } catch (e) {
      log('Error finding user: $e');
      return null;
    }
  }

  void _addRoleToParticipant() {
    final input = _participantController.text.trim();
    final roleName = _roleController.text.trim();
    if (input.isEmpty || roleName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and role')),
      );
      return;
    }
    _findUserId(input).then((userId) {
      if (userId != null) {
        setState(() {
          var participant = _participants.firstWhere(
            (p) => p.userId == userId,
            orElse: () => Participant(
              userId: userId,
              scheduleId: '',
              roles: [],
              freeDays: [],
            ),
          );
          if (!_participants.contains(participant)) {
            _participants.add(participant);
          }
          final role = Role(name: roleName);
          participant.roles.add(role);
          _participantController.clear();
          _roleController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Participant added successfully')),
          );
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('User not found with email/username: $input')),
          );
        }
      }
    });
  }

  Future<void> _createSchedule() async {
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
      final schedule = Schedule(
        id: const Uuid().v4(),
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        availableDays: selectedDays,
        duration: _selectedDuration!,
        ownerId: SupabaseManager.getCurrentUserId()!,
        participants: _participants,
        isFullySet: false,
      );
      await _scheduleService.createSchedule(schedule);
      for (var participant in _participants) {
        await _notificationService.sendInvitation(
            schedule.id,
            participant.userId,
            participant.roles.map((r) => r.name).join(', '));
      }
      if (mounted) {
        Navigator.pop(context);
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
    _participantController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Schedule'),
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
                  // Basic Info Section
                  Card(
                    elevation: 2,
                    // color: AppColors.secondary.withAlpha(100),
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
                  // Days & Duration Section
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
                                        value: duration, child: Text(duration)))
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
                  const SizedBox(height: 16),
                  // Participants Section
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ExpansionTile(
                      title: const Text(
                        'Participants',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Email or Username',
                                      hintText: 'Enter email or username',
                                      controller: _participantController,
                                      prefixIcon: Icons.email,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Role',
                                      hintText: 'Enter role name',
                                      controller: _roleController,
                                      prefixIcon: Icons.badge,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              GradientButton(
                                text: 'Add Participant',
                                onPressed: _addRoleToParticipant,
                              ),
                              if (_participants.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Participants',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _participants.clear();
                                        });
                                      },
                                      child: const Text(
                                        'Clear All',
                                        style:
                                            TextStyle(color: AppColors.error),
                                      ),
                                    ),
                                  ],
                                ),
                                ..._participants.map((p) => ListTile(
                                      leading: CircleAvatar(
                                        child: Text(p.userId.substring(0, 2)),
                                      ),
                                      title: Text(p.userId),
                                      subtitle: Text(p.roles
                                          .map((r) => r.name)
                                          .join(', ')),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: AppColors.error),
                                        onPressed: () {
                                          setState(() {
                                            _participants.remove(p);
                                          });
                                        },
                                      ),
                                    )),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  GradientButton(
                    text: 'Create Schedule',
                    onPressed: _createSchedule,
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
