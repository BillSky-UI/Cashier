import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central preferences store for app-level settings: theme mode and the active
/// cashier name. Persisted via [SharedPreferences] so changes survive restarts.
/// Extends [ChangeNotifier] so the whole app can rebuild when settings change.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _themeKey = 'theme_mode';
  static const _cashierKey = 'cashier_name';
  static const _storeNameKey = 'store_name';
  static const _storeAddressKey = 'store_address';
  static const _storePhoneKey = 'store_phone';
  static const _printerHostKey = 'printer_host';
  static const _printerPortKey = 'printer_port';
  static const _storeFooterKey = 'store_footer';
  static const _storeLogoKey = 'store_logo';
  static const _pinHashKey = 'cashier_pin_hash';
  static const _defaultCashier = 'Kasir';
  static const _defaultStoreName = 'BillFlow';
  static const _defaultStoreAddress =
      'Kp. Karya Bakti No.Rt04/04, RT.03/RW.06, Cilendek Bar., Kec. Bogor Bar., Kota Bogor, Jawa Barat 16112';
  static const _defaultStorePhone = '';
  static const _defaultPrinterHost = '';
  static const _defaultPrinterPort = 9100;

  /// Sentinel value stored in `storeLogoPath` when the packaged logo is used.
  static const builtinLogoMarker = '@builtin';

  // Keep in sync with `version:` in pubspec.yaml.
  static const appVersion = '2.0.0';

  String _cashierName = _defaultCashier;
  String _storeName = _defaultStoreName;
  String _storeAddress = _defaultStoreAddress;
  String _storePhone = _defaultStorePhone;
  String _printerHost = _defaultPrinterHost;
  int _printerPort = _defaultPrinterPort;
  String _storeFooter = '';
  String _storeLogoPath = '';
  String _pinHash = '';
  ThemeMode _themeMode = ThemeMode.system;
  bool _loaded = false;

  /// Loads stored settings once. Call from [main] before [runApp].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cashierName = prefs.getString(_cashierKey) ?? _defaultCashier;
    _storeName = prefs.getString(_storeNameKey) ?? _defaultStoreName;
    _storeAddress = prefs.getString(_storeAddressKey) ?? _defaultStoreAddress;
    _storePhone = prefs.getString(_storePhoneKey) ?? _defaultStorePhone;
    _printerHost = prefs.getString(_printerHostKey) ?? _defaultPrinterHost;
    _printerPort = prefs.getInt(_printerPortKey) ?? _defaultPrinterPort;
    _storeFooter = prefs.getString(_storeFooterKey) ?? '';
    _storeLogoPath = prefs.getString(_storeLogoKey) ?? '';
    _pinHash = prefs.getString(_pinHashKey) ?? '';
    _themeMode = _parseThemeMode(prefs.getString(_themeKey));
    _loaded = true;
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;

  String get cashierName => _cashierName;

  String get storeName => _storeName;

  String get storeAddress => _storeAddress;

  String get storePhone => _storePhone;

  String get printerHost => _printerHost;

  int get printerPort => _printerPort;

  String get storeFooter => _storeFooter;

  String get storeLogoPath => _storeLogoPath;

  bool get isLoaded => _loaded;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> setCashierName(String name) async {
    final clean = name.trim().isEmpty ? _defaultCashier : name.trim();
    if (clean == _cashierName) return;
    _cashierName = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cashierKey, _cashierName);
  }

  Future<void> setStoreProfile({
    required String name,
    String address = '',
    String phone = '',
  }) async {
    final cleanName = name.trim().isEmpty ? _defaultStoreName : name.trim();
    final cleanAddress = address.trim();
    final cleanPhone = phone.trim();
    if (cleanName == _storeName &&
        cleanAddress == _storeAddress &&
        cleanPhone == _storePhone) {
      return;
    }
    _storeName = cleanName;
    _storeAddress = cleanAddress;
    _storePhone = cleanPhone;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeNameKey, _storeName);
    await prefs.setString(_storeAddressKey, _storeAddress);
    await prefs.setString(_storePhoneKey, _storePhone);
  }

  Future<void> setPrinterConfig({required String host, required int port}) async {
    final cleanHost = host.trim();
    if (cleanHost == _printerHost && port == _printerPort) return;
    _printerHost = cleanHost;
    _printerPort = port;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_printerHostKey, _printerHost);
    await prefs.setInt(_printerPortKey, _printerPort);
  }

  /// Saves the free-text footer that appears at the bottom of every receipt.
  Future<void> setStoreFooter(String footer) async {
    final clean = footer.trim();
    if (clean == _storeFooter) return;
    _storeFooter = clean;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeFooterKey, _storeFooter);
  }

  /// Sets the logo used on receipts. [path] may be:
  ///  - [builtinLogoMarker] to use the packaged `assets/logo` image.
  ///  - an absolute file path to a user-picked image.
  ///  - empty string to disable the logo.
  Future<void> setStoreLogo(String path) async {
    if (path == _storeLogoPath) return;
    _storeLogoPath = path;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeLogoKey, _storeLogoPath);
  }

  // ---------------- Kasir PIN ----------------

  /// True when a 4-digit security PIN has been configured.
  bool get hasPin => _pinHash.isNotEmpty;

  /// Compares [pin] against the stored SHA-256 hash. Always false when no PIN
  /// is configured yet.
  bool verifyPin(String pin) {
    if (!hasPin) return false;
    return _hashPin(pin) == _pinHash;
  }

  /// Stores a new 4-digit PIN. Pass an empty/whitespace string to disable.
  Future<void> setPin(String pin) async {
    final clean = pin.trim();
    _pinHash = clean.isEmpty ? '' : _hashPin(clean);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_pinHash.isEmpty) {
      await prefs.remove(_pinHashKey);
    } else {
      await prefs.setString(_pinHashKey, _pinHash);
    }
  }

  /// Removes the PIN entirely (disables the security feature).
  Future<void> clearPin() => setPin('');

  /// SHA-256 of [value]; PINs are never persisted in plain text.
  static String _hashPin(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  ThemeMode _parseThemeMode(String? raw) {
    if (raw == null) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }
}