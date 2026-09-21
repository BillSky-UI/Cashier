package com.cashier.cashier_app

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Exposes the real Bluetooth adapter state and the OS-authoritative
        // permission state to Dart. The Bluetooth plugins/receivers can report
        // a permission as "denied" even when Android already granted it (e.g.
        // the "Nearby devices" toggle), so Dart trusts this direct OS query.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "billflow/bluetooth",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "bluetoothEnabled" -> {
                    result.success(
                        try {
                            val manager =
                                getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                            manager?.adapter?.isEnabled == true
                        } catch (_: SecurityException) {
                            // Permission not (yet) granted: report unknown so
                            // the scanner decides instead of throwing.
                            null
                        }
                    )
                }
                "bluetoothPermissionStates" -> {
                    result.success(
                        mapOf(
                            "bluetooth_scan" to granted(Manifest.permission.BLUETOOTH_SCAN),
                            "bluetooth_connect" to
                                granted(Manifest.permission.BLUETOOTH_CONNECT),
                            "location" to
                                (granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
                                    granted(Manifest.permission.ACCESS_COARSE_LOCATION)),
                        ),
                    )
                }
                "bluetoothSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("bluetooth_settings", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun granted(permission: String): Boolean {
        return try {
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }
}