# Ignore missing optional ML Kit language packages (Chinese, Devanagari, Japanese, Korean)
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.mlkit.**
-dontwarn org.tensorflow.lite.**

# Keep classes for reflection
-keep class com.google.mlkit.** { *; }
-keep class org.tensorflow.lite.** { *; }
