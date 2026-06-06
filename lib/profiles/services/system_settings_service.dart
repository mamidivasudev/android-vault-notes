import 'package:real_volume/real_volume.dart';
import '../models/profile.dart';

class SystemSettingsService {
  static final SystemSettingsService _instance = SystemSettingsService._internal();
  factory SystemSettingsService() => _instance;
  SystemSettingsService._internal();

  Future<bool> checkPermissions() async {
    // WRITE_SETTINGS is a special permission
    // real_volume handles some ringer mode permissions via ACCESS_NOTIFICATION_POLICY
    bool hasNotificationPolicyAccess = await RealVolume.isPermissionGranted() ?? false;
    return hasNotificationPolicyAccess;
  }

  Future<void> requestPermissions() async {
    await RealVolume.openDoNotDisturbSettings();
  }

  Future<void> applyProfile(Profile profile) async {
    try {
      // 1. Set Volumes first
      // Use small delays to ensure each setting is registered by the OS
      await RealVolume.setVolume(profile.ringtoneVolume, streamType: StreamType.RING);
      await Future.delayed(const Duration(milliseconds: 150));
      await RealVolume.setVolume(profile.notificationVolume, streamType: StreamType.NOTIFICATION);
      await Future.delayed(const Duration(milliseconds: 150));
      await RealVolume.setVolume(profile.mediaVolume, streamType: StreamType.MUSIC);
      await Future.delayed(const Duration(milliseconds: 150));
      await RealVolume.setVolume(profile.alarmVolume, streamType: StreamType.ALARM);
      await Future.delayed(const Duration(milliseconds: 150));

      // 2. Set Ringer Mode last
      switch (profile.ringerMode) {
        case AudioProfileMode.normal:
          await RealVolume.setRingerMode(RingerMode.NORMAL);
          break;
        case AudioProfileMode.vibrate:
          await RealVolume.setRingerMode(RingerMode.VIBRATE);
          break;
        case AudioProfileMode.silent:
          await RealVolume.setRingerMode(RingerMode.SILENT);
          break;
      }

      // 3. Handle DND explicitly if needed
      // Note: Setting RingerMode.SILENT often engages DND on Android.
      // If dndEnabled is true but mode is not silent, we could potentially do more,
      // but for now we ensure silent mode is the primary way to achieve "Total Silence".
    } catch (e) {
      print('Error applying profile: $e');
    }
  }

  Future<double> getCurrentVol(StreamType type) async {
    return await RealVolume.getCurrentVol(type) ?? 0.0;
  }

  Future<AudioProfileMode> getCurrentRingerMode() async {
    final mode = await RealVolume.getRingerMode();
    switch (mode) {
      case RingerMode.NORMAL:
        return AudioProfileMode.normal;
      case RingerMode.VIBRATE:
        return AudioProfileMode.vibrate;
      case RingerMode.SILENT:
        return AudioProfileMode.silent;
      default:
        return AudioProfileMode.normal;
    }
  }
}
