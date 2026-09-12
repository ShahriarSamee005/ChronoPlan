# ChronoPlan release (R8) rules.
#
# Why this file exists: flutter_local_notifications 17.2.4 persists scheduled
# notifications as JSON via Gson. R8 strips generic signatures by default, so
# the plugin's `new TypeToken<ArrayList<NotificationDetails>>() {}` throws
# IllegalStateException ("TypeToken must be created with a type argument"),
# loadScheduledNotifications() fails, and no alarms are ever scheduled.
# Release-only, because R8 does not run on debug builds.
#
# The plugin ships no consumer rules and bundles Gson 2.8.9, which predates
# Gson's own bundled consumer rules -- so nothing supplies these but us.
# Source: flutter_local_notifications README "Release build configuration",
# which points at the Gson rules and the plugin example's proguard-rules.pro.

## --- Gson rules (per flutter_local_notifications README) ---

# THE fix: Gson reads generic type information from the class file. R8 drops
# the Signature attribute by default, which is precisely what the exception
# above is reporting.
-keepattributes Signature

# NotificationDetails.scheduleMode is annotated @SerializedName(alternate=...);
# the annotation must survive for that field to deserialise.
-keepattributes *Annotation*

# The TypeToken instances are anonymous inner classes; keep the attributes that
# tie them to their enclosing class so their generic supertype stays readable.
-keepattributes InnerClasses,EnclosingMethod

# Gson references sun.misc.Unsafe, which does not exist on Android.
-dontwarn sun.misc.**

# The plugin's RuntimeTypeAdapterFactory implements TypeAdapterFactory and is
# registered on the Gson instance; R8 must not strip its interface information.
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Prevent R8 from leaving @SerializedName-annotated fields always null.
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Retain generic signatures of TypeToken and its subclasses on R8 3.0+.
# This is the rule that specifically clears the reported exception.
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

## --- flutter_local_notifications model classes ---

# Gson maps these by field name and reads them only reflectively. Under R8 full
# mode -- mandatory on AGP 9 -- fields that are written but never read in
# bytecode can be removed outright, and enum constant names can be renamed,
# silently corrupting the persisted schedule. Covers models/ and models/styles/.
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
