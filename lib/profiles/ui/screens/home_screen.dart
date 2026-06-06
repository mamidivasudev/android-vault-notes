import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/profile_provider.dart';
import '../widgets/profile_card.dart';
import 'profile_editor.dart';
import '../theme/app_theme.dart';
import '../../services/system_settings_service.dart';
import '../../providers/lock_provider.dart';
import '../../models/profile.dart';
import '../../../widgets/empty_state.dart';

class ProfilesHomeScreen extends ConsumerStatefulWidget {
  const ProfilesHomeScreen({super.key});

  @override
  ConsumerState<ProfilesHomeScreen> createState() => _ProfilesHomeScreenState();
}

class _ProfilesHomeScreenState extends ConsumerState<ProfilesHomeScreen> {
  final _system = SystemSettingsService();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final granted = await _system.checkPermissions();
    ref.read(permissionsGrantedProvider.notifier).state = granted;
  }

  void _verifyAndApply(Profile profile) {
    final isSensitive = profile.ringerMode == AudioProfileMode.silent || profile.dndEnabled;
    
    if (isSensitive) {
      final controller = TextEditingController();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Security Verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter passcode to activate "${profile.name}":', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'Passcode',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 7,
                onChanged: (val) {
                  if (val.length == 7) {
                    final requiredPass = ref.read(profileLockProvider);
                    if (val == requiredPass) {
                      Navigator.pop(context);
                      _apply(profile);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect passcode')));
                      controller.clear();
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final requiredPass = ref.read(profileLockProvider);
                if (controller.text == requiredPass) {
                  Navigator.pop(context);
                  _apply(profile);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incorrect passcode')));
                }
              }, 
              child: const Text('Verify'),
            ),
          ],
        ),
      );
    } else {
      _apply(profile);
    }
  }

  Future<void> _apply(Profile profile) async {
    await ref.read(profilesProvider.notifier).applyProfile(profile);
    ref.read(activeProfileProvider.notifier).state = profile.id;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile "${profile.name}" applied'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileProvider);
    final permissionsGranted = ref.watch(permissionsGrantedProvider);

    // Sort profiles
    final sortedProfiles = List<Profile>.from(profiles);
    sortedProfiles.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return Column(
      children: [
        if (!permissionsGranted)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'DND access is required to change ringer modes.',
                    style: TextStyle(color: Colors.amber, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await _system.requestPermissions();
                    _checkPermissions();
                  },
                  child: const Text('Grant'),
                ),
              ],
            ),
          ),
        Expanded(
          child: sortedProfiles.isEmpty
              ? EmptyState(
                  icon: Icons.volume_up_outlined,
                  title: 'No Profiles',
                  subtitle: 'Create custom profiles to manage your system settings.',
                  actionLabel: 'Create Profile',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => const ProfileEditorScreen()),
                  ),
                )
              : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedProfiles.length,
                      itemBuilder: (context, index) {
                        final profile = sortedProfiles[index];
                        return ProfileCard(
                          key: ValueKey(profile.id),
                          profile: profile,
                          isActive: activeId == profile.id,
                          onApply: () => _verifyAndApply(profile),
                          onEdit: () => _editProfile(profile),
                          onDelete: () => _confirmDeleteProfile(profile),
                          onMorePressed: () => _showProfileOptions(profile),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _editProfile(Profile profile) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => ProfileEditorScreen(profile: profile)),
    );
  }

  void _confirmDeleteProfile(Profile profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Profile?'),
        content: Text('Are you sure you want to delete "${profile.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(profilesProvider.notifier).deleteProfile(profile.id);
              Navigator.pop(context);
            }, 
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showProfileOptions(Profile profile) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppTheme.primaryColor),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                _editProfile(profile);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Profile', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteProfile(profile);
              },
            ),
          ],
        ),
      ),
    );
  }
}
