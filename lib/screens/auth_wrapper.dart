import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/utils/firebase_manager.dart';
import 'login_screen.dart';
import 'home_screen.dart';

/// Wrapper widget that handles authentication state and offline mode
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, connectivitySnapshot) {
        final isOffline =
            connectivitySnapshot.data?.contains(ConnectivityResult.none) ??
                false;

        // If offline, show offline screen
        if (isOffline) {
          return const OfflineModeScreen();
        }

        // If online, check authentication state
        return StreamBuilder(
          stream: FirebaseManager.authStateChanges,
          builder: (context, authSnapshot) {
            // Show loading while checking auth state
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading...'),
                    ],
                  ),
                ),
              );
            }

            // If user is signed in, go to home
            if (authSnapshot.hasData && authSnapshot.data != null) {
              return const HomeScreen();
            }

            // If not signed in, show login screen
            return const LoginScreen();
          },
        );
      },
    );
  }
}

/// Screen shown when the device is offline
class OfflineModeScreen extends StatelessWidget {
  const OfflineModeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Mode'),
        backgroundColor: Colors.orange,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'You\'re Offline',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'You can still view cached schedules, but some features may be limited.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  // Try to reconnect
                  final result = await Connectivity().checkConnectivity();
                  if (!result.contains(ConnectivityResult.none)) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Connection restored!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Still offline. Please check your connection.'),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Check Connection'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Navigate to cached schedules
                  Navigator.pushReplacementNamed(context, '/home');
                },
                child: const Text('View Cached Schedules'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
