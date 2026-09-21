import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Method channel exposing low-level Bluetooth state from the Android side.
const MethodChannel _bluetoothChannel = MethodChannel('billflow/bluetooth');

/// Outcome of a runtime-permission request for Bluetooth printing.
class PrinterPermissionResult {
  /// True when every permission applicable to this device is granted.
  final bool granted;

  /// True when at least one applicable permission was permanently denied,
  /// which only the OS Settings app can undo.
  final bool openSettings;

  /// True when the (location) permission is the one that is still missing. Lets
  /// the UI explain that some devices need location for Bluetooth discovery.
  final bool locationMissing;

  const PrinterPermissionResult({
    required this.granted,
    required this.openSettings,
    this.locationMissing = false,
  });
}

/// Requests the runtime permissions required to talk to a Bluetooth thermal
/// printer and returns whether scanning/connecting can proceed.
///
/// Flow (per applicable permission):
///   1. read [Permission.status] — if already OK, move on;
///   2. otherwise call [Permission.request] to show the OS prompt;
///   3. re-read [Permission.status].
///
/// If the plugin still reports "not granted" but the OS itself has granted the
/// permission (checked directly via `PackageManager` on the native side), the
/// OS is treated as authoritative — this fixes Android 12+ devices where the
/// plugin keeps reporting a denied state for bluetoothScan/bluetoothConnect
/// even though "Izin perangkat sekitar" was already allowed.
///
/// On every Android version the app asks for BLUETOOTH_CONNECT + BLUETOOTH_SCAN
/// (Android 12+) and for location — several devices and printer plugins block
/// classic-bluetooth discovery when location is not granted.
Future<PrinterPermissionResult> requestBluetoothPermissions() async {
  if (!Platform.isAndroid) {
    return const PrinterPermissionResult(granted: true, openSettings: false);
  }

  const permissions = <Permission>[
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.locationWhenInUse,
  ];

  var openSettings = false;
  var locationMissing = false;

  for (final permission in permissions) {
    // 1) Read status first — request only what is not granted yet.
    var status = await permission.status;
    if (!_isOk(status)) {
      status = await permission.request();
    }
    if (status.isPermanentlyDenied) openSettings = true;

    // 2) Authoritative check: the plugin can misreport the state even though
    //    Android already granted the permission — trust the OS in that case.
    final osGranted = await _osSaysGranted(permission);
    if (!_isOk(status) && !osGranted) {
      if (_isLocation(permission)) locationMissing = true;
      if (!_isLocation(permission)) openSettings = openSettings || status.isPermanentlyDenied;
    }
  }

  final granted = !locationMissing && !(await _anyBluetoothMissing());
  return PrinterPermissionResult(
    granted: granted,
    openSettings: openSettings,
    locationMissing: locationMissing,
  );
}

/// Final re-read of the two Bluetooth runtime permissions. Returns true when
/// every one of them is granted (either per the plugin or per the OS).
Future<bool> _anyBluetoothMissing() async {
  for (final permission in const <Permission>[
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ]) {
    final status = await permission.status;
    if (!_isOk(status) && !await _osSaysGranted(permission)) {
      return true;
    }
  }
  return false;
}

/// True when [status] allows scanning/connecting to proceed.
bool _isOk(PermissionStatus status) =>
    status.isGranted || status.isLimited || status.isRestricted;

bool _isLocation(Permission permission) =>
    permission == Permission.location ||
    permission == Permission.locationWhenInUse;

/// Queries the OS (PackageManager) directly for the real permission state.
/// Non-Android / channel failures fall back to false (let the plugin decide).
Future<bool> _osSaysGranted(Permission permission) async {
  try {
    final map = await _bluetoothChannel.invokeMapMethod<String, bool>(
        'bluetoothPermissionStates');
    if (map == null) return false;
    if (identical(permission, Permission.bluetoothScan)) {
      return map['bluetooth_scan'] == true;
    }
    if (identical(permission, Permission.bluetoothConnect)) {
      return map['bluetooth_connect'] == true;
    }
    if (_isLocation(permission)) {
      return map['location'] == true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// True when the Android Bluetooth adapter is powered on.
///
/// Returns true when the state cannot be determined so a missing permission
/// never silently blocks scanning; the picker itself stays authoritative.
Future<bool> isBluetoothEnabled() async {
  if (!Platform.isAndroid) return true;
  try {
    final enabled =
        await _bluetoothChannel.invokeMethod<bool>('bluetoothEnabled');
    return enabled ?? true;
  } catch (_) {
    return true;
  }
}

/// Opens the system Bluetooth settings so the user can turn the adapter on.
Future<void> openBluetoothSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await _bluetoothChannel.invokeMethod('bluetoothSettings');
  } catch (_) {
    // Best-effort; opening the OS settings page is not critical.
  }
}

/// Best-effort request at app startup so a future printer connection is not
/// blocked. Never throws; fails silently if the OS dialog cannot be shown.
Future<void> requestBluetoothPermissionsSilently() async {
  try {
    await requestBluetoothPermissions();
  } catch (_) {
    // Ignore — the connection-time request is the authoritative one.
  }
}