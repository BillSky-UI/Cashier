import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/transaction.dart';
import '../services/app_settings.dart';
import '../utils/format.dart';

/// Renders a transaction as a receipt "paper" (print-ready layout) that can be
/// shown in the preview page after a sale, or reused when viewing history.
///
/// It mirrors a thermal-printed receipt:
///  - store logo (if configured) + header (name / address / phone)
///  - bill number + timestamp
///  - cashier and buyer
///  - itemized lines (name, qty, unit price, subtotal)
///  - totals (Subtotal, Biaya Admin, Total)
///  - conditional payment block (Tunai shows Tunai Bayar + Kembalian; other
///    methods show only the payment method + Total Bayar)
///  - custom footer (if set) + thank-you closing
class ReceiptPaper extends StatelessWidget {
  final Transaction transaction;

  const ReceiptPaper({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final method = paymentMethodByKey(t.paymentMethod);
    final isCash = method.key == 'cash';
    final settings = AppSettings.instance;

    final headerLines = <String>[
      if (settings.storeName.isNotEmpty) settings.storeName,
      if (settings.storeAddress.isNotEmpty) settings.storeAddress,
      if (settings.storePhone.isNotEmpty) 'Telp: ${settings.storePhone}',
    ];

    // The struk MUST always render on a pure white background with dark text,
    // regardless of the app theme, so the preview is clean, readable and
    // matches what a thermal printer produces on white paper.
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.black87, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Store header ----
            Center(
              child: Column(
                children: [
                  _StoreLogo(logoPath: settings.storeLogoPath),
                  Text(
                    settings.storeName.isEmpty
                        ? 'BillFlow'
                        : settings.storeName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (headerLines.length > 1)
                    for (final line in headerLines.sublist(1))
                      Text(
                        line,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(thickness: 1.5, color: Colors.black),
            const SizedBox(height: 6),

            // ---- Bill number & timestamp ----
            _line('No. Bill', t.billNumber ?? '#${t.id ?? '-'}'),
            _line('Waktu', formatDateTime(t.datetime)),
            _line('Kasir', settings.cashierName),
            if (t.buyerName != null)
              _line(t.isBilling ? 'Nama Pelanggan' : 'Pembeli', t.buyerName!),
            _line('Metode', method.label),

            // ---- PPOB detail (PLN / PDAM / BPJS) — same clean layout ----
            if (t.isBilling) ...[
              const SizedBox(height: 6),
              _line('Jenis', t.billingTypeDisplay),
              _line(t.billingReferenceLabel ?? 'No. Referensi',
                  t.billingReference ?? '-'),
            ],

            const Divider(thickness: 1, color: Colors.black),
            const SizedBox(height: 4),

            // ---- Items ----
            for (final item in t.items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.productName,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        formatRupiah(item.subtotal),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Text(
                    '${item.quantity} x ${formatRupiah(item.price)}',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],

          const Divider(thickness: 1, color: Colors.black),
          const SizedBox(height: 4),

          // ---- Totals ----
          _line(
              t.isBilling ? 'Nominal Tagihan' : 'Subtotal',
              formatRupiah(t.subtotal)),
          if (t.adminFee > 0)
            _line('Biaya Admin', formatRupiah(t.adminFee)),
          if (t.extraAdmin > 0)
            _line('Admin Tambahan', formatRupiah(t.extraAdmin)),
          if (t.billingFine > 0)
            _line('Biaya Denda', formatRupiah(t.billingFine)),
          if (t.discount > 0)
            _line(t.discountLabel ?? 'Diskon', '- ${formatRupiah(t.discount)}'),
          const SizedBox(height: 4),
          _line('Grand Total', formatRupiah(t.total),
              bold: true, larger: true, highlight: true),

          const Divider(thickness: 1, color: Colors.black),
          const SizedBox(height: 4),

          // ---- Payment block ----
          if (isCash) ...[
            _line('Metode', method.label),
            _line('Tunai Bayar', formatRupiah(t.cashReceived)),
            _line('Kembalian', formatRupiah(t.change), bold: true),
          ] else ...[
            _line('Metode', method.label),
            _line('Total Bayar', formatRupiah(t.total), bold: true),
          ],
          if (t.paymentDetail != null && t.paymentDetail!.isNotEmpty)
            _line('Detail', t.paymentDetail!),

          const SizedBox(height: 12),
          const Divider(thickness: 1.5, color: Colors.black),
          const SizedBox(height: 8),

          // ---- Footer ----
          const Center(
            child: Text(
              'TERIMA KASIH TELAH BERBELANJA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              'Simpan struk ini sebagai bukti pembayaran yang sah.',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              'Powered by BillFlow POS',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          if (settings.storeFooter.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(thickness: 1, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              settings.storeFooter,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ],
          ],
        ),
        ),
    );
  }

  Widget _line(String label, String value,
      {bool bold = false, bool larger = false, bool highlight = false}) {
    final baseStyle = TextStyle(
      fontSize: larger ? 15 : 12,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: baseStyle),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: highlight
                ? baseStyle.copyWith(
                    fontSize: 15,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  )
                : baseStyle,
          ),
        ],
      ),
    );
  }
}

/// Loads and renders the configured store logo, or nothing if none is set.
/// Supports the packaged [AppSettings.builtinLogoMarker] asset as well as an
/// absolute file path to a user-picked image.
class _StoreLogo extends StatelessWidget {
  final String logoPath;

  const _StoreLogo({required this.logoPath});

  @override
  Widget build(BuildContext context) {
    if (logoPath.isEmpty) return const SizedBox.shrink();

    final future = logoPath == AppSettings.builtinLogoMarker
        ? _readBuiltin()
        : _readFile(logoPath);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 64, maxWidth: 160),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  Future<Uint8List?> _readBuiltin() async {
    try {
      final raw = await rootBundle.load('assets/logo/Logo BillFlow.jpg');
      return raw.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readFile(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}