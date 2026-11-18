import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_icons.dart';

// ---------------- Startup sound (played once, on a cold start only) ----------------
// It plays assets/sounds/startup.mp3 only when ALL of this is true:
//   * the file exists in the app
//   * the switch "Startup sound" in the Profile tab is on (default: on)
//   * the phone is NOT on silent or vibrate (checked on Android)
// If anything fails, there is simply no sound. Nothing else is affected.

const String kStartupSoundAsset = 'assets/sounds/startup.mp3';
const String _kStartupSoundKey = 'startup_sound';
const MethodChannel _audioChannel = MethodChannel('unibridge/audio');

class StartupSound {
  StartupSound._();

  // The switch in the Profile tab. Loaded once in main().
  static final enabled = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_kStartupSoundKey) ?? true;
    } catch (e) {
      debugPrint('Could not load the startup sound setting: $e');
    }
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kStartupSoundKey, value);
    } catch (e) {
      debugPrint('Could not save the startup sound setting: $e');
    }
  }

  // Android: true only when the ringer is in normal mode (not silent, not vibrate).
  static Future<bool> _phoneIsNotSilent() async {
    try {
      return await _audioChannel.invokeMethod<bool>('isRingerNormal') ?? false;
    } catch (e) {
      // Not Android, or the check failed: stay quiet.
      return false;
    }
  }

  static bool _played = false;

  // Call once when the app starts.
  static Future<void> playOnce() async {
    if (_played) return;
    _played = true;
    if (!enabled.value) return;
    if (!AppAssets.has(kStartupSoundAsset)) return;
    if (!await _phoneIsNotSilent()) return;
    try {
      final player = AudioPlayer();
      player.onPlayerComplete.listen((_) => player.dispose());
      // AssetSource paths start inside the assets/ folder.
      await player.play(AssetSource('sounds/startup.mp3'));
    } catch (e) {
      debugPrint('Could not play the startup sound: $e');
    }
  }
}
