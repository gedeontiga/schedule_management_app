import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:io';
import '../core/constants/app_colors.dart';
import '../core/widgets/gradient_button.dart';

class BiometricAuthScreen extends StatefulWidget {
  final String scheduleId;

  const BiometricAuthScreen({super.key, required this.scheduleId});

  @override
  BiometricAuthScreenState createState() => BiometricAuthScreenState();
}

class BiometricAuthScreenState extends State<BiometricAuthScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final _passwordController = TextEditingController();
  bool _isAuthenticating = false;
  bool _usePassword = false;
  String _errorMessage = '';

  Future<void> _authenticateWithBiometrics() async {
    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });
    try {
      bool authenticated = false;
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        authenticated = true;
      } else {
        authenticated = await _auth.authenticate(
          localizedReason: 'Authenticate to access the schedule',
          options: const AuthenticationOptions(biometricOnly: true),
        );
      }
      if (authenticated && mounted) {
        Navigator.pushReplacementNamed(context, '/manage-schedule',
            arguments: widget.scheduleId);
      } else {
        setState(() {
          _errorMessage = 'Authentication failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _usePassword = true; // Fallback to password if biometrics fail
      });
    } finally {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  Future<void> _authenticateWithPassword() async {
    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });
    try {
      // For demo purposes, assume password is validated against a stored hash
      // In a real app, validate against Supabase auth or a stored hash
      if (_passwordController.text == 'password123') {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/manage-schedule',
              arguments: widget.scheduleId);
        }
      } else {
        setState(() {
          _errorMessage = 'Invalid password';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withAlpha(204),
              AppColors.primary.withAlpha(153),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.fingerprint,
                    size: 80,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Authenticate to Continue',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _usePassword
                        ? 'Enter your password'
                        : Platform.isLinux ||
                                Platform.isMacOS ||
                                Platform.isWindows
                            ? 'Click to authenticate (desktop mode)'
                            : 'Use your fingerprint or device password',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (_usePassword) ...[
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GradientButton(
                      text: 'Authenticate with Password',
                      onPressed: _authenticateWithPassword,
                      isLoading: _isAuthenticating,
                    ),
                  ] else
                    GradientButton(
                      text: 'Authenticate',
                      onPressed: _authenticateWithBiometrics,
                      isLoading: _isAuthenticating,
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
