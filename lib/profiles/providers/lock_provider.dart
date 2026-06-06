import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileLockNotifier extends Notifier<String> {
  static const _key = 'profile_lock_password';

  @override
  String build() {
    _loadLock();
    return '1851421';
  }

  Future<void> _loadLock() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> setLock(String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, newPassword);
    state = newPassword;
  }
}

final profileLockProvider = NotifierProvider<ProfileLockNotifier, String>(ProfileLockNotifier.new);
