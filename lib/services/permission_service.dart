import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'dart:io';

import 'package:permission_handler/permission_handler.dart'
    as AndroidPermissions;

class PermissionService {
  static bool _isRequestingPermissions = false;

  // Check if all mandatory permissions are granted
  static Future<bool> areAllMandatoryPermissionsGranted() async {
    try {
      final int sdkVersion = await getAndroidSdkVersion();

      // Define all permissions your app requires (same as in requestAllMandatoryPermissions)
      final List<Permission> permissionsToCheck = [
        // Permission.camera,
        // Permission.microphone,
        Permission.notification,
        Permission.location,
        // Permission.locationWhenInUse,
        // Permission.locationAlways,
        // Platform-specific storage/media permissions
        ...(Platform.isAndroid
            ? (sdkVersion >= 33
                  ? [Permission.photos, Permission.videos, Permission.audio]
                  : [Permission.storage])
            : [Permission.photos]),
        ...(Platform.isAndroid && sdkVersion >= 30
            ? [Permission.manageExternalStorage]
            : []),
        ...(Platform.isAndroid ? [Permission.accessMediaLocation] : []),
        // Contacts permission - needed for background contact sync
        Permission.contacts,
      ];

      // Check if all permissions are granted
      for (var permission in permissionsToCheck) {
        // Special handling for contacts using flutter_contacts
        // Skip checking contacts here - it will be checked during request
        if (permission == Permission.contacts) {
          print(
            '⏭️ Skipping contacts check - will be requested in permission flow',
          );
          continue;
        }

        final status = await permission.status;
        if (!status.isGranted) {
          return false;
        }
      }

      return true;
    } catch (e) {
      print('Error checking permissions: $e');
      return false;
    }
  }

  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (e) {
      print('Error getting Android SDK version: $e');
      return 33; // Fallback to a recent version
    }
  }

  // Enhanced permission request with dialog for declined permissions
  static Future<bool> requestAllMandatoryPermissions(
    BuildContext context, {
    bool forceRequest = false,
  }) async {
    // Prevent multiple simultaneous permission requests
    if (_isRequestingPermissions && !forceRequest) {
      print('Permission request already in progress, skipping...');
      return false;
    }

    _isRequestingPermissions = true;

    try {
      final int sdkVersion = await getAndroidSdkVersion();

      // Define all permissions your app requires
      final List<Permission> permissionsToRequest = [
        // Permission.camera,
        // Permission.microphone,
        // Permission.notification,
        Permission.location, // For current location
        // Permission.locationWhenInUse, // For foreground location tracking
        // Permission.locationAlways, // For background location tracking
        // Platform-specific storage/media permissions
        ...(Platform.isAndroid
            ? (sdkVersion >= 33
                  // For Android 13+
                  ? [Permission.photos, Permission.videos, Permission.audio]
                  // For older Android
                  : [Permission.storage])
            : [Permission.photos]), // For iOS
        // Only request manageExternalStorage on relevant Android versions
        ...(Platform.isAndroid && sdkVersion >= 30
            ? [Permission.manageExternalStorage]
            : []),
        ...(Platform.isAndroid ? [Permission.accessMediaLocation] : []),
        // Contacts permission - needed for background contact sync
        Permission.contacts,
      ];

      print('📱 Platform: ${Platform.isIOS ? "iOS" : "Android"}');
      print('📋 Total permissions to request: ${permissionsToRequest.length}');
      print('📋 Permissions list: $permissionsToRequest');

      // Request permissions sequentially to avoid conflicts
      await _requestPermissionsSequentially(permissionsToRequest);

      // Check for denied permissions
      List<Permission> deniedPermissions = [];
      List<Permission> permanentlyDeniedPermissions = [];

      print('🔍 Checking final permission statuses...');
      for (var permission in permissionsToRequest) {
        // Special handling for contacts using flutter_contacts
        if (permission == Permission.contacts) {
          final hasContactsPermission = await FlutterContacts.requestPermission(
            readonly: true,
          );
          print(
            '   $permission (flutter_contacts): ${hasContactsPermission ? "granted" : "denied"}',
          );
          if (!hasContactsPermission) {
            deniedPermissions.add(permission);
            print('   ⚠️ $permission is denied');
          } else {
            print('   ✅ $permission is granted');
          }
          continue;
        }

        final status = await permission.status;
        print('   $permission: $status');
        if (!status.isGranted) {
          if (status.isPermanentlyDenied) {
            permanentlyDeniedPermissions.add(permission);
            print('   ⛔ $permission is permanently denied');
          } else {
            deniedPermissions.add(permission);
            print('   ⚠️ $permission is denied');
          }
        } else {
          print('   ✅ $permission is granted');
        }
      }

      // If any permissions were denied, show dialog and re-ask
      if (deniedPermissions.isNotEmpty ||
          permanentlyDeniedPermissions.isNotEmpty) {
        print('❌ Some permissions were denied. Showing dialog...');
        print('   Denied: $deniedPermissions');
        print('   Permanently Denied: $permanentlyDeniedPermissions');
        return await _showPermissionDialog(
          context,
          deniedPermissions,
          permanentlyDeniedPermissions,
        );
      }

      print('✅ All permissions granted!');
      return true; // All permissions granted
    } finally {
      _isRequestingPermissions = false;
    }
  }

  // Request permissions sequentially to avoid conflicts
  static Future<void> _requestPermissionsSequentially(
    List<Permission> permissions, {
    bool forceRequest = false,
  }) async {
    for (var permission in permissions) {
      try {
        // Special handling for contacts using flutter_contacts
        if (permission == Permission.contacts) {
          print(
            '�🔔🔔 REQUESTING CONTACTS PERMISSION USING FLUTTER_CONTACTS 🔔🔔🔔',
          );
          print('Platform: ${Platform.isIOS ? "iOS" : "Android"}');

          final hasPermission = await FlutterContacts.requestPermission();

          print('✅✅✅ CONTACTS PERMISSION RESULT: $hasPermission ✅✅✅');
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }

        final status = await permission.status;
        print('📋 Checking permission: $permission - Status: $status');

        // On iOS, some permissions might show as "denied" before first request
        // We should still try to request them
        if (!status.isGranted) {
          if (status.isPermanentlyDenied && !forceRequest) {
            print(
              '⚠️ Permission $permission is permanently denied, needs Settings',
            );
          } else {
            print(
              '🔔 Requesting permission: $permission (forceRequest: $forceRequest)',
            );
            final result = await permission.request();
            print('✅ Permission $permission result: $result');

            // Longer delay for photos on iOS
            if (Platform.isIOS && permission == Permission.photos) {
              await Future.delayed(const Duration(milliseconds: 500));
            } else {
              await Future.delayed(const Duration(milliseconds: 300));
            }
          }
        } else {
          print('✓ Permission $permission already granted');
        }
      } catch (e) {
        print('❌ Error requesting permission $permission: $e');
        // Continue with next permission if one fails
      }
    }
  }

  // Show dialog for declined permissions with accept/decline options
  static Future<bool> _showPermissionDialog(
    BuildContext context,
    List<Permission> deniedPermissions,
    List<Permission> permanentlyDeniedPermissions,
  ) async {
    if (!context.mounted) return false;

    String permissionMessage = _getPermissionMessage(
      deniedPermissions + permanentlyDeniedPermissions,
    );

    // Updated message to emphasize requirement
    String fullMessage =
        'All permissions are required to use this app.\n\n$permissionMessage\n\n${permanentlyDeniedPermissions.isNotEmpty ? "Some permissions need to be enabled in Settings.\n\n" : ""}You cannot proceed without granting all permissions.';

    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Permissions Required'),
        content: SingleChildScrollView(child: Text(fullMessage)),
        actions: <Widget>[
          TextButton(
            child: const Text('Exit App'),
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
          ),
          TextButton(
            child: Text(
              permanentlyDeniedPermissions.isNotEmpty
                  ? 'Open Settings'
                  : 'Grant Permissions',
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
          ),
        ],
      ),
    );

    if (result == true) {
      // User accepted, try to request permissions again
      if (permanentlyDeniedPermissions.isNotEmpty) {
        // If permanently denied, open settings
        print('📱 Opening app settings for permanently denied permissions...');
        await openAppSettings();
        // Wait for user to return from settings
        await Future.delayed(const Duration(seconds: 2));
        // Re-check permissions after returning from settings
        return await _recheckPermissions(
          context,
          deniedPermissions + permanentlyDeniedPermissions,
        );
      } else {
        // On iOS, if a permission was denied, we often need to go to Settings
        // because iOS doesn't allow re-requesting after initial denial
        print('🔄 Re-checking permission statuses before requesting...');
        List<Permission> nowPermanentlyDenied = [];
        List<Permission> stillCanRequest = [];

        for (var permission in deniedPermissions) {
          final status = await permission.status;
          print('   $permission current status: $status');

          // On iOS, denied is effectively permanently denied after first ask
          if (Platform.isIOS &&
              (status.isDenied || status.isPermanentlyDenied)) {
            print('   📱 iOS detected: $permission needs Settings');
            nowPermanentlyDenied.add(permission);
          } else if (status.isPermanentlyDenied) {
            nowPermanentlyDenied.add(permission);
          } else if (!status.isGranted) {
            stillCanRequest.add(permission);
          }
        }

        if (nowPermanentlyDenied.isNotEmpty) {
          // Need to open settings
          print(
            '⚠️ ${nowPermanentlyDenied.length} permissions need Settings, opening...',
          );
          await openAppSettings();
          await Future.delayed(const Duration(seconds: 2));
          return await _recheckPermissions(context, deniedPermissions);
        } else if (stillCanRequest.isNotEmpty) {
          // Request denied permissions again sequentially with force
          print(
            '🔔 Requesting ${stillCanRequest.length} permissions again with force...',
          );
          await Future.delayed(const Duration(milliseconds: 500));
          await _requestPermissionsSequentially(
            stillCanRequest,
            forceRequest: true,
          );

          // Check if there are still denied permissions
          List<Permission> stillDenied = [];
          List<Permission> nowPermanentlyDenied = [];

          for (var permission in stillCanRequest) {
            final status = await permission.status;
            if (!status.isGranted) {
              if (status.isPermanentlyDenied) {
                nowPermanentlyDenied.add(permission);
              } else {
                stillDenied.add(permission);
              }
            }
          }

          // If some became permanently denied, need Settings
          if (nowPermanentlyDenied.isNotEmpty) {
            print(
              '⚠️ ${nowPermanentlyDenied.length} permissions now permanently denied',
            );
            return await _showPermissionDialog(
              context,
              stillDenied,
              nowPermanentlyDenied,
            );
          }

          // If still some permissions are denied, show dialog again
          if (stillDenied.isNotEmpty) {
            return await _showPermissionDialog(context, stillDenied, []);
          }

          return true; // All permissions granted
        } else {
          // All permissions are now granted
          return true;
        }
      }
    } else {
      // User declined, show exit confirmation dialog
      bool? shouldExit = await _showExitConfirmationDialog(context);
      if (shouldExit == true) {
        // Exit the app
        exit(0);
      } else {
        // Try again
        await Future.delayed(const Duration(seconds: 1));
        return await _showPermissionDialog(
          context,
          deniedPermissions,
          permanentlyDeniedPermissions,
        );
      }
    }
  }

  // Show exit confirmation dialog
  static Future<bool?> _showExitConfirmationDialog(BuildContext context) async {
    if (!context.mounted) return false;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Exit App?'),
        content: const Text(
          'This app cannot function without the required permissions. '
          'Do you want to exit the app or try again?',
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Try Again'),
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
          ),
          TextButton(
            child: const Text('Exit App'),
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
          ),
        ],
      ),
    );
  }

  // Re-check permissions after returning from settings
  static Future<bool> _recheckPermissions(
    BuildContext context,
    List<Permission> permissionsToCheck,
  ) async {
    List<Permission> stillDenied = [];
    List<Permission> stillPermanentlyDenied = [];

    for (var permission in permissionsToCheck) {
      final status = await permission.status;
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          stillPermanentlyDenied.add(permission);
        } else {
          stillDenied.add(permission);
        }
      }
    }

    if (stillDenied.isNotEmpty || stillPermanentlyDenied.isNotEmpty) {
      return await _showPermissionDialog(
        context,
        stillDenied,
        stillPermanentlyDenied,
      );
    }

    return true; // All permissions granted
  }

  // Get user-friendly permission message
  static String _getPermissionMessage(List<Permission> permissions) {
    if (permissions.isEmpty) return '';

    List<String> permissionNames = permissions.map((permission) {
      switch (permission) {
        // case Permission.camera:
        // return 'Camera';
        // case Permission.microphone:
        // return 'Microphone';
        // case Permission.notification:
        //   return 'Notifications';
        case Permission.location:
          return 'Location';
        case Permission.contacts:
          return 'Contacts';
        // case Permission.locationWhenInUse:
        // return 'Location (When in Use)';
        // case Permission.locationAlways:
        // return 'Location (Always)';
        case Permission.photos:
          return 'Photos';
        case Permission.videos:
          return 'Videos';
        case Permission.audio:
          return 'Audio';
        case Permission.storage:
          return 'Storage';
        case Permission.manageExternalStorage:
          return 'File Management';
        case Permission.accessMediaLocation:
          return 'Media Location';
        default:
          return permission.toString().split('.').last;
      }
    }).toList();

    String permissionList = permissionNames.join(', ');

    return 'This app needs the following permissions to work properly:\n\n'
        '$permissionList\n\n'
        'Please grant these permissions to continue using the app.';
  }

  // --- Other existing methods for specific one-off checks ---
  static Future<bool> isPermissionGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  static Future<bool> requestPermission(Permission permission) async {
    final result = await permission.request();
    return result.isGranted;
  }

  static Future<bool> checkStoragePermission() async {
    final int sdkVersion = await getAndroidSdkVersion();

    if (Platform.isAndroid) {
      if (sdkVersion >= 33) {
        // For Android 13+, check granular media permissions
        final photosStatus = await Permission.photos.status;
        final videosStatus = await Permission.videos.status;
        final audioStatus = await Permission.audio.status;
        return photosStatus.isGranted &&
            videosStatus.isGranted &&
            audioStatus.isGranted;
      } else {
        // For older Android versions
        final storageStatus = await Permission.storage.status;
        return storageStatus.isGranted;
      }
    } else {
      // For iOS
      final photosStatus = await Permission.photos.status;
      return photosStatus.isGranted;
    }
  }

  // static Future<bool> checkContactsPermission() async {
  //   final status = await Permission.contacts.status;
  //   return status.isGranted;
  // }

  static Future<bool> areBackupPermissionsGranted() async {
    // final contactsGranted = await checkContactsPermission();
    final storageGranted = await checkStoragePermission();

    if (Platform.isAndroid) {
      final int sdkVersion = await getAndroidSdkVersion();
      if (sdkVersion >= 30) {
        final manageStorageStatus =
            await Permission.manageExternalStorage.status;
        return storageGranted && manageStorageStatus.isGranted;
      }
    }

    return storageGranted;
  }

  // Check if contacts permission is granted
  static Future<bool> checkContactsPermission() async {
    try {
      return await FlutterContacts.requestPermission(readonly: true);
    } catch (e) {
      print('Error checking contacts permission: $e');
      return false;
    }
  }

  // Request contacts permission specifically
  static Future<bool> requestContactsPermission() async {
    try {
      print('🔔 Requesting contacts permission...');
      final hasPermission = await FlutterContacts.requestPermission(
        readonly: false,
      );
      print('✅ Contacts permission result: $hasPermission');
      return hasPermission;
    } catch (e) {
      print('❌ Error requesting contacts permission: $e');
      return false;
    }
  }
}
