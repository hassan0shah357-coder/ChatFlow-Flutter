// package com.example.android_permissions;

// import android.Manifest;
// import android.content.pm.PackageManager;
// import android.os.Build;

// import androidx.annotation.NonNull;

// import io.flutter.embedding.engine.plugins.FlutterPlugin;
// import io.flutter.plugin.common.MethodCall;
// import io.flutter.plugin.common.MethodChannel;
// import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
// import io.flutter.plugin.common.MethodChannel.Result;

// public class AndroidPermissionsPlugin implements FlutterPlugin, MethodCallHandler {
//     private MethodChannel channel;

//     @Override
//     public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
//         channel = new MethodChannel(binding.getBinaryMessenger(), "com.example.android_permissions");
//         channel.setMethodCallHandler(this);
//     }

//     @Override
//     public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
//         channel.setMethodCallHandler(null);
//     }

//     @Override
//     public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
//         if (call.method.equals("requestPermission")) {
//             String permission = call.argument("permission");
//             boolean granted = checkSelfPermission(permission);
//             result.success(granted);
//         } else {
//             result.notImplemented();
//         }
//     }

//     private boolean checkSelfPermission(String permission) {
//         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
//             int result = context.checkSelfPermission(permission);
//             return result == PackageManager.PERMISSION_GRANTED;
//         } else {
//             return true;
//         }
//     }
// }