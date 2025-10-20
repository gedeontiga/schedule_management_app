import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/utils/firebase_manager.dart';
import '../core/widgets/expandable_description.dart';
import 'schedule_creation_screen.dart';
import 'package:local_auth/local_auth.dart';
import '../core/constants/app_colors.dart';
import '../core/services/schedule_service.dart';
import '../core/theme/theme_provider.dart';
import '../models/schedule.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScheduleService _scheduleService = ScheduleService();
  final LocalAuthentication _auth = LocalAuthentication();
  List<Schedule> _schedules = [];
  bool _isLoading = false;
  bool _isError = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late AnimationController _fabAnimController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _fabScaleAnimation;
  String? _currentUserId;
  late StreamSubscription<List<Schedule>> _scheduleSubscription;
  bool _canUseBiometrics = false;

  void _initializeScheduleStream() {
    final userId = FirebaseManager.currentUserId;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = 'User not logged in';
      });
      return;
    }

    _scheduleSubscription = _scheduleService.getUserSchedules(userId).listen(
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
  }

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseManager.currentUserId;

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _fabScaleAnimation = CurvedAnimation(
      parent: _fabAnimController,
      curve: Curves.elasticOut,
    );

    _animationController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fabAnimController.forward();
    });

    setState(() {
      _isLoading = true;
      _isError = false;
    });

    _initializeScheduleStream();
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
      _showSnackBar('Biometric authentication not available', isError: true);
      return false;
    }

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

      await _auth.stopAuthentication();

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );

      if (authenticated) {
        await _auth.stopAuthentication();
        return true;
      }
      return false;
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
      _showSnackBar(errorMessage, isError: true);
      return false;
    } catch (e) {
      _showSnackBar('Authentication error: ${e.toString()}', isError: true);
      return false;
    }
  }

  Future<void> _authenticateAndNavigate(String scheduleId) async {
    HapticFeedback.selectionClick();
    final authenticated = await _authenticateWithBiometrics(context);

    if (authenticated && mounted) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        Navigator.pushNamed(context, '/manage-schedule', arguments: scheduleId);
      }
    }
  }

  Future<void> _deleteSchedule(Schedule schedule) async {
    try {
      await _scheduleService.deleteSchedule(schedule.id);
      if (mounted) {
        _showSnackBar('${schedule.name} deleted successfully', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: ${e.toString()}', isError: true);
      }
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
    _animationController.dispose();
    _fabAnimController.dispose();
    _scheduleSubscription.cancel();
    _scheduleService.dispose();
    super.dispose();
  }

  Future<void> _fetchSchedules() async {
    try {
      setState(() {
        _isLoading = true;
        _isError = false;
      });

      final userId = FirebaseManager.currentUserId;
      if (userId == null) {
        _showSnackBar('Error: User not logged in', isError: true);
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = 'User not logged in';
        });
        return;
      }

      await _scheduleSubscription.cancel();
      _scheduleSubscription = _scheduleService.getUserSchedules(userId).listen(
        (schedules) {
          if (mounted) {
            setState(() {
              _schedules = schedules;
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            _showSnackBar('Error fetching schedules', isError: true);
            setState(() {
              _isLoading = false;
              _isError = true;
              _errorMessage = e.toString();
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error fetching schedules', isError: true);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    AppColors.darkBackground,
                    AppColors.darkSurface,
                    AppColors.darkBackground,
                  ]
                : [
                    AppColors.lightBackground,
                    AppColors.primary.withValues(alpha: 0.05),
                    AppColors.lightSurface,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(isLargeScreen, isDark, themeProvider),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _fetchSchedules,
                  color: AppColors.primary,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: _isLoading
                          ? _buildLoadingState(isLargeScreen, isDark)
                          : _isError
                              ? _buildErrorState(isDark)
                              : _schedules.isEmpty
                                  ? _buildEmptyState(isDark)
                                  : _buildScheduleList(isLargeScreen, isDark),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton.extended(
          onPressed: () => _navigateToCreateSchedule(),
          backgroundColor: AppColors.primary,
          tooltip: 'Create Schedule',
          elevation: 6,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text(
            'New Schedule',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(
      bool isLargeScreen, bool isDark, ThemeProvider themeProvider) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 24.0 : 16.0,
        vertical: 16.0,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Hero(
                  tag: 'app_logo',
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/schedulo.png',
                      width: 32,
                      height: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Schedulo',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 24 : 20,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Manage schedules with ease',
                        style: TextStyle(
                          fontSize: isLargeScreen ? 13 : 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.primary,
                ),
                onPressed: () {
                  themeProvider.toggleTheme();
                  HapticFeedback.lightImpact();
                },
                tooltip: 'Toggle theme',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.person_outline,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.primary,
                ),
                onPressed: () {
                  // Navigate to profile
                },
                tooltip: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isLargeScreen, bool isDark) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isLargeScreen ? 24.0 : 16.0,
        vertical: 16.0,
      ),
      child: ListView.builder(
        itemCount: 3,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardBackground : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Failed to load schedules',
              style: TextStyle(
                fontSize: 15,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _fetchSchedules,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleList(bool isLargeScreen, bool isDark) {
    final fullySetSchedules = _schedules.where((s) => s.isFullySet).toList();
    final draftSchedules = _schedules.where((s) => !s.isFullySet).toList();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: isLargeScreen ? 24.0 : 16.0,
          vertical: 16.0,
        ),
        children: [
          if (draftSchedules.isNotEmpty) ...[
            _buildSectionHeader(
                'Drafts', draftSchedules.length, isDark, Icons.drafts),
            const SizedBox(height: 12),
            ...draftSchedules.map((schedule) =>
                _buildScheduleCard(schedule, isLargeScreen, isDark)),
            const SizedBox(height: 24),
          ],
          if (fullySetSchedules.isNotEmpty) ...[
            _buildSectionHeader('Active Schedules', fullySetSchedules.length,
                isDark, Icons.check_circle),
            const SizedBox(height: 12),
            ...fullySetSchedules.map((schedule) =>
                _buildScheduleCard(schedule, isLargeScreen, isDark)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      String title, int count, bool isDark, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.primary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
      Schedule schedule, bool isLargeScreen, bool isDark) {
    final isOwner = schedule.ownerId == _currentUserId;
    final Color statusColor =
        schedule.isFullySet ? AppColors.success : AppColors.warning;

    return Dismissible(
      key: Key(schedule.id),
      direction: isOwner ? DismissDirection.horizontal : DismissDirection.none,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.error),
                  const SizedBox(width: 12),
                  const Text('Delete Schedule'),
                ],
              ),
              content: Text(
                  'Are you sure you want to delete "${schedule.name}"? This action cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
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
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.2),
              AppColors.primary.withValues(alpha: 0.05)
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit, color: AppColors.primary, size: 28),
            const SizedBox(height: 4),
            Text(
              'Edit',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.error.withValues(alpha: 0.05),
              AppColors.error.withValues(alpha: 0.2)
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete, color: AppColors.error, size: 28),
            const SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _fadeAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: 0.96 + (_fadeAnimation.value * 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Card(
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: isDark ? AppColors.darkCardBackground : Colors.white,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _authenticateAndNavigate(schedule.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.secondary
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.schedule,
                                  color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    schedule.name,
                                    style: TextStyle(
                                      fontSize: isLargeScreen ? 18 : 16,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withValues(
                                              alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: statusColor.withValues(
                                                  alpha: 0.5)),
                                        ),
                                        child: Text(
                                          schedule.isFullySet
                                              ? 'Active'
                                              : 'Draft',
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isOwner)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.star,
                                                  size: 12,
                                                  color: AppColors.primary),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Owner',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ],
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
                            schedule.description!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ExpandableDescription(
                            description: schedule.description!,
                            isLargeScreen: isLargeScreen,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Divider(
                            color: isDark
                                ? AppColors.darkDivider
                                : AppColors.lightDivider),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Created: ${DateFormat('MMM dd, yyyy').format(schedule.createdAt)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.people,
                              size: 14,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${schedule.participants.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isOwner)
                              TextButton.icon(
                                onPressed: () =>
                                    _navigateToCreateSchedule(schedule),
                                icon: const Icon(Icons.edit, size: 16),
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
                                  _authenticateAndNavigate(schedule.id),
                              icon: Icon(
                                _canUseBiometrics
                                    ? Icons.fingerprint
                                    : Icons.lock_open,
                                size: 16,
                              ),
                              label: const Text('View Details'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                elevation: 2,
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
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return RefreshIndicator(
      onRefresh: _fetchSchedules,
      color: AppColors.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.elasticOut,
                    builder: (context, double value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.2),
                                AppColors.secondary.withValues(alpha: 0.1),
                              ],
                            ),
                          ),
                          child: Image.asset(
                            'assets/schedulo.png',
                            width: 100,
                            height: 100,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'No schedules yet!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'Create your first schedule to get started.\nTap the button below or pull down to refresh.',
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Icon(
                    Icons.arrow_downward,
                    color: AppColors.primary.withValues(alpha: 0.5),
                    size: 32,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
