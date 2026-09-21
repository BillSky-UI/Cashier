import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/transaction.dart';
import '../services/app_settings.dart';
import '../services/thermal_printer.dart';
import '../utils/format.dart';
import '../widgets/printer_dialog.dart';
import '../widgets/receipt_paper.dart';

/// Full-screen receipt preview shown immediately after a successful sale, and
/// reused when viewing a past transaction from history.
///
/// The receipt content is rendered by [ReceiptPaper] (a print-ready "paper"
/// layout). Below it, the user can either "Cetak" (print to a connected thermal
/// printer) or finish ("Selesai"). A second convenience action in the app bar
/// copies the struk text to the clipboard.
class ReceiptScreen extends StatefulWidget {
  final Transaction transaction;
  final String appBarTitle;
  final String doneLabel;

  const ReceiptScreen({
    super.key,
    required this.transaction,
    this.appBarTitle = 'Struk Digital',
    this.doneLabel = 'Selesai',
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  bool _printing = false;

  Transaction get transaction => widget.transaction;

  /// Builds a plain-text representation of the receipt, mirroring [ReceiptPaper]
  /// so users can paste the struk into chat/messaging apps.
  String _buildText(Transaction t) {
    final settings = AppSettings.instance;
    final method = paymentMethodByKey(t.paymentMethod);
    final isCash = method.key == 'cash';
    final b = StringBuffer()
      ..writeln('      ${settings.storeName.isNotEmpty ? settings.storeName : 'BillFlow'}')
      ..writeln(settings.storeAddress)
      ..writeln(settings.storePhone.isEmpty ? '' : 'Telp: ${settings.storePhone}')
      ..writeln('--------------------------------')
      ..writeln('No. Bill : ${t.billNumber ?? '#${t.id ?? '-'}'}')
      ..writeln('Waktu    : ${formatDateTime(t.datetime)}')
      ..writeln('Kasir    : ${settings.cashierName}');
    if (t.buyerName != null) b.writeln('Pembeli  : ${t.buyerName}');
    b.writeln('Metode   : ${method.label}');
    if (t.isBilling) {
      b
        ..writeln('Jenis    : ${t.billingTypeDisplay}')
        ..writeln('${t.billingReferenceLabel ?? 'No. Referensi'} : '
            '${t.billingReference ?? '-'}');
    }
    b.writeln('--------------------------------');
    for (final item in t.items) {
      b.writeln(item.productName);
      b.writeln('   ${item.quantity} x ${formatRupiah(item.price)}'
          '            ${formatRupiah(item.subtotal)}');
    }
    b
      ..writeln('--------------------------------')
      ..writeln('${t.isBilling ? 'Nominal Tagihan' : 'Subtotal'}      '
          '${formatRupiah(t.subtotal)}');
    if (t.adminFee > 0) b.writeln('Biaya Admin   ${formatRupiah(t.adminFee)}');
    if (t.extraAdmin > 0) {
      b.writeln('Admin Tambahan ${formatRupiah(t.extraAdmin)}');
    }
    if (t.billingFine > 0) {
      b.writeln('Biaya Denda   ${formatRupiah(t.billingFine)}');
    }
    if (t.discount > 0) {
      b.writeln('Diskon        - ${formatRupiah(t.discount)}');
    }
    b.writeln('GRAND TOTAL   ${formatRupiah(t.total)}');
    if (isCash) {
      b
        ..writeln('--------------------------------')
        ..writeln('Metode      ${method.label}')
        ..writeln('Tunai Bayar ${formatRupiah(t.cashReceived)}')
        ..writeln('Kembalian   ${formatRupiah(t.change)}');
    } else {
      b
        ..writeln('--------------------------------')
        ..writeln('Metode      ${method.label}')
        ..writeln('Total Bayar ${formatRupiah(t.total)}');
    }
    if (t.paymentDetail != null && t.paymentDetail!.isNotEmpty) {
      b.writeln('Detail      ${t.paymentDetail}');
    }
    b
      ..writeln('--------------------------------')
      ..writeln('TERIMA KASIH TELAH BERBELANJA')
      ..writeln('Simpan struk ini sebagai bukti pembayaran yang sah.')
      ..writeln('Powered by BillFlow POS');
    if (settings.storeFooter.isNotEmpty) {
      b
        ..writeln('--------------------------------')
        ..writeln(settings.storeFooter);
    }
    return b.toString();
  }

  Future<void> _copyToClipboard() async {
    final text = _buildText(transaction);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Struk disalin ke clipboard.')),
    );
  }

  /// Opens the printer picker (Bluetooth / USB / Network), then prints the
  /// struk to the selected thermal printer.
  Future<void> _cetak() async {
    final target = await showPrinterPicker(context);
    if (!mounted || target == null) return;

    setState(() => _printing = true);
    String? error;
    try {
      error = await ThermalPrinter.print(transaction, target);
    } finally {
      if (mounted) setState(() => _printing = false);
    }

    if (!mounted) return;
    final success = error == null;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Print Berhasil!' : 'Print Gagal karena: $error',
        ),
        backgroundColor: success
            ? Colors.green
            : Theme.of(context).colorScheme.error,
        duration: Duration(seconds: success ? 2 : 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.appBarTitle),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Salin struk',
            icon: const Icon(Icons.copy_outlined),
            onPressed: _printing ? null : _copyToClipboard,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  // Simulate a (narrow) receipt roll for a more authentic look
                  // on both phones and wide screens.
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: ReceiptPaper(transaction: transaction),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _printing
                        ? OutlinedButton.icon(
                            onPressed: null,
                            icon: const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: const Text('Mencetak...'),
                          )
                        : OutlinedButton.icon(
                            onPressed: _cetak,
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Cetak'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed:
                          _printing ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(widget.doneLabel,
                          style: const TextStyle(fontSize: 16)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}