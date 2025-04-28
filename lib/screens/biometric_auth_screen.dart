import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:supabase_flutter/supabase_flutter.dart';
// import '../core/constants/app_colors.dart';
// import '../core/widgets/gradient_button.dart';

class BiometricAuthScreen extends StatefulWidget {
  final String scheduleId;
  const BiometricAuthScreen({super.key, required this.scheduleId});

  @override
  BiometricAuthScreenState createState() => BiometricAuthScreenState();
}

class BiometricAuthScreenState extends State<BiometricAuthScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isAuthenticating = false;
  String _errorMessage = '';
  bool _canUseBiometrics = false;
  bool _usePasswordFallback = false;
  String _authInstruction = 'Checking authentication methods...';

  @override
  void initState() {
    super.initState();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    // Clean up controllers
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    try {
      final canAuthenticate =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      String instruction;

      if (canAuthenticate) {
        final biometrics = await _auth.getAvailableBiometrics();
        if (biometrics.contains(BiometricType.face)) {
          instruction = 'Use Face ID or device credentials';
        } else if (biometrics.contains(BiometricType.fingerprint)) {
          instruction = 'Use fingerprint or device credentials';
        } else {
          instruction = 'Use PIN, pattern, or password';
        }
      } else {
        instruction = 'Device authentication not supported';
      }

      if (mounted) {
        setState(() {
          _canUseBiometrics = canAuthenticate;
          _authInstruction = instruction;
          _usePasswordFallback = !canAuthenticate;
          _errorMessage = '';
        });

        // Automatically start authentication if biometrics are available
        if (canAuthenticate) {
          // Add delay to ensure UI is fully rendered
          Future.delayed(const Duration(milliseconds: 300), () {
            _authenticateWithBiometrics();
          });
        }
      }
    } catch (e) {
      print('Error checking biometrics: $e');
      if (mounted) {
        setState(() {
          _canUseBiometrics = false;
          _authInstruction = 'Authentication not available';
          _usePasswordFallback = true;
          _errorMessage = 'Authentication not available on this device';
        });
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (!_canUseBiometrics) {
      setState(() {
        _errorMessage = 'Authentication not supported on this device';
        _usePasswordFallback = true;
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access the schedule',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );

      // Make sure to check if the widget is still mounted before proceeding
      if (!mounted) return;

      if (authenticated) {
        // Add a small delay to ensure the authentication UI is dismissed
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) {
          // Navigate using pushReplacement to avoid keeping the auth screen in the stack
          Navigator.pushReplacementNamed(context, '/manage-schedule',
              arguments: widget.scheduleId);
        }
      } else {
        setState(() {
          _errorMessage = 'Authentication failed';
          _usePasswordFallback = true;
        });
      }
    } catch (e) {
      String errorMessage;
      if (e.toString().contains('no_fragment_activity')) {
        errorMessage =
            'Authentication not supported on this device configuration';
        setState(() {
          _usePasswordFallback = true;
        });
      } else if (e.toString() == auth_error.notAvailable) {
        errorMessage = 'Authentication not available';
      } else if (e.toString() == auth_error.notEnrolled) {
        errorMessage = 'No biometric or device credentials enrolled';
      } else if (e.toString() == auth_error.passcodeNotSet) {
        errorMessage = 'Device passcode not set';
      } else {
        errorMessage = 'Error: $e';
      }

      setState(() {
        _errorMessage = errorMessage;
        if (!e.toString().contains('no_fragment_activity')) {
          _usePasswordFallback = true;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  Future<void> _authenticateWithSupabasePassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password';
      });
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorMessage = '';
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (response.session != null) {
        // Navigate using pushReplacement to avoid keeping the auth screen in the stack
        Navigator.pushReplacementNamed(context, '/manage-schedule',
            arguments: widget.scheduleId);
      } else {
        setState(() {
          _errorMessage = 'Invalid credentials';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Authentication failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authentication Required'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Icon(
              _canUseBiometrics ? Icons.fingerprint : Icons.lock,
              size: 64,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            Text(
              _authInstruction,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (_canUseBiometrics && !_usePasswordFallback) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text('Authenticate'),
                onPressed:
                    _isAuthenticating ? null : _authenticateWithBiometrics,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _usePasswordFallback = true;
                  });
                },
                child: const Text('Use email and password instead'),
              ),
            ],
            if (_usePasswordFallback) ...[
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                enabled: !_isAuthenticating,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                enabled: !_isAuthenticating,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isAuthenticating
                    ? null
                    : _authenticateWithSupabasePassword,
                child: _isAuthenticating
                    ? const CircularProgressIndicator()
                    : const Text('Sign In'),
              ),
              if (_canUseBiometrics) ...[
                TextButton(
                  onPressed: _isAuthenticating
                      ? null
                      : () {
                          setState(() {
                            _usePasswordFallback = false;
                          });
                          _authenticateWithBiometrics();
                        },
                  child: const Text('Use biometric authentication instead'),
                ),
              ],
            ],
            if (_isAuthenticating) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
