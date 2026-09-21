import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/app_settings.dart';
import '../services/app_bus.dart';
import '../services/backup_service.dart';
import 'admin_fee_screen.dart';
import 'category_screen.dart';
import 'expense_screen.dart';
import 'recap_archive_screen.dart';
import 'report_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _openCategories() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoryScreen()),
    );
  }

  void _openAdminFee() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminFeeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            children: [
              const SectionHeader('Tema Aplikasi'),
              RadioGroup<ThemeMode>(
                groupValue: settings.themeMode,
                onChanged: (m) {
                  if (m != null) settings.setThemeMode(m);
                },
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('Mode Otomatis'),
                      subtitle: Text('Ikuti pengaturan perangkat'),
                      secondary: Icon(Icons.brightness_auto),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Mode Terang'),
                      subtitle: Text('Light mode'),
                      secondary: Icon(Icons.light_mode),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Mode Gelap'),
                      subtitle: Text('Dark mode'),
                      secondary: Icon(Icons.dark_mode),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const Divider(),
              const SectionHeader('Identitas Kasir'),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Nama Kasir'),
                subtitle: Text(settings.cashierName),
                trailing: const Icon(Icons.edit),
                onTap: () => _editCashierName(context, settings),
              ),
              const Divider(),
              const SectionHeader('Identitas Toko'),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Profil Toko'),
                subtitle: Text(
                  settings.storeAddress.isEmpty && settings.storePhone.isEmpty
                      ? settings.storeName
                      : '${settings.storeName} · ${settings.storeAddress}'
                          .trim()
                          .replaceAll(RegExp(r'\s+'), ' '),
                ),
                trailing: const Icon(Icons.edit),
                onTap: () => _editStoreProfile(context, settings),
              ),
              const Divider(),
              const SectionHeader('Tampilan Struk'),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Logo Toko'),
                subtitle: Text(_logoSubtitle(settings)),
                trailing: const Icon(Icons.edit),
                onTap: () => _editLogo(context, settings),
              ),
              ListTile(
                leading: const Icon(Icons.notes_rounded),
                title: const Text('Footer Struk'),
                subtitle: Text(
                  settings.storeFooter.isEmpty
                      ? 'Pesan penutup di bagian bawah struk'
                      : settings.storeFooter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.edit),
                onTap: () => _editFooter(context, settings),
              ),
              const Divider(),
              const SectionHeader('Master Data'),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Kategori Produk'),
                subtitle: const Text('Kelola kategori untuk mengelompokkan produk'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCategories,
              ),
              ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: const Text('Biaya Admin'),
                subtitle: const Text('Atur nominal biaya admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openAdminFee,
              ),
              const Divider(),
              const SectionHeader('Laporan & Kasir'),
              ListTile(
                leading: const Icon(Icons.insert_chart_outlined),
                title: const Text('Laporan & Tutup Kasir'),
                subtitle: const Text('Rekap penjualan harian dan bulanan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Pengeluaran Toko'),
                subtitle: const Text('Catat biaya operasional di luar penjualan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExpenseScreen()),
                ),
              ),
              const Divider(),
              const SectionHeader('Keamanan'),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('PIN Keamanan Kasir'),
                subtitle: Text(
                  settings.hasPin
                      ? 'PIN 4 angka aktif — ketuk untuk mengubah'
                      : 'Belum diatur — ketuk untuk membuat PIN',
                ),
                trailing: settings.hasPin
                    ? Icon(Icons.check_circle_outline,
                        color: Colors.green.shade600)
                    : const Icon(Icons.edit),
                onTap: () => _editPin(context, settings),
              ),
              const Divider(),
              const SectionHeader('Data & Cadangan'),
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Backup Data'),
                subtitle: const Text('Simpan salinan database ke perangkat'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _backup(context),
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Pulihkan Data'),
                subtitle: const Text('Muat kembali dari file backup'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _restore(context),
              ),
              const Divider(),
              const SectionHeader('Tentang'),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Versi Aplikasi'),
                subtitle: Text('BillFlow v${AppSettings.appVersion}'),
              ),
              const ListTile(
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('Tampil di struk'),
                subtitle: Text('Nama kasir akan dicetak pada struk transaksi'),
                enabled: false,
              ),
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('Arsip Rekap Bulanan'),
                subtitle: const Text('Lihat rekap PDF bulan-bulan sebelumnya'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RecapArchiveScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

    Future<void> _backup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Menyiapkan backup...'),
      duration: Duration(seconds: 1),
    ));
    final error = await BackupService.backup();
    if (error != null && error.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Memilih file backup...'),
      duration: Duration(seconds: 1),
    ));
    final msg = await BackupService.restore();
    if (msg != null && msg.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
      ));
    }
    // Let every screen reload against the restored database.
    AppBus.instance.notifyChanged();
  }

  Future<void> _editPin(BuildContext context, AppSettings settings) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PinSetupDialog(settings: settings),
    );
  }

  String _logoSubtitle(AppSettings settings) {
    if (settings.storeLogoPath.isEmpty) return 'Struk tanpa logo';
    if (settings.storeLogoPath == AppSettings.builtinLogoMarker) {
      return 'Logo bawaan BillFlow';
    }
    return 'Logo dari galeri';
  }

  Future<void> _editLogo(
      BuildContext context, AppSettings settings) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Logo Toko',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Gunakan logo bawaan'),
              subtitle: const Text('Logo BillFlow bawaan aplikasi'),
              trailing: settings.storeLogoPath == AppSettings.builtinLogoMarker
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await settings.setStoreLogo(AppSettings.builtinLogoMarker);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Logo bawaan dipilih.')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari galeri'),
              subtitle: const Text('Ambil gambar logo dari perangkat'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final path = await _pickLogo();
                if (path != null) {
                  await settings.setStoreLogo(path);
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Logo diperbarui.')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Nonaktifkan logo'),
              subtitle: const Text('Struk tampil tanpa logo'),
              trailing: settings.storeLogoPath.isEmpty
                  ? const Icon(Icons.check)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                await settings.setStoreLogo('');
                messenger.showSnackBar(
                    const SnackBar(content: Text('Logo dinonaktifkan.')));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickLogo() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return null;
      final source = result.single.path;
      if (source == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${dir.path}${Platform.pathSeparator}logo');
      if (!await destDir.exists()) await destDir.create(recursive: true);
      final ext = source.split('.').last.toLowerCase();
      final dest = '${destDir.path}${Platform.pathSeparator}logo.$ext';
      await File(source).copy(dest);
      return dest;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memilih logo: $e')));
      }
      return null;
    }
  }

  Future<void> _editFooter(
      BuildContext context, AppSettings settings) async {
    final controller = TextEditingController(text: settings.storeFooter);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Footer Struk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Teks penutup yang tampil di bagian paling bawah struk '
              '(mis. jam operasional, kontak, atau ucapan terima kasih).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 120,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Contoh: Buka setiap hari 07.00 - 22.00\nTerima kasih',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final value = controller.text;
              await settings.setStoreFooter(value);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              messenger.showSnackBar(
                  const SnackBar(content: Text('Footer diperbarui.')));
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCashierName(
      BuildContext context, AppSettings settings) async {    final controller = TextEditingController(text: settings.cashierName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubah Nama Kasir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama Kasir',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (result != null) {
      await settings.setCashierName(result);
    }
  }

  Future<void> _editStoreProfile(
      BuildContext context, AppSettings settings) async {
    final nameController = TextEditingController(text: settings.storeName);
    final addressController =
        TextEditingController(text: settings.storeAddress);
    final phoneController = TextEditingController(text: settings.storePhone);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profil Toko'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama Toko',
                    prefixIcon: Icon(Icons.storefront_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Nama toko wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Alamat (opsional)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'No. Telepon (opsional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(context, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true) {
      await settings.setStoreProfile(
        name: nameController.text,
        address: addressController.text,
        phone: phoneController.text,
      );
    }
    nameController.dispose();
    addressController.dispose();
    phoneController.dispose();
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Create or change the 4-digit kasir PIN. When a PIN is already set the
/// current PIN must be entered first, and the PIN can be removed entirely.
class _PinSetupDialog extends StatefulWidget {
  final AppSettings settings;

  const _PinSetupDialog({required this.settings});

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  bool get _hasPin => widget.settings.hasPin;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.settings.setPin(_newCtrl.text.trim());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus PIN?'),
        content: const Text(
            'Kasir tidak lagi meminta PIN saat tombol Bayar ditekan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    await widget.settings.clearPin();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String? _digitValidator(String? v, {required String message}) {
    final val = v?.trim() ?? '';
    if (val.isEmpty) return message;
    if (val.length != 4 || int.tryParse(val) == null) {
      return 'Harus 4 digit angka';
    }
    return null;
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('PIN Keamanan Kasir'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasPin) ...[
                TextFormField(
                  controller: _currentCtrl,
                  obscureText: true,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: _decoration('PIN Saat Ini'),
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) return 'Masukkan PIN saat ini';
                    if (!widget.settings.verifyPin(val)) {
                      return 'PIN saat ini salah';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _newCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration:
                    _decoration(_hasPin ? 'PIN Baru (4 digit)' : 'PIN (4 digit)'),
                validator: (v) =>
                    _digitValidator(v, message: 'PIN wajib diisi'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: true,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: _decoration('Ulangi PIN'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Ulangi PIN';
                  if (v.trim() != _newCtrl.text.trim()) return 'PIN tidak sama';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_hasPin)
          TextButton(
            onPressed: _saving ? null : _removePin,
            child: Text('Hapus PIN', style: TextStyle(color: scheme.error)),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}