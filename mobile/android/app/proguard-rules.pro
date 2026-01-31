# Flutter 앱용 ProGuard 규칙

# Flutter 엔진 클래스 유지
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Wear OS 관련 클래스 유지
-keep class com.google.android.gms.wearable.** { *; }
-dontwarn com.google.android.gms.wearable.**

# 네이티브 메서드 유지
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable 구현 클래스 유지
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Serializable 구현 클래스 유지
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# R 클래스 유지
-keepclassmembers class **.R$* {
    public static <fields>;
}

# 데이터 클래스 유지 (Kotlin)
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.** { *; }

# Wear OS Data Layer 메시지 클래스 유지
-keep class * extends com.google.android.gms.wearable.MessageClient$OnMessageReceivedListener { *; }
-keep class * extends com.google.android.gms.wearable.DataClient$OnDataChangedListener { *; }

# Play Core 라이브러리 (Flutter에서 사용하지만 실제로는 사용하지 않는 경우)
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
-keep class com.google.android.play.core.** { *; }

