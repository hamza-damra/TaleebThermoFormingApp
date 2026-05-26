# Keep tink-android classes to prevent R8 NullPointerException during minification
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
