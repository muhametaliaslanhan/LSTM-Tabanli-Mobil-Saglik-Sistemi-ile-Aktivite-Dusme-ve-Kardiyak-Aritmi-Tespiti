// lib/widgets/status_badge.dart
import 'package:flutter/material.dart';
import '../app_theme.dart';

class StatusBadge extends StatelessWidget {
  final bool isActive;
  final String activeLabel;
  final String inactiveLabel;
  final Color? activeColor;

  const StatusBadge({
    super.key,
    required this.isActive,
    this.activeLabel = 'Aktif',
    this.inactiveLabel = 'Pasif',
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? (activeColor ?? AppTheme.accentGreen) : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? activeLabel : inactiveLabel,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
