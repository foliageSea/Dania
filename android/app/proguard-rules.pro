# Conscrypt's legacy platform adapters reference hidden Android SSL classes.
# These adapters are not used on the app's supported Android versions (API 26+).
-dontwarn com.android.org.conscrypt.SSLParametersImpl
-dontwarn org.apache.harmony.xnet.provider.jsse.SSLParametersImpl

# Shizuku creates UserService implementations by reflection in the shell
# process. Keep the concrete service and its Binder interface intact.
-keep class com.foliage.dania.toolbox.PrivilegedService { public <init>(); *; }
-keep class com.foliage.dania.toolbox.IPrivilegedService { *; }
-keep class com.foliage.dania.toolbox.IPrivilegedService$Stub { *; }
-keep class com.foliage.dania.toolbox.IPrivilegedService$Stub$Proxy { *; }
