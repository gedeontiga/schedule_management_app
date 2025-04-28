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

  @override
  void initState() {
    super.initState();

    // Initialize selectedDays here
    _selectedDays = List.filled(7, false);

    // Debug log to confirm initState is called
    debugPrint(
        'initState called: ${widget.schedule != null ? 'Edit Mode' : 'Create Mode'}');

    _isEditMode = widget.schedule != null;

    if (_isEditMode && widget.schedule != null) {
      // Added null check
      debugPrint(
          'Editing schedule: id=${widget.schedule!.id}, name=${widget.schedule!.name}');

      // Set controllers with schedule data
      _nameController.text = widget.schedule!.name;
      _descriptionController.text = widget.schedule!.description ?? '';

      // Set duration
      _selectedDuration = _durations.contains(widget.schedule!.duration)
          ? widget.schedule!.duration
          : _durations.first;
      debugPrint('Selected duration: $_selectedDuration');

      // Set selected days
      for (int i = 0; i < _days.length; i++) {
        _selectedDays[i] = widget.schedule!.availableDays.contains(_days[i]);
      }
      debugPrint('Selected days: $_selectedDays');

      // Load participants
      if (widget.schedule!.participants.isNotEmpty) {
        _participants = List.from(widget.schedule!.participants);
        debugPrint('Participants loaded: ${_participants.length}');

        // Load usernames for participants
        _loadUsernames();
      }
    } else {
      _selectedDuration = _durations.first;
      debugPrint('Creating new schedule');
    }
  }

  // Separate method to load usernames for better organization
  Future<void> _loadUsernames() async {
    for (var participant in _participants) {
      _usernameCache[participant.userId] = participant.userId; // Default value
    }

    try {
      // Load all usernames in parallel
      await Future.wait(_participants.map((participant) async {
        final username = await _findUsername(participant.userId);
        if (username != null) {
          _usernameCache[participant.userId] = username;
        }
      }));

      // Update UI after loading usernames
      if (mounted) {
        setState(() {
          debugPrint('Usernames loaded successfully');
        });
      }
    } catch (e) {
      debugPrint('Error loading usernames: $e');
    }
  }

  Future<String?> _findUserId(String input) async {
    final normalizedInput = input.trim().toLowerCase();
    debugPrint('Searching for user with input: "$normalizedInput"');

    try {
      final response = await SupabaseManager.client
          .from('user_profiles')
          .select('id, email')
          .eq('email', normalizedInput)
          .single();
      debugPrint('Found user: $response');
      return response['id'];
    } catch (e) {
      debugPrint('Error finding user: $e');
      return null;
    }
  }

  Future<String?> _findUsername(String userId) async {
    debugPrint('Finding username for userId: $userId');
    try {
      final response = await SupabaseManager.client
          .from('user_details')
          .select('id, username')
          .eq('id', userId)
          .single();
      debugPrint('Found username: ${response['username']}');
      return response['username'];
    } catch (e) {
      debugPrint('Error finding username: $e');
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
      debugPrint('Error adding participant: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding participant: $error')),
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

      final scheduleId = _isEditMode ? widget.schedule!.id : const Uuid().v4();

      final updatedParticipants = _participants
          .map((p) => Participant(
                userId: p.userId,
                scheduleId: scheduleId,
                roles: p.roles,
                freeDays: p.freeDays,
              ))
          .toList();

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
        availableDays: selectedDays,
        duration: _selectedDuration!,
        ownerId: SupabaseManager.getCurrentUserId()!,
        participants: updatedParticipants,
        isFullySet: false,
      );

      if (_isEditMode) {
        debugPrint('Updating schedule: ${schedule.id}');
        await _scheduleService.updateSchedule(schedule);
        await _scheduleService.syncParticipants(
            scheduleId, updatedParticipants);
      } else {
        debugPrint('Creating new schedule: ${schedule.id}');
        await _scheduleService.createSchedule(schedule);

        // Send invitations
        for (var participant in updatedParticipants) {
          if (participant.userId != SupabaseManager.getCurrentUserId()) {
            try {
              await _notificationService.sendInvitation(
                schedule.id,
                participant.userId,
                participant.roles.map((r) => r.name).join(', '),
              );
            } catch (e) {
              debugPrint(
                  'Failed to send invitation to ${participant.userId}: $e');

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Schedule created, but failed to send invitation to ${_usernameCache[participant.userId] ?? participant.userId}'),
                  ),
                );
              }
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode
                ? 'Schedule updated successfully'
                : 'Schedule created successfully'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving schedule: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
        title: Text(_isEditMode ? 'Edit Schedule' : 'Create Schedule'),
        backgroundColor: AppColors.primary,
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
              AppColors.background,
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
                  padding: const EdgeInsets.all(16.0),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                          // Use a transparent color for the card
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
                                      children:
                                          _days.asMap().entries.map((entry) {
                                        final index = entry.key;
                                        final day = entry.value;
                                        return AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
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
                                          borderRadius:
                                              BorderRadius.circular(12),
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
                                            backgroundColor: AppColors.primary,
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
                                                      _participants.remove(p);
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
                        GradientButton(
                          text: _isEditMode
                              ? 'Update Schedule'
                              : 'Create Schedule',
                          onPressed: _saveSchedule,
                          isLoading: _isLoading,
                          enabled: !_isLoading,
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
