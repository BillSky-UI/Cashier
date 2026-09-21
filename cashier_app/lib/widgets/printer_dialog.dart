import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart'
    as fb;
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:usb_serial/usb_serial.dart';

import '../services/app_settings.dart';
import '../services/printer_permissions.dart';
import '../services/thermal_printer.dart';

/// Shows a dialog that lets the user pick which thermal printer to use, then
/// returns the chosen [PrinterTarget] (or null if cancelled).
///
/// Three transports are offered:
///  - Bluetooth: scans & lets the user pick a paired printer.
///  - USB / Kabel: lists attached USB-serial devices.
///  - Network: the previously configured LAN host/port.
Future<PrinterTarget?> showPrinterPicker(BuildContext context) {
  return showDialog<PrinterTarget>(
    context: context,
    builder: (_) => const _PrinterPickerDialog(),
  );
}

class _PrinterPickerDialog extends StatefulWidget {
  const _PrinterPickerDialog();

  @override
  State<_PrinterPickerDialog> createState() => _PrinterPickerDialogState();
}

class _PrinterPickerDialogState extends State<_PrinterPickerDialog> {
  bool _loadingUsb = false;
  String? _btError;
  String? _usbError;
  List<UsbDevice> _usbDevices = [];

  bool _btEnabled = false;
  bool _btStatusChecked = false;

  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hostCtrl.text = AppSettings.instance.printerHost;
    _portCtrl.text = AppSettings.instance.printerPort.toString();
    _scanUsb();
    _refreshBluetoothStatus();
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanUsb() async {
    setState(() {
      _loadingUsb = true;
      _usbError = null;
    });
    try {
      final devices = await UsbSerial.listDevices();
      if (!mounted) return;
      setState(() {
        _usbDevices = devices;
        _loadingUsb = false;
        if (devices.isEmpty) {
          _usbError = 'Tidak ada printer USB terhubung.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingUsb = false;
        _usbError = 'Gagal memindai USB: $e';
      });
    }
  }

  void _select(PrinterTarget target) => Navigator.of(context).pop(target);

  /// Re-checks whether the Android Bluetooth adapter is powered on.
  Future<void> _refreshBluetoothStatus() async {
    final enabled = await isBluetoothEnabled();
    if (!mounted) return;
    setState(() {
      _btEnabled = enabled;
      _btStatusChecked = true;
      _btError = null;
    });
  }

  /// Opens the built-in Bluetooth device picker (scans while open) and, if a
  /// printer is chosen, selects it for printing.
  ///
  /// Before scanning it ensures the runtime permissions are granted and that
  /// the Bluetooth adapter is actually switched on, otherwise the thermal
  /// printer would never appear in the results.
  Future<void> _pickBluetooth() async {
    final result = await requestBluetoothPermissions();
    if (!mounted) return;
    if (!result.granted) {
      setState(() {
        _btError = result.locationMissing
            ? 'Izin lokasi belum diberikan. Sebagian perangkat membutuhkan '
                'izin lokasi agar printer Bluetooth ditemukan.'
            : result.openSettings
                ? 'Izin Bluetooth diblokir. Buka Pengaturan untuk mengizinkan.'
                : 'Izin Bluetooth belum diberikan.';
      });
      if (result.openSettings) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Izin Bluetooth diblokir permanen.'),
              action: SnackBarAction(
                label: 'Buka Pengaturan',
                onPressed: () => openAppSettings(),
              ),
            ),
          );
      }
      return;
    }

    // The permissions are granted — now make sure Bluetooth itself is on.
    final enabled = await isBluetoothEnabled();
    if (!mounted) return;
    setState(() {
      _btEnabled = enabled;
      _btStatusChecked = true;
      _btError = null;
    });
    if (!enabled) {
      setState(() => _btError =
          'Bluetooth dalam keadaan mati. Nyalakan dulu, lalu pindai ulang.');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content:
              const Text('Bluetooth mati. Nyalakan Bluetooth untuk mencari printer.'),
          action: SnackBarAction(
            label: 'Nyalakan',
            onPressed: () => openBluetoothSettings(),
          ),
        ));
      return;
    }

    // Plugin-level pre-flight: flutter_bluetooth_printer runs its own native
    // permission check before scanning. If it still reports "not permitted"
    // (e.g. the OS granted permissions only after the app started, or an older
    // APK without the fixed manifest is installed), resync once before opening
    // the picker so the user never sees a dead "Bluetooth is not permitted"
    // screen.
    if (await fb.FlutterBluetoothPrinter.getState() ==
        fb.BluetoothState.notPermitted) {
      final resync = await requestBluetoothPermissions();
      if (!resync.granted ||
          await fb.FlutterBluetoothPrinter.getState() ==
              fb.BluetoothState.notPermitted) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        setState(() {
          _btError =
              'Izin Bluetooth belum tersinkron ke aplikasi. Perbarui aplikasi '
              'dan izinkan izin perangkat sekitar, lalu pindai ulang.';
        });
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const Text('Izin Bluetooth belum tersinkron.'),
            action: SnackBarAction(
              label: 'Buka Pengaturan',
              onPressed: () => openAppSettings(),
            ),
          ));
        return;
      }
      if (!mounted) return;
    }

    if (!mounted) return;
    final device = await fb.FlutterBluetoothPrinter.selectDevice(context);
    if (!mounted || device == null) return;

    _select(PrinterTarget(
      type: PrinterType.bluetooth,
      label: device.name ?? 'Bluetooth Printer',
      detail: device.address,
      handle: device.address,
    ));
  }

  Future<void> _printNetwork() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alamat IP printer tidak boleh kosong.')),
      );
      return;
    }
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9100;
    await AppSettings.instance.setPrinterConfig(host: host, port: port);
    _select(const PrinterTarget(
        type: PrinterType.network, label: 'Jaringan', detail: ''));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Printer Thermal'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader('Bluetooth', Icons.bluetooth,
                  onScan: _refreshBluetoothStatus),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search),
                title: const Text('Pindai & pilih printer Bluetooth'),
                subtitle: Text(
                  _btError ??
                      (_btStatusChecked
                          ? (_btEnabled
                              ? 'Status: Aktif — pilih perangkat yang sudah dipasangkan'
                              : 'Status: Mati — ketuk untuk cek ulang')
                          : 'Memeriksa status Bluetooth...'),
                ),
                dense: true,
                onTap: _pickBluetooth,
              ),
              const Divider(height: 24),
              _sectionHeader('USB / Kabel', Icons.usb,
                  onScan: _loadingUsb ? null : _scanUsb),
              _buildUsb(),
              const Divider(height: 24),
              _sectionHeader('Jaringan (LAN)', Icons.wifi),
              _buildNetwork(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon,
      {VoidCallback? onScan}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (onScan != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'Pindai ulang',
              onPressed: onScan,
            ),
        ],
      ),
    );
  }

  Widget _buildUsb() {
    if (_loadingUsb) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Row(
          children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Memindai perangkat USB...'),
          ],
        ),
      );
    }
    if (_usbError != null && _usbDevices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(_usbError!, style: const TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: [
        for (final d in _usbDevices)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.usb),
            title: Text(d.productName ?? d.deviceName),
            subtitle: Text(d.manufacturerName ?? 'USB Serial'),
            onTap: () => _select(PrinterTarget(
              type: PrinterType.usb,
              label: d.productName ?? d.deviceName,
              detail: d.manufacturerName ?? 'USB',
              handle: d,
            )),
          ),
      ],
    );
  }

  Widget _buildNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hostCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Alamat IP / Host',
                  hintText: 'contoh: 192.168.1.50',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _portCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _printNetwork,
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('Cetak via Jaringan'),
        ),
      ],
    );
  }
}
