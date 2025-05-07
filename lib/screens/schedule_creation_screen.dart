import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/custom_text_field.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/utils/supabase_manager.dart';
import '../models/available_day.dart';
import '../models/schedule.dart';
import '../models/participant.dart';
import '../models/role.dart';

class ScheduleCreationScreen extends StatefulWidget {
  final Schedule? schedule;

  const ScheduleCreationScreen({super.key, this.schedule});

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
  final Map<String, String> _usernameCache = {};
  final List<TextEditingController> _startTimeControllers =
      List.generate(7, (_) => TextEditingController(text: '08:00'));
  final List<TextEditingController> _endTimeControllers =
      List.generate(7, (_) => TextEditingController(text: '18:00'));
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
  List<Participant> _participants = [];
  bool _isLoading = false;
  bool _isEditMode = false;
  DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDays = List.filled(7, false);
    _isEditMode = widget.schedule != null;

    if (_isEditMode && widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _descriptionController.text = widget.schedule!.description ?? '';
      _selectedDuration = _durations.contains(widget.schedule!.duration)
          ? widget.schedule!.duration
          : _durations.first;

      _startDate = widget.schedule!.startDate;

      // Set selected days and time intervals
      for (int i = 0; i < _days.length; i++) {
        final day = _days[i];
        final availableDay = widget.schedule!.availableDays.firstWhere(
            (d) => d.day == day,
            orElse: () =>
                AvailableDay(day: day, startTime: '08:00', endTime: '18:00'));

        _selectedDays[i] =
            widget.schedule!.availableDays.any((d) => d.day == day);

        if (_selectedDays[i]) {
          _startTimeControllers[i].text = availableDay.startTime;
          _endTimeControllers[i].text = availableDay.endTime;
        }
      }

      if (widget.schedule!.participants.isNotEmpty) {
        _participants = List.from(widget.schedule!.participants);
        _loadUsernames();
      }
    } else {
      _selectedDuration = _durations.first;
    }
  }

  Future<void> _loadUsernames() async {
    for (var participant in _participants) {
      _usernameCache[participant.userId] = participant.userId;
    }
    try {
      await Future.wait(_participants.map((participant) async {
        final username = await _findUsername(participant.userId);
        if (username != null) {
          _usernameCache[participant.userId] = username;
        }
      }));
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // ignore
    }
  }

  Future<String?> _findUserId(String input) async {
    final normalizedInput = input.trim().toLowerCase();
    try {
      final response = await SupabaseManager.client
          .from('user_profiles')
          .select('id, email')
          .eq('email', normalizedInput)
          .single();
      return response['id'];
    } catch (e) {
      return null;
    }
  }

  Future<String?> _findUsername(String userId) async {
    try {
      final response = await SupabaseManager.client
          .from('user_details')
          .select('id, username')
          .eq('id', userId)
          .single();
      return response['username'];
    } catch (e) {
      return null;
    }
  }

  Future<void> _selectTime(
      BuildContext context, TextEditingController controller) async {
    TimeOfDay initialTime;
    try {
      final timeParts = controller.text.split(':');
      initialTime = TimeOfDay(
          hour: int.parse(timeParts[0]), minute: int.parse(timeParts[1]));
    } catch (e) {
      initialTime = TimeOfDay.now();
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      controller.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
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
    setState(() => _isLoading = true);
    _findUserId(input).then((userId) {
      if (userId != null) {
        _findUsername(userId).then((username) {
          if (username != null) {
            setState(() {
              _usernameCache[userId] = username;
            });
          }
        });
        setState(() {
          var participant = _participants.firstWhere(
            (p) => p.userId == userId,
            orElse: () => Participant(
              userId: userId,
              scheduleId: _isEditMode ? widget.schedule!.id : const Uuid().v4(),
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
          _isLoading = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Participant added successfully')),
          );
        });
      } else {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('User not found with email: $input')),
          );
        }
      }
    }).catchError((error) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding participant')),
        );
      }
    });
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDays.every((selected) => !selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one day')),
      );
      return;
    }

    // Validate time slots
    for (int i = 0; i < _days.length; i++) {
      if (_selectedDays[i]) {
        final startTime = _startTimeControllers[i].text;
        final endTime = _endTimeControllers[i].text;
        final startParts = startTime.split(':').map(int.parse).toList();
        final endParts = endTime.split(':').map(int.parse).toList();
        final startMinutes = startParts[0] * 60 + startParts[1];
        final endMinutes = endParts[0] * 60 + endParts[1];

        if (startMinutes >= endMinutes) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Start time must be before end time for ${_days[i]}')),
          );
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    try {
      final availableDays = <AvailableDay>[];
      for (int i = 0; i < _days.length; i++) {
        if (_selectedDays[i]) {
          availableDays.add(AvailableDay(
            day: _days[i],
            startTime: _startTimeControllers[i].text,
            endTime: _endTimeControllers[i].text,
          ));
        }
      }

      final scheduleId = _isEditMode ? widget.schedule!.id : const Uuid().v4();
      final updatedParticipants = _participants.map((p) {
        final existingParticipant = _isEditMode
            ? widget.schedule!.participants.firstWhere(
                (ep) => ep.userId == p.userId,
                orElse: () => p,
              )
            : p;
        return Participant(
          userId: p.userId,
          scheduleId: scheduleId,
          roles: p.roles,
          freeDays: existingParticipant.freeDays,
        );
      }).toList();

      if (!_isEditMode) {
        updatedParticipants.add(Participant(
          userId: SupabaseManager.getCurrentUserId()!,
          scheduleId: scheduleId,
          roles: [Role(name: 'Owner')],
          freeDays: [],
        ));
      }

      final schedule = Schedule(
        id: scheduleId,
        name: _nameController.text,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
        availableDays: availableDays,
        duration: _selectedDuration!,
        ownerId: SupabaseManager.getCurrentUserId()!,
        participants: updatedParticipants,
        isFullySet: _isEditMode ? widget.schedule!.isFullySet : false,
        createdAt: _isEditMode ? widget.schedule!.createdAt : DateTime.now(),
        startDate: _startDate,
      );

      if (_isEditMode) {
        await _scheduleService.updateSchedule(schedule);
        await _scheduleService.syncParticipants(
            scheduleId, updatedParticipants);
      } else {
        await _scheduleService.createSchedule(schedule);
        for (var participant in updatedParticipants) {
          if (participant.userId != SupabaseManager.getCurrentUserId()) {
            try {
              await _notificationService.sendInvitation(
                schedule.id,
                participant.userId,
                participant.roles.map((r) => r.name).join(', '),
              );
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Schedule created, but failed to send invitation to ${_usernameCache[participant.userId] ?? participant.userId}',
                    ),
                  ),
                );
              }
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Schedule updated successfully'
                : 'Schedule created successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _participantController.dispose();
    _roleController.dispose();

    for (var controller in _startTimeControllers) {
      controller.dispose();
    }

    for (var controller in _endTimeControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  Widget _buildDateSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: InkWell(
        onTap: () => _selectDate(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('yyyy-MM-dd').format(_startDate),
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Update the _selectDate method to provide better feedback
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _startDate.isBefore(DateTime.now()) ? DateTime.now() : _startDate,
      firstDate: DateTime.now(), // Changed to prevent selecting past dates
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: AppColors.textOnPrimary,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _startDate) {
      setState(() {
        _startDate = picked;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Start date set to ${DateFormat('yyyy-MM-dd').format(picked)}'),
            backgroundColor: AppColors.secondary,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Schedule' : 'Create Schedule'),
        backgroundColor: AppColors.secondary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
      // Apply the gradient to the entire background
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withAlpha(26),
              AppColors.secondary.withAlpha(26),
            ],
          ),
        ),
        // Make sure the Container fills the entire available space
        width: double.infinity,
        height: double.infinity,
        child: SafeArea(
          child: _isLoading && _participants.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 16.0 : 24.0,
                    vertical: 16.0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Make cards transparent to let gradient show through
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // Use a transparent color for the card
                              color: Colors.white.withAlpha(230),
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
                                            if (value == null ||
                                                value.isEmpty) {
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
                                borderRadius: BorderRadius.circular(12),
                              ),
                              color: Colors.white.withAlpha(230),
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                title: const Text(
                                  'Days & Duration',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Start Date Selector
                                        const Text(
                                          'Start Date',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildDateSelector(),
                                        const SizedBox(height: 16),

                                        // Available Days
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
                                          children: _days
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            final index = entry.key;
                                            final day = entry.value;
                                            return AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: ChoiceChip(
                                                label: Text(day),
                                                selected: _selectedDays[index],
                                                onSelected: (selected) {
                                                  setState(() {
                                                    _selectedDays[index] =
                                                        selected;
                                                  });
                                                },
                                                selectedColor:
                                                    AppColors.primary,
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

                                        // Day Time Selectors
                                        ..._days
                                            .asMap()
                                            .entries
                                            .where((entry) =>
                                                _selectedDays[entry.key])
                                            .map((entry) {
                                          int index = entry.key;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 12.0),
                                            child: Card(
                                              elevation: 1,
                                              margin: EdgeInsets.zero,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                side: BorderSide(
                                                    color: AppColors.primary
                                                        .withValues(
                                                            alpha: 0.2)),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12.0),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _days[index],
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            AppColors.primary,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextFormField(
                                                            controller:
                                                                _startTimeControllers[
                                                                    index],
                                                            readOnly: true,
                                                            decoration:
                                                                InputDecoration(
                                                              labelText:
                                                                  'Start Time',
                                                              suffixIcon:
                                                                  const Icon(Icons
                                                                      .access_time),
                                                              border:
                                                                  OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                            ),
                                                            onTap: () =>
                                                                _selectTime(
                                                                    context,
                                                                    _startTimeControllers[
                                                                        index]),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                          child: TextFormField(
                                                            controller:
                                                                _endTimeControllers[
                                                                    index],
                                                            readOnly: true,
                                                            decoration:
                                                                InputDecoration(
                                                              labelText:
                                                                  'End Time',
                                                              suffixIcon:
                                                                  const Icon(Icons
                                                                      .access_time),
                                                              border:
                                                                  OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 12,
                                                                vertical: 8,
                                                              ),
                                                            ),
                                                            onTap: () =>
                                                                _selectTime(
                                                                    context,
                                                                    _endTimeControllers[
                                                                        index]),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }),

                                        const SizedBox(height: 16),

                                        // Duration Selector
                                        DropdownButtonFormField<String>(
                                          decoration: InputDecoration(
                                            labelText: 'Duration',
                                            prefixIcon: const Icon(Icons.timer,
                                                color: AppColors.primary),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          value: _selectedDuration,
                                          items: _durations
                                              .map((duration) =>
                                                  DropdownMenuItem(
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
                            const SizedBox(height: 16),
                            Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // Use a transparent color for the card
                              color: Colors.white.withAlpha(230),
                              child: ExpansionTile(
                                initiallyExpanded: true,
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
                                                label: 'Email',
                                                hintText: 'Enter email',
                                                controller:
                                                    _participantController,
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
                                          isLoading: _isLoading,
                                          enabled: !_isLoading,
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
                                                onPressed: _isLoading
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _participants.clear();
                                                        });
                                                      },
                                                child: const Text(
                                                  'Clear All',
                                                  style: TextStyle(
                                                      color: AppColors.error),
                                                ),
                                              ),
                                            ],
                                          ),
                                          ...List.generate(_participants.length,
                                              (index) {
                                            final p = _participants[index];
                                            return ListTile(
                                              leading: CircleAvatar(
                                                backgroundColor:
                                                    AppColors.primary,
                                                foregroundColor:
                                                    AppColors.textOnPrimary,
                                                child: Text(
                                                  (_usernameCache[p.userId] ??
                                                          'User')
                                                      .substring(0, 1)
                                                      .toUpperCase(),
                                                ),
                                              ),
                                              title: Text(
                                                  _usernameCache[p.userId] ??
                                                      'Loading...'),
                                              subtitle: Text(p.roles
                                                  .map((r) => r.name)
                                                  .join(', ')),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete,
                                                    color: AppColors.error),
                                                onPressed: _isLoading
                                                    ? null
                                                    : () {
                                                        setState(() {
                                                          _participants
                                                              .remove(p);
                                                        });
                                                      },
                                              ),
                                            );
                                          }),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isSmallScreen ? 0 : 48.0),
                              child: GradientButton(
                                text: _isEditMode
                                    ? 'Update Schedule'
                                    : 'Create Schedule',
                                onPressed: _saveSchedule,
                                isLoading: _isLoading,
                                enabled: !_isLoading,
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
