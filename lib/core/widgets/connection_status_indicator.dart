import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class ConnectionStatusIndicator extends StatefulWidget {
  const ConnectionStatusIndicator({super.key});

  @override
  ConnectionStatusIndicatorState createState() =>
      ConnectionStatusIndicatorState();
}

class ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator> {
  bool _isOffline = false;
  late Stream<List<ConnectivityResult>> _connectivityStream;

  @override
  void initState() {
    super.initState();
    _connectivityStream = Connectivity().onConnectivityChanged;

    _connectivityStream.listen((List<ConnectivityResult> results) {
      setState(() {
        _isOffline =
            results.isEmpty || results.contains(ConnectivityResult.none);
      });
    });

    Connectivity().checkConnectivity().then((List<ConnectivityResult> results) {
      setState(() {
        _isOffline =
            results.isEmpty || results.contains(ConnectivityResult.none);
      });
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
}
