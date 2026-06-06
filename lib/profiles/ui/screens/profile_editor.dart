import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/profile.dart';
import '../../providers/profile_provider.dart';
import '../theme/app_theme.dart';

class ProfileEditorScreen extends ConsumerStatefulWidget {
  final Profile? profile;

  const ProfileEditorScreen({super.key, this.profile});

  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  late TextEditingController _nameController;
  late String _selectedIcon;
  late double _ringVolume;
  late double _notifVolume;
  late double _mediaVolume;
  late double _alarmVolume;
  late AudioProfileMode _ringerMode;
  late bool _dndEnabled;

  final List<String> _icons = ['volume-high', 'briefcase', 'bell-slash', 'sun', 'moon', 'bed', 'car', 'music'];

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _selectedIcon = p?.icon ?? 'volume-high';
    _ringVolume = p?.ringtoneVolume ?? 0.7;
    _notifVolume = p?.notificationVolume ?? 0.7;
    _mediaVolume = p?.mediaVolume ?? 0.5;
    _alarmVolume = p?.alarmVolume ?? 0.8;
    _ringerMode = p?.ringerMode ?? AudioProfileMode.normal;
    _dndEnabled = p?.dndEnabled ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

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

  void _save() {
    if (_nameController.text.isEmpty) return;

    final newProfile = Profile(
      id: widget.profile?.id,
      name: _nameController.text,
      icon: _selectedIcon,
      ringtoneVolume: _ringVolume,
      notificationVolume: _notifVolume,
      mediaVolume: _mediaVolume,
      alarmVolume: _alarmVolume,
      ringerMode: _ringerMode,
      dndEnabled: _dndEnabled,
    );

    if (widget.profile == null) {
      ref.read(profilesProvider.notifier).addProfile(newProfile);
    } else {
      ref.read(profilesProvider.notifier).updateProfile(newProfile);
    }

    Navigator.pop(context);
  }

  void _resetToDefaults() {
    final isOffice = (widget.profile?.name ?? _nameController.text).toLowerCase() == 'office';
    setState(() {
      _nameController.text = widget.profile?.name ?? (isOffice ? 'Office' : 'General');
      _selectedIcon = isOffice ? 'briefcase' : 'volume-high';
      _ringVolume = isOffice ? 0.45 : 0.7;
      _notifVolume = isOffice ? 0.45 : 0.7;
      _mediaVolume = isOffice ? 0.1 : 0.5;
      _alarmVolume = isOffice ? 0.45 : 0.8;
      _ringerMode = isOffice ? AudioProfileMode.vibrate : AudioProfileMode.normal;
      _dndEnabled = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reset to ${isOffice ? 'Office' : 'default'} values'), duration: const Duration(seconds: 1)));
  }

  Widget _buildSlider(String label, IconData icon, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.black87)),
              ],
            ),
            Text('${(value * 100).toInt()}%', style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'New Profile' : 'Edit Profile'),
        backgroundColor: Colors.transparent,
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Reset', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Profile Name',
                hintText: 'e.g. Office, Gym, Sleep',
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 32),
            const Text('Choose Icon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _icons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final name = _icons[index];
                  final isSelected = _selectedIcon == name;
                  return InkWell(
                    onTap: () => setState(() => _selectedIcon = name),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 50,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryColor : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(_getIconData(name), color: isSelected ? Colors.white : Colors.black54, size: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            const Text('Ringer Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            SegmentedButton<AudioProfileMode>(
              segments: const [
                ButtonSegment(value: AudioProfileMode.normal, label: Text('Normal'), icon: Icon(Icons.notifications)),
                ButtonSegment(value: AudioProfileMode.vibrate, label: Text('Vibrate'), icon: Icon(Icons.vibration)),
                ButtonSegment(value: AudioProfileMode.silent, label: Text('Silent'), icon: Icon(Icons.notifications_off)),
              ],
              selected: {_ringerMode},
              onSelectionChanged: (val) => setState(() => _ringerMode = val.first),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return AppTheme.primaryColor;
                  return const Color(0xFFF1F5F9);
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return Colors.white;
                  return Colors.black87;
                }),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Volume Levels', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 24),
            _buildSlider('Ringtone', Icons.ring_volume, _ringVolume, (v) => setState(() => _ringVolume = v)),
            _buildSlider('Notifications', Icons.notifications, _notifVolume, (v) => setState(() => _notifVolume = v)),
            _buildSlider('Media', Icons.music_note, _mediaVolume, (v) => setState(() => _mediaVolume = v)),
            _buildSlider('Alarms', Icons.alarm, _alarmVolume, (v) => setState(() => _alarmVolume = v)),
            
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Enable DND'),
              subtitle: const Text('Silence all interruptions'),
              value: _dndEnabled,
              onChanged: (val) => setState(() => _dndEnabled = val),
              tileColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              activeThumbColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
