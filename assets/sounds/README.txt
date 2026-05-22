Place the line-takeover notification sound here as:

    takeover_alert.mp3

A short (1-2s) attention tone. Until the real file is added,
TakeoverNotificationService.alert() fails gracefully (no sound) — the
takeover dialog/banner still appears and the device still vibrates.

The asset is loaded via audioplayers AssetSource('sounds/takeover_alert.mp3'),
declared under `flutter: assets: - assets/sounds/` in pubspec.yaml.
