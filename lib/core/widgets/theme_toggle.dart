import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../theme/theme_provider.dart';

class ThemeToggle extends StatefulWidget {
  const ThemeToggle({super.key});
  @override
  State<ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<ThemeToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    if (isDark) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        themeProvider.toggleTheme();
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2C3E50), const Color(0xFF34495E)]
                : [const Color(0xFFFFD700), const Color(0xFFFFA500)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.blue : Colors.orange).withValues(
                alpha: 0.3,
              ),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.rotate(
              angle: _animation.value * 3.14159,
              child: Icon(
                isDark ? Icons.nightlight_round : Icons.wb_sunny,
                color: Colors.white,
                size: 24,
              ),
            );
          },
        ),
      ),
    );
  }
}
