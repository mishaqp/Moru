-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# flutter_local_notifications stores scheduled notifications as Gson JSON and
# reads them back through anonymous TypeToken subclasses. R8 full mode drops
# their generic signatures ("Missing type parameter" on schedule/cancel and
# after reboot) and would rename the stored fields between builds.
-keepattributes Signature
-keepattributes *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }
