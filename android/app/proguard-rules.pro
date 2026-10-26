# Keep JNI entry points — names are referenced from native code by signature.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class com.orchestrsim.blackhole.NativeBridge { *; }

# Compose handles its own keep rules via consumer files; nothing extra needed.
