import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scheduling_management_app/core/utils/supabase_manager.dart';
import '../core/constants/app_colors.dart';
import '../core/services/schedule_service.dart';
import '../models/schedule.dart';
import 'schedule_creation_screen.dart';

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
  bool _isError = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _currentUserId;
  late StreamSubscription<List<Schedule>> _scheduleSubscription;

  @override
  void initState() {
    super.initState();
    _currentUserId = SupabaseManager.getCurrentUserId();
    print('HomeScreen init with userId: $_currentUserId');
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();

    setState(() {
      _isLoading = true;
      _isError = false;
    });

    _scheduleSubscription = _scheduleService.scheduleStream.listen((schedules) {
      print('Home screen received schedules from stream: ${schedules.length}');
      if (mounted) {
        setState(() {
          _schedules = schedules;
          _isLoading = false;
          _isError = false;
        });
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    });

    _fetchSchedules();
  }

  Future<void> _deleteSchedule(Schedule schedule) async {
    try {
      final result = await _scheduleService.deleteSchedule(schedule.id);
      if (result) {
        if (mounted) {
          setState(() {
            _schedules.removeWhere((s) => s.id == schedule.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${schedule.name} deleted successfully'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete ${schedule.name}'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => _deleteSchedule(schedule),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scheduleSubscription.cancel();
    super.dispose();
  }

  Future<void> _fetchSchedules() async {
    try {
      setState(() {
        _isLoading = true;
        _isError = false;
      });

      final userId = SupabaseManager.getCurrentUserId();
      if (userId == null) {
        print('No user ID found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User not logged in'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = 'User not logged in';
        });
        return;
      }

      final schedules = await _scheduleService.getUserSchedules(userId);
      print('Fetched ${schedules.length} schedules directly: $schedules');

      if (mounted) {
        setState(() {
          _schedules = schedules;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching schedules: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching schedules: $e'),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _fetchSchedules,
            ),
          ),
        );
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _navigateToCreateSchedule([Schedule? schedule]) async {
    HapticFeedback.mediumImpact();

    // Debug logging to confirm schedule object is passed
    if (schedule != null) {
      print(
          'Navigating to edit schedule: id=${schedule.id}, name=${schedule.name}');
    } else {
      print('Navigating to create new schedule');
    }

    // Wait for the result from the navigation
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleCreationScreen(schedule: schedule),
      ),
    );

    // If we got a successful result, refresh schedules
    if (result == true) {
      _fetchSchedules();
    }
  }

  void _navigateToScheduleDetails(String scheduleId) {
    HapticFeedback.selectionClick();
    Navigator.pushNamed(context, '/biometric-auth', arguments: scheduleId);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withAlpha(239),
              AppColors.background.withAlpha(243),
            ],
            stops: const [0.0, 0.7],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isLargeScreen),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchSchedules,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _isLoading
                          ? _buildLoadingState(isLargeScreen)
                          : _isError
                              ? _buildErrorState()
                              : _schedules.isEmpty
                                  ? _buildEmptyState()
                                  : _buildScheduleList(isLargeScreen),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreateSchedule(),
        backgroundColor: AppColors.primary,
        tooltip: 'Create Schedule',
        elevation: 4,
        icon: const Icon(Icons.add, color: AppColors.textOnPrimary),
        label: const Text(
          'New Schedule',
          style: TextStyle(color: AppColors.textOnPrimary),
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isLargeScreen) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 32.0 : 16.0,
        vertical: 24.0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scheduling App',
                style: TextStyle(
                  fontSize: isLargeScreen ? 28 : 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textOnPrimary,
                  shadows: [
                    Shadow(
                      blurRadius: 4,
                      color: Colors.black.withAlpha(52),
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your schedules with ease',
                style: TextStyle(
                  fontSize: isLargeScreen ? 16 : 14,
                  color: AppColors.textOnPrimary.withAlpha(204),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          CircleAvatar(
            radius: isLargeScreen ? 32 : 24,
            backgroundImage: const AssetImage(
              'assets/images/schedule_app_logo.png',
            ),
            backgroundColor: AppColors.primary.withAlpha(52),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isLargeScreen) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 24.0 : 16.0,
        vertical: 16.0,
      ),
      child: ListView.builder(
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.background.withAlpha(180),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: AppColors.warning.withAlpha(200),
          ),
          const SizedBox(height: 16),
          Text(
            'Oops! Something went wrong',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Failed to load schedules',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchSchedules,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(bool isLargeScreen) {
    // Group schedules by status
    final fullySetSchedules = _schedules.where((s) => s.isFullySet).toList();
    final draftSchedules = _schedules.where((s) => !s.isFullySet).toList();

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 24.0 : 16.0,
        vertical: 16.0,
      ),
      children: [
        if (draftSchedules.isNotEmpty) ...[
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Drafts',
              style: TextStyle(
                fontSize: isLargeScreen ? 20 : 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withAlpha(220),
              ),
            ),
          ),
          ...draftSchedules
              .map((schedule) => _buildScheduleCard(schedule, isLargeScreen)),
          const SizedBox(height: 16),
        ],
        if (fullySetSchedules.isNotEmpty) ...[
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Complete Schedules',
              style: TextStyle(
                fontSize: isLargeScreen ? 20 : 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withAlpha(220),
              ),
            ),
          ),
          ...fullySetSchedules
              .map((schedule) => _buildScheduleCard(schedule, isLargeScreen)),
        ],
      ],
    );
  }

  Widget _buildScheduleCard(Schedule schedule, bool isLargeScreen) {
    final isOwner = schedule.ownerId == _currentUserId;
    final Color statusColor =
        schedule.isFullySet ? AppColors.success : AppColors.warning;

    return Dismissible(
      key: Key(schedule.id),
      direction: isOwner ? DismissDirection.horizontal : DismissDirection.none,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          final shouldDelete = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Schedule'),
              content:
                  Text('Are you sure you want to delete "${schedule.name}"?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );

          if (shouldDelete == true) {
            _deleteSchedule(schedule);
            // Return false so the Dismissible doesn't handle the dismiss,
            // we'll update the list ourselves after the API call completes
            return false;
          }
          return false;
        } else if (direction == DismissDirection.startToEnd) {
          _navigateToCreateSchedule(schedule);
          return false;
        }
        return false;
      },
      background: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(50),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: AppColors.primary),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(50),
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.95 + (_fadeAnimation.value * 0.05),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: Card(
                elevation: 4,
                shadowColor: Colors.black.withAlpha(39),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.background.withAlpha(243),
                        AppColors.background.withAlpha(217),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(13),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    splashColor: AppColors.primary.withAlpha(52),
                    highlightColor: AppColors.primary.withAlpha(26),
                    onTap: () => _navigateToScheduleDetails(schedule.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withAlpha(26),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  color: AppColors.primary,
                                  size: isLargeScreen ? 28 : 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            schedule.name,
                                            style: TextStyle(
                                              fontSize: isLargeScreen ? 20 : 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            semanticsLabel: schedule.name,
                                          ),
                                        ),
                                        if (isOwner)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withAlpha(30),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'Owner',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withAlpha(30),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: statusColor.withAlpha(78),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            schedule.isFullySet
                                                ? 'Fully Set'
                                                : 'Draft',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: isLargeScreen ? 13 : 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (schedule.description != null &&
                              schedule.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 12.0, left: 8.0, right: 8.0),
                              child: Text(
                                schedule.description!,
                                style: TextStyle(
                                  fontSize: isLargeScreen ? 15 : 14,
                                  color: AppColors.textSecondary.withAlpha(204),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                semanticsLabel: schedule.description,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isOwner)
                                TextButton.icon(
                                  onPressed: () =>
                                      _navigateToCreateSchedule(schedule),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Edit'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _navigateToScheduleDetails(schedule.id),
                                icon: const Icon(Icons.visibility, size: 18),
                                label: const Text('View'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.textOnPrimary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder(
            tween: Tween<double>(begin: 0.95, end: 1.0),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Image.asset(
              'assets/images/schedule_app_logo.png',
              width: 120,
              height: 120,
              opacity: const AlwaysStoppedAnimation(0.8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No schedules yet!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.warning.withAlpha(230),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Create your first schedule to get started',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary.withAlpha(204),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
