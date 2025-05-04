import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'schedule_creation_screen.dart';
import 'package:local_auth/local_auth.dart';
import '../core/constants/app_colors.dart';
import '../core/services/schedule_service.dart';
import '../models/schedule.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScheduleService _scheduleService = ScheduleService();
  final LocalAuthentication _auth = LocalAuthentication();
  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isError = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _currentUserId;
  late StreamSubscription<List<Schedule>> _scheduleSubscription;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut);
    _animationController.forward();

    setState(() {
      _isLoading = true;
      _isError = false;
    });

    _scheduleSubscription = _scheduleService.scheduleStream.listen(
      (schedules) {
        if (mounted) {
          setState(() {
            _schedules = schedules;
            _isLoading = false;
            _isError = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isError = true;
            _errorMessage = e.toString();
          });
        }
      },
    );

    _fetchSchedules();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canAuthenticate =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (mounted) {
        setState(() {
          _canUseBiometrics = canAuthenticate;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _canUseBiometrics = false;
        });
      }
    }
  }

  Future<bool> _authenticateWithBiometrics(BuildContext context) async {
    if (!_canUseBiometrics) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Biometric authentication not available on this device'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    final completer = Completer<bool>();
    try {
      String localizedReason;
      final biometrics = await _auth.getAvailableBiometrics();
      if (biometrics.contains(BiometricType.face)) {
        localizedReason =
            'Authenticate with Face ID to access schedule details';
      } else if (biometrics.contains(BiometricType.fingerprint)) {
        localizedReason =
            'Authenticate with fingerprint to access schedule details';
      } else {
        localizedReason = 'Authenticate to access schedule details';
      }

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );

      completer.complete(authenticated);
    } on PlatformException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'LockedOut':
          errorMessage = 'Too many attempts. Please try again later.';
          break;
        case 'NotAvailable':
          errorMessage = 'Authentication not available';
          break;
        case 'NotEnrolled':
          errorMessage = 'No biometric or device credentials enrolled';
          break;
        case 'PasscodeNotSet':
          errorMessage = 'Device passcode not set';
          break;
        default:
          errorMessage = 'Authentication error: ${e.message}';
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      completer.complete(false);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication error: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      completer.complete(false);
    }

    return completer.future;
  }

  Future<void> _authenticateAndNavigate(String scheduleId) async {
    HapticFeedback.selectionClick();

    final authenticated = await _authenticateWithBiometrics(context);

    if (authenticated && mounted) {
      // Add a small delay to ensure the biometric dialog is dismissed
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted) {
        Navigator.pushNamed(context, '/manage-schedule', arguments: scheduleId);
      }
    }
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
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
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
      if (mounted) {
        setState(() {
          _schedules = schedules;
          _isLoading = false;
        });
      }
    } catch (e) {
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScheduleCreationScreen(schedule: schedule),
      ),
    );
    if (result == true) {
      _fetchSchedules();
    }
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
              AppColors.primary.withValues(alpha: 0.5),
              AppColors.secondary.withValues(alpha: 0.5),
            ],
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
        elevation: 6,
        icon: const Icon(Icons.add, color: AppColors.textOnPrimary),
        label: const Text(
          'New Schedule',
          style: TextStyle(
              color: AppColors.textOnPrimary, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildAppBar(bool isLargeScreen) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 24.0 : 16.0,
        vertical: 12.0, // Reduced from 24.0
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Using Row instead of Column for horizontal layout when space is tight
          Expanded(
            child: Row(
              children: [
                // App logo in smaller screens
                if (!isLargeScreen)
                  Padding(
                    padding: const EdgeInsets.only(right: 10.0),
                    child: CircleAvatar(
                      radius: 18, // Smaller radius
                      backgroundImage:
                          const AssetImage('assets/schedule_app_logo.png'),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),

                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min, // Take minimum space
                    children: [
                      Text(
                        'Scheduling App',
                        style: TextStyle(
                          fontSize:
                              isLargeScreen ? 22 : 18, // Reduced from 28/24
                          fontWeight: FontWeight.w900,
                          color: AppColors.textOnPrimary,
                          shadows: [
                            BoxShadow(
                              blurRadius: 4, // Reduced from 6
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.6), // Less opacity
                              offset: const Offset(1, 1), // Smaller offset
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Manage your schedules with ease',
                        style: TextStyle(
                          fontSize:
                              isLargeScreen ? 14 : 12, // Reduced from 16/14
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Only show logo on right side in large screens
          if (isLargeScreen)
            CircleAvatar(
              radius: 24, // Reduced from 32
              backgroundImage: const AssetImage('assets/schedule_app_logo.png'),
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
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
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
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
            color: AppColors.warning.withValues(alpha: 0.8),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList(bool isLargeScreen) {
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
                color: AppColors.textPrimary,
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
                color: AppColors.textPrimary,
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
        // Dismissible code remains the same
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
                  child: const Text('Delete',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          );
          if (shouldDelete == true) {
            _deleteSchedule(schedule);
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
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.edit, color: AppColors.primary),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: AppColors.error),
      ),
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.95 + (_fadeAnimation.value * 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8.0, vertical: 4.0), // Reduced vertical padding
              child: Card(
                elevation: 4, // Reduced elevation
                shadowColor: Colors.black.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.background.withValues(alpha: 0.95),
                        AppColors.background.withValues(alpha: 0.85),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    splashColor: AppColors.primary.withValues(alpha: 0.2),
                    highlightColor: AppColors.primary.withValues(alpha: 0.1),
                    onTap: () => _authenticateAndNavigate(schedule.id),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0), // Reduced padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize
                            .min, // Add this to make the column take minimum required space
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(
                                    6.0), // Reduced padding
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  color: AppColors.primary,
                                  size: isLargeScreen ? 20 : 18, // Smaller icon
                                ),
                              ),
                              const SizedBox(width: 8), // Reduced spacing
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
                                              fontSize: isLargeScreen
                                                  ? 16
                                                  : 15, // Smaller font
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
                                                horizontal: 6,
                                                vertical: 2), // Smaller padding
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'Owner',
                                              style: TextStyle(
                                                fontSize: 10, // Smaller font
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(
                                        height: 4), // Reduced spacing
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2), // Smaller padding
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                                alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: statusColor.withValues(
                                                  alpha: 0.5),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            schedule.isFullySet
                                                ? 'Fully Set'
                                                : 'Draft',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: isLargeScreen
                                                  ? 11
                                                  : 10, // Smaller font
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Created: ${DateFormat('dd-MM-yy').format(schedule.createdAt)}',
                                          style: TextStyle(
                                            fontSize: isLargeScreen
                                                ? 11
                                                : 10, // Smaller font
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Optional description - show only if available
                          if (schedule.description != null &&
                              schedule.description!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 8.0,
                                  left: 6.0,
                                  right: 6.0), // Reduced padding
                              child: Text(
                                schedule.description!,
                                style: TextStyle(
                                  fontSize:
                                      isLargeScreen ? 13 : 12, // Smaller font
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.8),
                                ),
                                maxLines: 1, // Reduced to 1 line
                                overflow: TextOverflow.ellipsis,
                                semanticsLabel: schedule.description,
                              ),
                            ),
                          const SizedBox(height: 8), // Reduced spacing
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isOwner)
                                TextButton.icon(
                                  onPressed: () =>
                                      _navigateToCreateSchedule(schedule),
                                  icon: const Icon(Icons.edit,
                                      size: 16), // Smaller icon
                                  label: const Text('Edit',
                                      style: TextStyle(
                                          fontSize: 12)), // Smaller font
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4), // Smaller padding
                                    minimumSize: const Size(
                                        0, 32), // Smaller minimum size
                                  ),
                                ),
                              const SizedBox(width: 4), // Reduced spacing
                              ElevatedButton.icon(
                                onPressed: () =>
                                    _authenticateAndNavigate(schedule.id),
                                icon: const Icon(Icons.fingerprint,
                                    size: 16), // Smaller icon
                                label: const Text('View',
                                    style: TextStyle(
                                        fontSize: 12)), // Smaller font
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: AppColors.textOnPrimary,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4), // Smaller padding
                                  minimumSize:
                                      const Size(0, 32), // Smaller minimum size
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
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
            duration: const Duration(milliseconds: 1200),
            curve: Curves.elasticOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Image.asset(
              'assets/schedule_app_logo.png',
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
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Create your first schedule to get started',
            style: TextStyle(
              fontSize: 16,
              color: Colors.purple,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
