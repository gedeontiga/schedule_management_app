import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscureText;
  final IconData prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconPressed;
  final String? Function(String?)? validator;
  final bool enabled;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    required this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.validator,
    this.enabled = true,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _focusAnimation;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _focusAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
      if (_focusNode.hasFocus) {
        _controller.forward();
        HapticFeedback.lightImpact();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryTextColor = theme.textTheme.bodySmall?.color;

    return AnimatedBuilder(
      animation: _focusAnimation,
      builder: (context, child) {
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(_focusAnimation.value * 0.01)
            ..scaleAdjoint(1.0 + _focusAnimation.value * 0.02),
          alignment: Alignment.center,
          child: Container(
            margin: EdgeInsets.only(bottom: 4 + _focusAnimation.value * 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: _isFocused ? 13 : 14,
                    fontWeight: _isFocused ? FontWeight.w600 : FontWeight.w500,
                    color: _isFocused
                        ? theme.colorScheme.primary
                        : secondaryTextColor,
                  ),
                  child: Text(widget.label),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: _isFocused
                        ? const LinearGradient(
                            colors: [
                              AppColors.secondary,
                              AppColors.tertiary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: _isFocused
                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                            : theme.shadowColor.withValues(alpha: 0.1),
                        blurRadius: _isFocused ? 20 : 10,
                        offset: Offset(0, _isFocused ? 8 : 4),
                        spreadRadius: _isFocused ? 2 : 0,
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(_isFocused ? 2 : 1),
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.enabled
                          ? theme.cardColor
                          : theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isFocused
                            ? Colors.transparent
                            : theme.dividerColor.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: TextFormField(
                      focusNode: _focusNode,
                      controller: widget.controller,
                      obscureText: widget.obscureText,
                      keyboardType: widget.keyboardType,
                      validator: widget.validator,
                      enabled: widget.enabled,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: secondaryTextColor?.withValues(alpha: 0.5),
                          fontSize: 14,
                        ),
                        prefixIcon: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            widget.prefixIcon,
                            color: _isFocused
                                ? theme.colorScheme.primary
                                : secondaryTextColor,
                            size: 20,
                          ),
                        ),
                        suffixIcon: widget.suffixIcon != null
                            ? IconButton(
                                icon: Icon(
                                  widget.suffixIcon,
                                  color: _isFocused
                                      ? theme.colorScheme.primary
                                      : secondaryTextColor,
                                  size: 20,
                                ),
                                onPressed: widget.onSuffixIconPressed,
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
