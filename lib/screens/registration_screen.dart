import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/services/firebase_auth_service.dart';
import '../core/utils/validators.dart';
import '../core/widgets/gradient_button.dart';
import '../core/widgets/custom_text_field.dart';
import '../core/widgets/connection_status_indicator.dart';
import '../core/widgets/theme_toggle.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  RegistrationScreenState createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final FirebaseAuthService _authService = FirebaseAuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordController.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  Future<void> _handleRegistration() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _usernameController.text.trim(),
        );
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: AppColors.background,
              elevation: 10,
              title: const Text(
                'Registration Successful',
                style: TextStyle(color: AppColors.primary),
              ),
              content: const Text(
                'Your account has been created successfully. You can now log in.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (mounted) {
                      Navigator.pop(context);
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primary.withAlpha(26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString().replaceAll('Exception: ', '');
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithGoogle();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
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
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.secondary.withAlpha(204),
              AppColors.secondary.withAlpha(153),
              AppColors.background,
            ],
            stops: const [0.0, 0.3, 0.9],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  const SliverAppBar(
                    title: Text(
                      'Registration',
                      style: TextStyle(fontSize: 32),
                    ),
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppColors.textOnPrimary,
                    elevation: 0,
                    floating: true,
                    snap: true,
                  ),
                  SliverFillRemaining(
                    hasScrollBody: true,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24.0),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: isSmallScreen ? double.infinity : 500,
                          ),
                          child: Card(
                            elevation: 10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            color: AppColors.background.withAlpha(230),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: FadeTransition(
                                opacity: _fadeInAnimation,
                                child: SlideTransition(
                                  position: _slideAnimation,
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Hero(
                                          tag: 'app_logo',
                                          child: Container(
                                            height: 120,
                                            width: 120,
                                            margin: const EdgeInsets.only(
                                                bottom: 24),
                                            decoration: BoxDecoration(
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary
                                                      .withAlpha(77),
                                                  blurRadius: 10,
                                                  spreadRadius: 2,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Image.asset(
                                                'assets/schedulo_logo.png',
                                                fit: BoxFit.contain,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Container(
                                                    decoration: BoxDecoration(
                                                      color: AppColors.primary
                                                          .withAlpha(26),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                    ),
                                                    child: const Icon(
                                                      Icons
                                                          .app_registration_rounded,
                                                      size: 60,
                                                      color: AppColors.primary,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Text(
                                          'Create Account',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 32),
                                        if (_errorMessage != null) ...[
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.error.withAlpha(26),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                  color: AppColors.error),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                        CustomTextField(
                                          label: 'Username',
                                          hintText: 'Enter your username',
                                          controller: _usernameController,
                                          prefixIcon: Icons.person,
                                          validator:
                                              Validators.validateUsername,
                                        ),
                                        const SizedBox(height: 16),
                                        CustomTextField(
                                          label: 'Email',
                                          hintText: 'Enter your email',
                                          controller: _emailController,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          prefixIcon: Icons.email,
                                          validator: Validators.validateEmail,
                                        ),
                                        const SizedBox(height: 16),
                                        CustomTextField(
                                          label: 'Password',
                                          hintText: 'Enter your password',
                                          controller: _passwordController,
                                          obscureText: _obscurePassword,
                                          prefixIcon: Icons.lock,
                                          suffixIcon: _obscurePassword
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          onSuffixIconPressed:
                                              _togglePasswordVisibility,
                                          validator:
                                              Validators.validatePassword,
                                        ),
                                        const SizedBox(height: 16),
                                        CustomTextField(
                                          label: 'Confirm Password',
                                          hintText: 'Confirm your password',
                                          controller:
                                              _confirmPasswordController,
                                          obscureText: _obscureConfirmPassword,
                                          prefixIcon: Icons.lock_outline,
                                          suffixIcon: _obscureConfirmPassword
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          onSuffixIconPressed:
                                              _toggleConfirmPasswordVisibility,
                                          validator: _validateConfirmPassword,
                                        ),
                                        const SizedBox(height: 32),
                                        GradientButton(
                                          text: 'Register',
                                          onPressed: _handleRegistration,
                                          isLoading: _isLoading,
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Divider(
                                                color: AppColors.textSecondary
                                                    .withAlpha(77),
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              child: Text(
                                                'OR',
                                                style: TextStyle(
                                                  color: AppColors.textSecondary
                                                      .withAlpha(153),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child: Divider(
                                                color: AppColors.textSecondary
                                                    .withAlpha(77),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        OutlinedButton.icon(
                                          onPressed: _isLoading
                                              ? null
                                              : _handleGoogleSignUp,
                                          icon: Image.asset(
                                            'assets/google_logo.png',
                                            height: 24,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return const Icon(Icons.login,
                                                  color: AppColors.primary);
                                            },
                                          ),
                                          label: const Text(
                                              'Continue with Google'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textPrimary,
                                            side: BorderSide(
                                              color: AppColors.primary
                                                  .withAlpha(77),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              'Already have an account?',
                                              style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pushNamed(
                                                    context, '/login');
                                              },
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.primary,
                                              ),
                                              child: const Text(
                                                'Log In',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        const ConnectionStatusIndicator(),
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
                  ),
                ],
              ),
              Positioned(
                top: 16,
                right: 16,
                child: const ThemeToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
