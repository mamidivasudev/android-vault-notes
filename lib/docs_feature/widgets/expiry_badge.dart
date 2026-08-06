import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// A color-coded badge showing document expiry status.
class ExpiryBadge extends StatelessWidget {
  final DateTime? expiryDate;
  final bool compact;

  const ExpiryBadge({super.key, required this.expiryDate, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (expiryDate == null) {
      if (compact) return const SizedBox.shrink();
      return _buildBadge(AppColors.noExpiry, Icons.all_inclusive, 'No Expiry');
    }

    final color = getExpiryColor(expiryDate);
    final label = getExpiryLabel(expiryDate);
    final days = expiryDate!.difference(DateTime.now()).inDays;

    IconData icon;
    if (days < 0) {
      icon = Icons.error_rounded;
    } else if (days <= 30) {
      icon = Icons.warning_amber_rounded;
    } else {
      icon = Icons.check_circle_rounded;
    }

    if (compact) {
      return Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 1),
          ],
        ),
      );
    }

    return _buildBadge(color, icon, label);
  }

  Widget _buildBadge(Color color, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
