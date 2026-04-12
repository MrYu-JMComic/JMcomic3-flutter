# Keep JNI bridge names stable; native symbol lookup depends on these names.
-keep class opensource.jenny.Jni { *; }

# Preserve native method signatures across the app.
-keepclasseswithmembernames class * {
    native <methods>;
}
