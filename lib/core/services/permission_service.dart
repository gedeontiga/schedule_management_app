import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Request storage permission (not needed for Android 10+ with scoped storage)
  Future<PermissionStatus> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;

      // Android 10+ (API 29+) uses scoped storage - no permission needed
      // when using getExternalStorageDirectory()
      if (androidInfo.version.sdkInt >= 29) {
        // For Android 10+, we don't need storage permission
        // when using app-specific directories
        return PermissionStatus.granted;
      } else {
        // For Android 9 and below, request storage permission
        if (await Permission.storage.isGranted) {
          return PermissionStatus.granted;
        }

        if (await Permission.storage.isPermanentlyDenied) {
          return PermissionStatus.permanentlyDenied;
        }

        return await Permission.storage.request();
      }
    } else if (Platform.isIOS) {
      // iOS doesn't need storage permission for app documents directory
      return PermissionStatus.granted;
    } else {
      return PermissionStatus.granted;
    }
  }

  /// Open app settings
  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
