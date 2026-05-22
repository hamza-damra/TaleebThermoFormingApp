import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Plays the attention alert (sound + vibration) for a new Line Takeover
/// Request. Every failure is swallowed — a missing sound asset or a device
/// with no vibrator must never break the takeover dialog/banner flow.
class TakeoverNotificationService {
  /// Created lazily on first sound playback so a test double that overrides
  /// [alert] never instantiates a real platform-bound [AudioPlayer].
  AudioPlayer? _player;

  /// Asset key, relative to the `assets/` root (see pubspec `assets:`).
  static const String _soundAsset = 'sounds/takeover_alert.mp3';

  /// Fire-and-forget. Callers must NOT await this on a hot path.
  Future<void> alert() async {
    await Future.wait([_playSound(), _vibrate()]);
  }

  Future<void> _playSound() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource(_soundAsset));
    } catch (e) {
      debugPrint('TakeoverNotificationService: sound failed — $e');
    }
  }

  Future<void> _vibrate() async {
    try {
      // `== true` tolerates both the `bool` and `bool?` return shapes across
      // vibration package versions.
      if (await Vibration.hasVibrator() == true) {
        // Two ~400ms pulses — distinct from a normal tap haptic.
        Vibration.vibrate(pattern: const [0, 400, 200, 400]);
      }
    } catch (e) {
      debugPrint('TakeoverNotificationService: vibration failed — $e');
    }
  }

  void dispose() {
    _player?.dispose();
  }
}
