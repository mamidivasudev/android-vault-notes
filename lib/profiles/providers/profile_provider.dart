import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/profile.dart';
import '../services/system_settings_service.dart';
import '../../vault_service.dart';
import '../../providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilesNotifier extends Notifier<List<Profile>> {
  final _system = SystemSettingsService();
  final _vault = VaultService();

  Future<void>? _initFuture;
  @override
  List<Profile> build() {
    ref.watch(vaultPathProvider);
    _initFuture = loadProfiles();
    return [];
  }

  Future<void> loadProfiles() async {
    final rawData = await _vault.loadProfiles();
    if (rawData.isEmpty) {
      // Initialize with defaults if empty
      state = [
        Profile(name: 'General', icon: 'volume-high', ringtoneVolume: 0.7, notificationVolume: 0.7, mediaVolume: 0.5, alarmVolume: 0.8, ringerMode: AudioProfileMode.normal, orderIndex: 0),
        Profile(name: 'Office', icon: 'briefcase', ringtoneVolume: 0.45, notificationVolume: 0.45, mediaVolume: 0.1, alarmVolume: 0.45, ringerMode: AudioProfileMode.vibrate, orderIndex: 1),
        Profile(name: 'Silent', icon: 'bell-slash', ringtoneVolume: 0.0, notificationVolume: 0.0, mediaVolume: 0.0, alarmVolume: 0.0, ringerMode: AudioProfileMode.silent, dndEnabled: true, orderIndex: 2),
        Profile(name: 'Outdoor', icon: 'sun', ringtoneVolume: 1.0, notificationVolume: 1.0, mediaVolume: 0.8, alarmVolume: 1.0, ringerMode: AudioProfileMode.normal, orderIndex: 3),
      ];
      _saveToVault();
    } else {
      state = rawData.map((p) => Profile.fromJson(p)).toList();
      // Ensure orderIndex consistency
      if (state.isNotEmpty && state.every((p) => p.orderIndex == 0)) {
        state = [
          for (int i = 0; i < state.length; i++)
            state[i].copyWith(orderIndex: i)
        ];
        _saveToVault();
      }
    }
  }

  Future<void> addProfile(Profile profile) async {
    await _initFuture;
    final newOrder = state.isEmpty ? 0 : state.map((p) => p.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    state = [...state, profile.copyWith(orderIndex: newOrder)];
  }

  Future<void> updateProfile(Profile profile) async {
    await _initFuture;
    state = [
      for (final p in state)
        if (p.id == profile.id) profile else p
    ];
  }

  Future<void> reorderProfiles(List<Profile> reorderedList) async {
    await _initFuture;
    state = [
      for (int i = 0; i < reorderedList.length; i++)
        reorderedList[i].copyWith(orderIndex: i)
    ];
  }

  Future<void> deleteProfile(String id) async {
    await _initFuture;
    state = state.where((p) => p.id != id).toList();
  }

  Future<void> resetToDefaults() async {
    await _initFuture;
    state = [
      Profile(name: 'General', icon: 'volume-high', ringtoneVolume: 0.7, notificationVolume: 0.7, mediaVolume: 0.5, alarmVolume: 0.8, ringerMode: AudioProfileMode.normal, orderIndex: 0),
      Profile(name: 'Office', icon: 'briefcase', ringtoneVolume: 0.45, notificationVolume: 0.45, mediaVolume: 0.1, alarmVolume: 0.45, ringerMode: AudioProfileMode.vibrate, orderIndex: 1),
      Profile(name: 'Silent', icon: 'bell-slash', ringtoneVolume: 0.0, notificationVolume: 0.0, mediaVolume: 0.0, alarmVolume: 0.0, ringerMode: AudioProfileMode.silent, dndEnabled: true, orderIndex: 2),
      Profile(name: 'Outdoor', icon: 'sun', ringtoneVolume: 1.0, notificationVolume: 1.0, mediaVolume: 0.8, alarmVolume: 1.0, ringerMode: AudioProfileMode.normal, orderIndex: 3),
    ];
  }

  Future<void> applyProfile(Profile profile) async {
    await _system.applyProfile(profile);
  }

  void _saveToVault() {
    try {
      _vault.saveProfiles(state.map((p) => p.toJson()).toList());
    } catch (e) {
      print('Error saving profiles to vault: $e');
    }
  }

  @override
  set state(List<Profile> value) {
    super.state = value;
    _saveToVault();
  }
}

final profilesProvider = NotifierProvider<ProfilesNotifier, List<Profile>>(() {
  return ProfilesNotifier();
});

class ActiveProfileNotifier extends Notifier<String?> {
  static const _key = 'active_profile_id';

  @override
  String? build() {
    _loadActiveProfile();
    return null;
  }

  Future<void> _loadActiveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_key);
  }

  @override
  set state(String? value) {
    super.state = value;
    _saveActiveProfile(value);
  }

  Future<void> _saveActiveProfile(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, value);
    }
  }
}

final activeProfileProvider = NotifierProvider<ActiveProfileNotifier, String?>(() {
  return ActiveProfileNotifier();
});

class PermissionsNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}

final permissionsGrantedProvider = NotifierProvider<PermissionsNotifier, bool>(() {
  return PermissionsNotifier();
});
