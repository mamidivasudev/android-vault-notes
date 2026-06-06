import 'package:uuid/uuid.dart';

enum AudioProfileMode { normal, vibrate, silent }

class Profile {
  final String id;
  final String name;
  final String icon;
  final double ringtoneVolume;
  final double notificationVolume;
  final double mediaVolume;
  final double alarmVolume;
  final AudioProfileMode ringerMode;
  final bool dndEnabled;
  final int orderIndex;

  Profile({
    String? id,
    required this.name,
    required this.icon,
    this.ringtoneVolume = 0.5,
    this.notificationVolume = 0.5,
    this.mediaVolume = 0.5,
    this.alarmVolume = 0.5,
    this.ringerMode = AudioProfileMode.normal,
    this.dndEnabled = false,
    this.orderIndex = 0,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'ringtoneVolume': ringtoneVolume,
      'notificationVolume': notificationVolume,
      'mediaVolume': mediaVolume,
      'alarmVolume': alarmVolume,
      'ringerMode': ringerMode.index,
      'dndEnabled': dndEnabled ? 1 : 0,
      'orderIndex': orderIndex,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
      ringtoneVolume: map['ringtoneVolume'],
      notificationVolume: map['notificationVolume'],
      mediaVolume: map['mediaVolume'],
      alarmVolume: map['alarmVolume'],
      ringerMode: AudioProfileMode.values[map['ringerMode']],
      dndEnabled: map['dndEnabled'] == 1,
      orderIndex: map['orderIndex'] ?? 0,
    );
  }

  factory Profile.fromJson(Map<String, dynamic> json) => Profile.fromMap(json);

  Profile copyWith({
    String? name,
    String? icon,
    double? ringtoneVolume,
    double? notificationVolume,
    double? mediaVolume,
    double? alarmVolume,
    AudioProfileMode? ringerMode,
    bool? dndEnabled,
    int? orderIndex,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      ringtoneVolume: ringtoneVolume ?? this.ringtoneVolume,
      notificationVolume: notificationVolume ?? this.notificationVolume,
      mediaVolume: mediaVolume ?? this.mediaVolume,
      alarmVolume: alarmVolume ?? this.alarmVolume,
      ringerMode: ringerMode ?? this.ringerMode,
      dndEnabled: dndEnabled ?? this.dndEnabled,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }
}
