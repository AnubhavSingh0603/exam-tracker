# R8 rules for release builds (minify + resource shrinking are on).
#
# Dart code (Riverpod, the app's models, sqflite's Dart side, Drift if added later)
# is AOT-compiled into libapp.so. R8 never sees it, so it needs no rules.
# Only the plugins' Java/Kotlin halves are shrunk. Most ship consumer rules; these
# cover the known gaps.

# Flutter references Play Core for deferred components, which this app doesn't use.
-dontwarn com.google.android.play.core.**

# device_calendar maps calendar/event models through Gson reflection. Without this
# rule R8 renames the fields and calendar sync silently breaks in release builds only.
-keep class com.builttoroam.devicecalendar.** { *; }
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Plugins that Dart reaches through JNI (package:jni): Dart looks their classes and
# methods up by name at run time, so R8 must not rename or drop them. v0.13.0 was
# built with a shared_preferences_android that works this way, R8 removed its
# getAll(), and every settings read failed (Google sign-in showed "Couldn't sign in").
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.github.dart_lang.jni.** { *; }

# package:jni runs Kotlin suspend functions from Dart and finds Kotlin's coroutine
# classes by name (Continuation, intrinsics.IntrinsicsKt, intrinsics.CoroutineSingletons;
# see jni's lib/src/kotlin.dart). Its consumer rules don't keep them, so v0.13.2
# still failed: ClassNotFoundException "kotlin/coroutines/intrinsics/...".
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }

# sqflite (native side)
-keep class com.tekartik.sqflite.** { *; }

# flutter_secure_storage -> Google Tink: annotation-only references
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

# ota_update: downloader + FileProvider + PackageInstaller receiver
-keep class sk.fourq.otaupdate.** { *; }

# Firebase Messaging (when firebase_messaging is added) ships its own consumer
# rules; nothing extra is needed here.
