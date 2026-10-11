// lib/widgets/vitals_card.dart
import 'package:flutter/material.dart';
import '../app_theme.dart';

class VitalsCard extends StatelessWidget {
  final int heartRate;
  final String activity;
  final bool isWatchConnected;
  final bool isAnomaly;

  const VitalsCard({
    super.key,
    required this.heartRate,
    required this.activity,
    required this.isWatchConnected,
    this.isAnomaly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isAnomaly
              ? [
                  AppTheme.accentRed.withOpacity(0.2),
                  AppTheme.accentOrange.withOpacity(0.1),
                ]
              : [
                  AppTheme.bgCardHighlight,
                  AppTheme.bgCard,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isAnomaly
              ? AppTheme.accentRed.withOpacity(0.6)
              : AppTheme.borderSubtle,
          width: isAnomaly ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite, color: AppTheme.accentRed, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Nabız',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              _WatchBadge(connected: isWatchConnected),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                heartRate > 0 ? '$heartRate' : '--',
                style: TextStyle(
                  color: isAnomaly ? AppTheme.accentRed : AppTheme.textPrimary,
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'bpm',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (isAnomaly) ...[
                const Spacer(),
                const _PulsingIcon(),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _ActivityPill(activity: activity),
        ],
      ),
    );
  }
}

class _WatchBadge extends StatelessWidget {
  final bool connected;
  const _WatchBadge({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: connected
            ? AppTheme.accentGreen.withOpacity(0.15)
            : AppTheme.textMuted.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? AppTheme.accentGreen.withOpacity(0.4)
              : AppTheme.textMuted.withOpacity(0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.watch,
            size: 12,
            color: connected ? AppTheme.accentGreen : AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            connected ? 'Bağlı' : 'Bağlı Değil',
            style: TextStyle(
              color: connected ? AppTheme.accentGreen : AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityPill extends StatelessWidget {
  final String activity;
  const _ActivityPill({required this.activity});

  Color _getColor(String label) {
    switch (label.toLowerCase()) {
      case 'running':
      case 'koşuyor':
        return AppTheme.primaryCyan;
      case 'walking':
      case 'yürüyor':
        return AppTheme.accentGreen;
      case 'sitting':
      case 'oturuyor':
      case 'lying':
      case 'yatıyor':
        return AppTheme.textSecondary;
      case 'impact':
      case 'jumping':
        return AppTheme.accentOrange;
      default:
        return AppTheme.primaryBlue;
    }
  }

  IconData _getIcon(String label) {
    switch (label.toLowerCase()) {
      case 'running':
        return Icons.directions_run;
      case 'walking':
        return Icons.directions_walk;
      case 'sitting':
        return Icons.chair;
      case 'lying':
        return Icons.airline_seat_flat;
      case 'jumping':
      case 'impact':
        return Icons.warning_amber_rounded;
      case 'cycling':
        return Icons.directions_bike;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor(activity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_getIcon(activity), size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          activity,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon();

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: const Icon(
          Icons.warning_rounded,
          color: AppTheme.accentRed,
          size: 24,
        ),
      ),
    );
  }
}
