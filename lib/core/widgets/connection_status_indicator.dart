import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'dart:async';

class ConnectionStatusIndicator extends StatefulWidget {
  const ConnectionStatusIndicator({super.key});

  @override
  ConnectionStatusIndicatorState createState() =>
      ConnectionStatusIndicatorState();
}

class ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();

    // Initial connectivity check
    Connectivity().checkConnectivity().then((List<ConnectivityResult> results) {
      if (mounted) {
        setState(() {
          _isOffline =
              results.isEmpty || results.contains(ConnectivityResult.none);
        });
      }
    });

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (mounted) {
        setState(() {
          _isOffline =
              results.isEmpty || results.contains(ConnectivityResult.none);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(52),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Text(
            'Offline Mode',
            style: TextStyle(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Cancel the subscription to prevent memory leaks
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
