import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/profile.dart';
import '../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers.dart';

class ProfileCard extends ConsumerWidget {
  final Profile profile;
  final bool isActive;
  final VoidCallback onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMorePressed;
  final Widget? trailing;

  const ProfileCard({
    super.key,
    required this.profile,
    required this.isActive,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
    required this.onMorePressed,
    this.trailing,
  });

  IconData _getIconData(String name) {
    switch (name) {
      case 'volume-high': return Icons.volume_up;
      case 'briefcase': return Icons.work;
      case 'bell-slash': return Icons.notifications_off;
      case 'sun': return Icons.wb_sunny;
      case 'moon': return Icons.nightlight_round;
      case 'bed': return Icons.bed;
      case 'car': return Icons.directions_car;
      default: return Icons.music_note;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseFontSize = ref.watch(fontSizeProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.primaryColor.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppTheme.primaryColor.withOpacity(0.5) : const Color(0xFFE2E8F0),
          width: isActive ? 2.0 : 1,
        ),
        boxShadow: isActive ? [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.12),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          )
        ] : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onApply,
          onLongPress: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      _getIconData(profile.icon),
                      color: isActive ? Colors.white : Colors.black54,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            profile.name,
                            style: TextStyle(
                              fontSize: baseFontSize + 1,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${(profile.ringtoneVolume * 100).toInt()}% Vol • ${profile.ringerMode.name.toUpperCase()}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: baseFontSize - 2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 20)
                      .animate()
                      .scale(duration: 300.ms, curve: Curves.easeOutBack),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (profile.ringerMode == AudioProfileMode.silent || profile.dndEnabled)
                      const Icon(Icons.lock, size: 16, color: Colors.red),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.black54, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onMorePressed,
                    ),
                  ],
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}
