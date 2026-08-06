import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette
  static const Color background = Color(0xFF080C1F);
  static const Color surface = Color(0xFF0F1530);
  static const Color surfaceLight = Color(0xFF161D3C);
  static const Color card = Color(0xFF111829);

  // Accent
  static const Color cyan = Color(0xFF00D4FF);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color cyanDark = Color(0xFF0090CC);
  static const Color purpleDark = Color(0xFF4A27CC);

  // Status
  static const Color expired = Color(0xFFFF4757);
  static const Color expiringSoon = Color(0xFFFF9F43);
  static const Color valid = Color(0xFF2ED573);
  static const Color noExpiry = Color(0xFF747D8C);

  // Text
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB0B7C8);
  static const Color textMuted = Color(0xFF5E6887);

  // Borders
  static const Color borderSubtle = Color(0xFF1E2847);
  static const Color borderGlow = Color(0xFF00D4FF);

  // Gradient colors
  static const List<Color> backgroundGradient = [
    Color(0xFF080C1F),
    Color(0xFF0F1530),
    Color(0xFF140F2E),
  ];

  static const List<Color> cyanPurpleGradient = [
    Color(0xFF00D4FF),
    Color(0xFF7C4DFF),
  ];

  static const List<Color> purpleToCyan = [
    Color(0xFF7C4DFF),
    Color(0xFF00D4FF),
  ];
}

class AppGradients {
  static const LinearGradient background = LinearGradient(
    colors: AppColors.backgroundGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanPurple = LinearGradient(
    colors: AppColors.cyanPurpleGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleCyan = LinearGradient(
    colors: AppColors.purpleToCyan,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient cardGlow(Color color) => LinearGradient(
    colors: [color.withValues(alpha: 0.15), Colors.transparent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppTextStyles {
  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge!.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      );

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      );

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: AppColors.textSecondary,
      );

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!.copyWith(
        color: AppColors.textMuted,
      );
}

class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> glow(Color color, {double intensity = 0.4}) => [
    BoxShadow(
      color: color.withValues(alpha: intensity),
      blurRadius: 20,
      spreadRadius: 2,
    ),
  ];

  static List<BoxShadow> fab = [
    BoxShadow(
      color: AppColors.cyan.withValues(alpha: 0.5),
      blurRadius: 24,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];
}

/// Returns expiry color based on days remaining.
Color getExpiryColor(DateTime? expiryDate) {
  if (expiryDate == null) return AppColors.noExpiry;
  final days = expiryDate.difference(DateTime.now()).inDays;
  if (days < 0) return AppColors.expired;
  if (days <= 30) return AppColors.expiringSoon;
  return AppColors.valid;
}

/// Returns expiry label.
String getExpiryLabel(DateTime? expiryDate) {
  if (expiryDate == null) return 'No Expiry';
  final days = expiryDate.difference(DateTime.now()).inDays;
  if (days < 0) return 'Expired';
  if (days == 0) return 'Expires Today!';
  if (days <= 30) return 'Expires in $days days';
  return 'Valid';
}

/// Category icon map.
IconData getCategoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('id') || c.contains('passport') || c.contains('aadhar')) return Icons.badge_rounded;
  if (c.contains('medical') || c.contains('health')) return Icons.medical_services_rounded;
  if (c.contains('financial') || c.contains('bank') || c.contains('finance')) return Icons.account_balance_rounded;
  if (c.contains('vehicle') || c.contains('car') || c.contains('bike')) return Icons.directions_car_rounded;
  if (c.contains('education') || c.contains('school') || c.contains('degree')) return Icons.school_rounded;
  if (c.contains('insurance')) return Icons.shield_rounded;
  if (c.contains('property') || c.contains('house') || c.contains('land')) return Icons.home_rounded;
  if (c.contains('tax')) return Icons.receipt_long_rounded;
  return Icons.folder_special_rounded;
}

/// Category gradient accent color.
Color getCategoryColor(String category) {
  final c = category.toLowerCase();
  if (c.contains('id') || c.contains('passport')) return const Color(0xFF00D4FF);
  if (c.contains('medical') || c.contains('health')) return const Color(0xFFFF6B9D);
  if (c.contains('financial') || c.contains('bank')) return const Color(0xFF2ED573);
  if (c.contains('vehicle')) return const Color(0xFFFF9F43);
  if (c.contains('education')) return const Color(0xFF9B59B6);
  if (c.contains('insurance')) return const Color(0xFF3498DB);
  if (c.contains('property')) return const Color(0xFF1ABC9C);
  if (c.contains('tax')) return const Color(0xFFE67E22);
  return const Color(0xFF7C4DFF);
}
