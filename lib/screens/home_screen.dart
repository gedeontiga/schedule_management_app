import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:scheduling_management_app/core/utils/supabase_manager.dart';
import '../core/constants/app_colors.dart';
import '../core/services/schedule_service.dart';
import '../models/schedule.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScheduleService _scheduleService = ScheduleService();
  List<Schedule> _schedules = [];
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _currentUserId; // Add this to store current user ID

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseManager.getCurrentUserId();
    _fetchSchedules();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
    _scheduleService.scheduleStream.listen((schedules) {
      log('Stream updated with schedules: $schedules'); // Debug log
      setState(() {
        _schedules = schedules;
      });
    });
  }

  Future<void> _fetchSchedules() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = SupabaseManager.getCurrentUserId();
      if (userId == null) {
        log('No user ID found'); // Debug log
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: User not logged in')),
        );
        return;
      }
      final schedules = await _scheduleService.getUserSchedules(userId);
      log('Fetched schedules: $schedules'); // Debug log
      setState(() {
        _schedules = schedules;
      });
    } catch (e) {
      log('Error fetching schedules: $e'); // Debug log
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching schedules: $e')),
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
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withAlpha(206),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Welcome Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to Schedule App!',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                        const Text(
                          'Manage your schedules with ease',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ],
                    ),
                    CircleAvatar(
                      radius: 24,
                      backgroundImage:
                          AssetImage('assets/images/schedule_app_logo.png'),
                    ),
                  ],
                ),
              ),
              // Schedule List
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _schedules.isEmpty
                        ? _buildEmptyState()
                        : FadeTransition(
                            opacity: _fadeAnimation,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16.0),
                              itemCount: _schedules.length,
                              itemBuilder: (context, index) {
                                final schedule = _schedules[index];
                                final isOwner = schedule.ownerId ==
                                    _currentUserId; // Check if user is owner
                                return Card(
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      Navigator.pushNamed(
                                          context, '/biometric-auth',
                                          arguments: schedule.id);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      schedule.name,
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: AppColors
                                                            .textPrimary,
                                                      ),
                                                    ),
                                                    if (schedule.description !=
                                                        null)
                                                      Text(
                                                        schedule.description!,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          color: AppColors
                                                              .textSecondary,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    const SizedBox(height: 8),
                                                    Chip(
                                                      label: Text(
                                                        schedule.isFullySet
                                                            ? 'Fully Set'
                                                            : 'Draft',
                                                        style: TextStyle(
                                                          color: schedule
                                                                  .isFullySet
                                                              ? AppColors
                                                                  .success
                                                              : AppColors
                                                                  .warning,
                                                        ),
                                                      ),
                                                      backgroundColor: schedule
                                                              .isFullySet
                                                          ? AppColors.success
                                                              .withAlpha(26)
                                                          : AppColors.warning
                                                              .withAlpha(26),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: AppColors.primary),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              // Setup Schedule Button
                                              TextButton.icon(
                                                icon: const Icon(
                                                    Icons.edit_calendar,
                                                    color: AppColors.primary),
                                                label: const Text(
                                                  'Setup',
                                                  style: TextStyle(
                                                      color: AppColors.primary),
                                                ),
                                                onPressed: () {
                                                  Navigator.pushNamed(context,
                                                      '/manage-schedule',
                                                      arguments: schedule.id);
                                                },
                                              ),
                                              // Edit Button (visible only to owner)
                                              if (isOwner)
                                                IconButton(
                                                  icon: const Icon(Icons.edit,
                                                      color: AppColors.primary),
                                                  onPressed: () {
                                                    Navigator.pushNamed(context,
                                                        '/edit-schedule',
                                                        arguments: schedule);
                                                  },
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/create-schedule');
        },
        backgroundColor: AppColors.primary,
        tooltip: 'Create Schedule',
        child: const Icon(Icons.add, color: AppColors.textOnPrimary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/schedule_app_logo.png',
            width: 100,
            height: 100,
            opacity: const AlwaysStoppedAnimation(0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'No schedules yet!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const Text(
            'Tap the + button to create one.',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
