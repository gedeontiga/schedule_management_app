import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/custom_text_field.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/schedule_service.dart';
import '../core/services/notification_service.dart';
import '../core/utils/firebase_manager.dart';
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

class ScheduleCreationScreenState extends State<ScheduleCreationScreen>
    with TickerProviderStateMixin {
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
  late AnimationController _headerAnimController;
  late AnimationController _cardAnimController;
  late Animation<double> _headerAnimation;
  late Animation<Offset> _cardSlideAnimation;

  @override
  void initState() {
    super.initState();
    _selectedDays = List.filled(7, false);
    _isEditMode = widget.schedule != null;

    _headerAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _cardAnimController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _headerAnimation =
        CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut);
    _cardSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _cardAnimController, curve: Curves.easeOutCubic));

    _headerAnimController.forward();
    _cardAnimController.forward();

    if (_isEditMode && widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _descriptionController.text = widget.schedule!.description ?? '';
      _selectedDuration = _durations.contains(widget.schedule!.duration)
          ? widget.schedule!.duration
          : _durations.first;
      _startDate = widget.schedule!.startDate;

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
      if (mounted) setState(() {});
    } catch (e) {
      // Failed to load usernames - not critical
    }
  }

  Future<String?> _findUserId(String input) async {
    final normalizedInput = input.trim().toLowerCase();
    try {
      final querySnapshot = await FirebaseManager.firestore
          .collection('users')
          .where('email', isEqualTo: normalizedInput)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) return null;
      return querySnapshot.docs.first.id;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _findUsername(String userId) async {
    try {
      final doc =
          await FirebaseManager.firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;
      return doc.data()?['username'] as String?;
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
              hourMinuteTextColor: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
              dialHandColor: AppColors.primary,
              dialBackgroundColor: isDark
                  ? AppColors.darkCardBackground
                  : AppColors.lightSurface,
            ),
          ),
          child: child!,
        );
      },
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
      _showSnackBar('Please enter both email and role', isError: true);
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
        });

        _showSnackBar('✓ Participant added successfully', isSuccess: true);
      } else {
        setState(() => _isLoading = false);
        _showSnackBar('User not found with email: $input', isError: true);
      }
    }).catchError((error) {
      setState(() => _isLoading = false);
      _showSnackBar('Error adding participant', isError: true);
    });
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDays.every((selected) => !selected)) {
      _showSnackBar('Please select at least one day', isError: true);
      return;
    }

    for (int i = 0; i < _days.length; i++) {
      if (_selectedDays[i]) {
        final startTime = _startTimeControllers[i].text;
        final endTime = _endTimeControllers[i].text;
        final startParts = startTime.split(':').map(int.parse).toList();
        final endParts = endTime.split(':').map(int.parse).toList();
        final startMinutes = startParts[0] * 60 + startParts[1];
        final endMinutes = endParts[0] * 60 + endParts[1];

        if (startMinutes >= endMinutes) {
          _showSnackBar('Start time must be before end time for ${_days[i]}',
              isError: true);
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
            ? widget.schedule!.participants
                .firstWhere((ep) => ep.userId == p.userId, orElse: () => p)
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
          userId: FirebaseManager.currentUserId!,
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
        ownerId: FirebaseManager.currentUserId!,
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
          if (participant.userId != FirebaseManager.currentUserId) {
            try {
              await _notificationService.sendInvitation(
                schedule.id,
                participant.userId,
                participant.roles.map((r) => r.name).join(', '),
              );
            } catch (e) {
              // Failed to send invitation - not critical, schedule still created
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        _showSnackBar(
          _isEditMode
              ? '✓ Schedule updated successfully'
              : '✓ Schedule created successfully',
          isSuccess: true,
        );
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message,
      {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess
                  ? Icons.check_circle
                  : (isError ? Icons.error_outline : Icons.info_outline),
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess
            ? AppColors.success
            : (isError ? AppColors.error : AppColors.primary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _participantController.dispose();
    _roleController.dispose();
    _headerAnimController.dispose();
    _cardAnimController.dispose();
    for (var controller in _startTimeControllers) {
      controller.dispose();
    }
    for (var controller in _endTimeControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildDateSelector(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.5,
        ),
        color: isDark ? AppColors.darkSurface : Colors.white,
      ),
      child: InkWell(
        onTap: () => _selectDate(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('MMM dd, yyyy').format(_startDate),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _startDate.isBefore(DateTime.now()) ? DateTime.now() : _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: isDark ? AppColors.darkSurface : Colors.white,
              onSurface: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
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
      _showSnackBar(
          'Start date set to ${DateFormat('MMM dd, yyyy').format(picked)}',
          isSuccess: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Schedule' : 'Create Schedule'),
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Quick Tips'),
                    content: const Text(
                      '• Select days and set working hours\n'
                      '• Add participants with their roles\n'
                      '• Choose schedule duration\n'
                      '• Set a future start date',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it!'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.darkBackground, AppColors.darkSurface]
                : [AppColors.lightBackground, AppColors.lightSurface],
          ),
        ),
        child: SafeArea(
          child: _isLoading && _participants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Loading...',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              : SlideTransition(
                  position: _cardSlideAnimation,
                  child: FadeTransition(
                    opacity: _headerAnimation,
                    child: SingleChildScrollView(
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
                                _buildInfoCard(isDark, isSmallScreen),
                                const SizedBox(height: 16),
                                _buildDaysCard(isDark, isSmallScreen),
                                const SizedBox(height: 16),
                                _buildParticipantsCard(isDark, isSmallScreen),
                                const SizedBox(height: 24),
                                _buildSaveButton(isSmallScreen),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(bool isDark, bool isSmallScreen) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? AppColors.darkCardBackground : Colors.white,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.info_outline,
              color: AppColors.primary, size: 24),
        ),
        title: const Text('Basic Information',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        children: [
          CustomTextField(
            label: 'Schedule Name',
            hintText: 'e.g., Weekly Team Schedule',
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
            hintText: 'Brief description of the schedule',
            controller: _descriptionController,
            prefixIcon: Icons.description,
          ),
        ],
      ),
    );
  }

  Widget _buildDaysCard(bool isDark, bool isSmallScreen) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? AppColors.darkCardBackground : Colors.white,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.calendar_month,
              color: AppColors.secondary, size: 24),
        ),
        title: const Text('Schedule Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start Date',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _buildDateSelector(isDark),
              const SizedBox(height: 20),
              Text(
                'Available Days',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _days.asMap().entries.map((entry) {
                  final index = entry.key;
                  final day = entry.value;
                  return FilterChip(
                    label: Text(day.substring(0, 3)),
                    selected: _selectedDays[index],
                    onSelected: (selected) {
                      setState(() {
                        _selectedDays[index] = selected;
                      });
                    },
                    selectedColor: AppColors.primary,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _selectedDays[index]
                          ? Colors.white
                          : (isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary),
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              ..._days
                  .asMap()
                  .entries
                  .where((entry) => _selectedDays[entry.key])
                  .map((entry) {
                int index = entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _days[index],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _startTimeControllers[index],
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Start',
                                  suffixIcon:
                                      const Icon(Icons.access_time, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  isDense: true,
                                ),
                                onTap: () => _selectTime(
                                    context, _startTimeControllers[index]),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _endTimeControllers[index],
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'End',
                                  suffixIcon:
                                      const Icon(Icons.access_time, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  isDense: true,
                                ),
                                onTap: () => _selectTime(
                                    context, _endTimeControllers[index]),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Duration',
                  prefixIcon: const Icon(Icons.timer, color: AppColors.primary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                initialValue: _selectedDuration,
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
                  if (value == null) return 'Please select a duration';
                  return null;
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard(bool isDark, bool isSmallScreen) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? AppColors.darkCardBackground : Colors.white,
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.tertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.group, color: AppColors.tertiary, size: 24),
        ),
        title: Text(
          'Participants (${_participants.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  label: 'Email',
                  hintText: 'user@example.com',
                  controller: _participantController,
                  prefixIcon: Icons.email,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomTextField(
                  label: 'Role',
                  hintText: 'e.g., Manager',
                  controller: _roleController,
                  prefixIcon: Icons.badge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _addRoleToParticipant,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add),
              label: const Text('Add Participant'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_participants.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _participants.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = _participants[index];
                return Container(
                  decoration: BoxDecoration(
                    color:
                        isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      child: Text(
                        (_usernameCache[p.userId] ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      _usernameCache[p.userId] ?? 'Loading...',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      p.roles.map((r) => r.name).join(', '),
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.error),
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _participants.remove(p);
                              });
                              _showSnackBar('Participant removed',
                                  isSuccess: true);
                            },
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton(bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 0 : 48.0),
      child: GradientButton(
        text: _isEditMode ? 'Update Schedule' : 'Create Schedule',
        onPressed: _saveSchedule,
        isLoading: _isLoading,
        enabled: !_isLoading,
      ),
    );
  }
}
