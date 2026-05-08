# ProGuard rules for Termisol
# Keep Flutter framework classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn io.flutter.embedding.**

# Keep xterm terminal emulator classes
-keep class com.xterm.** { *; }
-keep class xterm.** { *; }

# Keep dart:convert, dart:io related classes used via FFI
-keep class java.nio.charset.** { *; }

# Keep method channels
-keep class com.termisol.** { *; }

# General
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
