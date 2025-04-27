import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/widgets/gradient_button.dart';
import '../core/services/notification_service.dart';
import '../models/permutation_request.dart';

class PermutationRequestScreen extends StatefulWidget {
  const PermutationRequestScreen({super.key});

  @override
  PermutationRequestScreenState createState() =>
      PermutationRequestScreenState();
}

class PermutationRequestScreenState extends State<PermutationRequestScreen> {
  final NotificationService _notificationService = NotificationService();
  bool _isLoading = false;

  Future<void> _handleRequest(String requestId, String status) async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _notificationService.updatePermutationRequestStatus(
          requestId, status);
      if (mounted) {
        Navigator.pop(context, true); // Signal to refresh schedule
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final request =
        ModalRoute.of(context)!.settings.arguments as PermutationRequest;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permutation Request'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withAlpha(50),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Permutation Request',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Swap ${request.senderDay} with ${request.receiverDay}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Text(
                  'Message: Please swap ${request.senderDay} with ${request.receiverDay}',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                GradientButton(
                  text: 'Accept',
                  onPressed: () => _handleRequest(request.id, 'accepted'),
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 16),
                GradientButton(
                  text: 'Reject',
                  onPressed: () => _handleRequest(request.id, 'rejected'),
                  isLoading: _isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
