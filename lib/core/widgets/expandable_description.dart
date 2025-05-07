import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';

class ExpandableDescription extends StatefulWidget {
  final String description;
  final bool isLargeScreen;

  const ExpandableDescription({
    super.key,
    required this.description,
    required this.isLargeScreen,
  });

  @override
  State<ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
        HapticFeedback.lightImpact();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedCrossFade(
              firstChild: Text(
                widget.description,
                style: TextStyle(
                  fontSize: widget.isLargeScreen ? 13 : 12,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: widget.description,
              ),
              secondChild: Text(
                widget.description,
                style: TextStyle(
                  fontSize: widget.isLargeScreen ? 13 : 12,
                  color: AppColors.textSecondary,
                ),
                semanticsLabel: widget.description,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
            if (widget.description.length > 30)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _expanded ? 'Show less' : 'Show more',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
