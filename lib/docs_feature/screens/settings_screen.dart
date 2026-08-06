import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/google_drive_service.dart';
import '../services/auth_service.dart';
import '../widgets/glass_container.dart';
import '../utils/app_theme.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import '../providers/document_provider.dart';
import 'manage_categories_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GoogleDriveService _driveService = GoogleDriveService();
  GoogleSignInAccount? _currentUser;
  bool _isBiometricEnabled = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await AuthService.isBiometricEnabled();
    if (mounted) {
      setState(() => _isBiometricEnabled = enabled);
    }
  }

  Future<void> _handleSignIn() async {
    final user = await _driveService.signIn();
    if (mounted) {
      setState(() => _currentUser = user);
      _showSnack(
        user != null ? 'Signed in as ${user.email}' : 'Sign-in failed',
        user != null ? AppColors.valid : AppColors.expired,
      );
    }
  }

  Future<void> _handleSignOut() async {
    await _driveService.signOut();
    if (mounted) setState(() => _currentUser = null);
  }

  Future<void> _handleBackup() async {
    if (_currentUser == null) return;
    setState(() => _isSyncing = true);
    try {
      await _driveService.backupData();
      if (mounted) _showSnack('Backup to Google Drive successful!', AppColors.valid);
    } catch (e) {
      if (mounted) _showSnack('Backup failed: ${e.toString()}', AppColors.expired);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleRestore() async {
    if (_currentUser == null) return;
    setState(() => _isSyncing = true);
    try {
      await _driveService.restoreData();
      if (mounted) {
        Provider.of<DocumentProvider>(context, listen: false).loadDocuments();
        _showSnack('Restore successful!', AppColors.valid);
      }
    } catch (e) {
      if (mounted) _showSnack('Restore failed: ${e.toString()}', AppColors.expired);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: color.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // ── Google Drive Section ─────────────────────────────
            // Handled centrally in the main app backup menu.

            // ── Preferences Section ─────────────────────────────
            const SizedBox(height: 28),
            _sectionLabel('Preferences'),
            const SizedBox(height: 10),

            GlassContainer(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _actionTile(
                    icon: Icons.category_rounded,
                    iconColor: AppColors.cyan,
                    title: 'Manage Categories',
                    subtitle: 'Add, edit, or remove document categories',
                    isLoading: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ManageCategoriesScreen()),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.15, end: 0),

            // ── Security Section ─────────────────────────────────
            const SizedBox(height: 28),
            _sectionLabel('Security'),
            const SizedBox(height: 10),

            GlassContainer(
              padding: EdgeInsets.zero,
              accentColor: _isBiometricEnabled ? AppColors.purple : null,
              showGlow: _isBiometricEnabled,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.fingerprint_rounded, color: AppColors.purple, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Biometric Lock',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Require fingerprint/face to unlock',
                            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      activeThumbColor: AppColors.purple,
                      activeTrackColor: AppColors.purple.withValues(alpha: 0.3),
                      inactiveThumbColor: AppColors.textMuted,
                      inactiveTrackColor: AppColors.borderSubtle,
                      value: _isBiometricEnabled,
                      onChanged: (val) async {
                        if (val) {
                          final authenticated = await AuthService.authenticateBiometrics();
                          if (authenticated && mounted) {
                            await AuthService.setBiometricEnabled(true);
                            setState(() => _isBiometricEnabled = true);
                            _showSnack('Biometric lock enabled', AppColors.valid);
                          }
                        } else {
                          await AuthService.setBiometricEnabled(false);
                          if (mounted) {
                            setState(() => _isBiometricEnabled = false);
                            _showSnack('Biometric lock disabled', AppColors.textMuted);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.15, end: 0),

            // ── About Section ────────────────────────────────────
            const SizedBox(height: 28),
            _sectionLabel('About'),
            const SizedBox(height: 10),

            GlassContainer(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _infoTile(
                    icon: Icons.security_rounded,
                    iconColor: AppColors.cyan,
                    title: 'LifeVault',
                    subtitle: 'Your personal document vault',
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                  _infoTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: AppColors.textMuted,
                    title: 'Version',
                    subtitle: '1.0.0',
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                  _infoTile(
                    icon: Icons.lock_outline_rounded,
                    iconColor: AppColors.textMuted,
                    title: 'Privacy',
                    subtitle: 'Documents stored locally on device',
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.15, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.inter(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isLoading,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withValues(alpha: 0.25)),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: iconColor, strokeWidth: 2),
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          Text(subtitle, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
