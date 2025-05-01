import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<PermissionStatus> requestStoragePermission() async {
    PermissionStatus status;

    if (Platform.isAndroid) {
      // For Android 10+ (API 29+), we need to request MANAGE_EXTERNAL_STORAGE
      if (await DeviceInfoPlugin()
          .androidInfo
          .then((info) => info.version.sdkInt >= 29)) {
        if (await Permission.manageExternalStorage.isGranted) {
          return PermissionStatus.granted;
        }

        // First check if we can request the permission
        if (await Permission.manageExternalStorage.isPermanentlyDenied) {
          // If permanently denied, we need to open app settings
          return PermissionStatus.permanentlyDenied;
        }

        // Request the permission
        status = await Permission.manageExternalStorage.request();
      } else {
        // For Android < 10, just request storage permission
        if (await Permission.storage.isGranted) {
          return PermissionStatus.granted;
        }

        // Check if permanently denied
        if (await Permission.storage.isPermanentlyDenied) {
          return PermissionStatus.permanentlyDenied;
        }

        // Request the permission
        status = await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      // On iOS, we don't need explicit storage permission for app documents directory
      status = PermissionStatus.granted;
    } else {
      // For other platforms, assume granted
      status = PermissionStatus.granted;
    }

    return status;
  }

  // Open settings if permission is permanently denied
  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
