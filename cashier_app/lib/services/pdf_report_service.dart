import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/transaction.dart';
import '../services/app_settings.dart';
import '../utils/format.dart';
import '../utils/profit.dart';

/// Generates and shares a PDF version of the sales report (and expenses) for a
/// selected month. The PDF is produced entirely on-device and saved via the
/// system share sheet.
class PdfReportService {
  PdfReportService._();

  static const _months = <String>[
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  static List<Transaction> _monthTx(List<Transaction> all, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return all
        .where((t) => !t.datetime.isBefore(start) && t.datetime.isBefore(end))
        .toList();
  }

  static List<Expense> _monthExpenses(List<Expense> all, DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return all
        .where((e) => !e.datetime.isBefore(start) && e.datetime.isBefore(end))
        .toList();
  }

  static Future<Uint8List> generateBytes({
    required DateTime month,
    required List<Transaction> transactions,
    required List<Expense> expenses,
  }) async {
    final tx = _monthTx(transactions, month);
    final exp = _monthExpenses(expenses, month);

    final revenue = tx.fold(0.0, (s, t) => s + t.total);
    final totalExpense = exp.fold(0.0, (s, e) => s + e.amount);
    final items = tx.fold(0, (s, t) => s + t.items.length);
    final summary = ProfitCalculator.summarize(
      transactions: tx,
      expenses: exp,
    );
    final net = summary.netProfit;

    // Payment-method breakdown
    final payMap = <String, double>{};
    for (final t in tx) {
      final label = paymentMethodByKey(t.paymentMethod).label;
      payMap[label] = (payMap[label] ?? 0) + t.total;
    }

    final settings = AppSettings.instance;
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            'Laporan Penjualan',
            style: const pw.TextStyle(
                fontSize: 10, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              settings.storeName.isEmpty ? 'BillFlow' : settings.storeName,
              style: const pw.TextStyle(
                  fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (settings.storeAddress.isNotEmpty)
            pw.Center(
              child: pw.Text(settings.storeAddress,
                  style: const pw.TextStyle(fontSize: 10)),
            ),
          if (settings.storePhone.isNotEmpty)
            pw.Center(
              child: pw.Text('Telp: ${settings.storePhone}',
                  style: const pw.TextStyle(fontSize: 10)),
            ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              '${_months[month.month - 1]} ${month.year}',
              style: const pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // ---- Summary ----
          pw.TableHelper.fromTextArray(
            headers: ['Ringkasan', 'Nilai'],
            data: [
              ['Total Penjualan', formatRupiah(revenue)],
              ['Jumlah Transaksi', '${tx.length}'],
              ['Item Terjual', '$items'],
              ['HPP (Modal Barang)', formatRupiah(summary.cogs)],
              ['Laba Kotor', formatRupiah(summary.grossProfit)],
              ['Total Pengeluaran', formatRupiah(totalExpense)],
              ['Laba/Rugi Bersih', formatRupiah(net)],
            ],
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey100),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
          ),

          pw.SizedBox(height: 16),
          pw.Text('Rincian Penjualan per Hari',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),

          // ---- Daily breakdown ----
          _dailyTable(context, tx, month),

          pw.SizedBox(height: 16),
          pw.Text('Rincian Pengeluaran',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          if (exp.isEmpty)
            pw.Text('Tidak ada pengeluaran tercatat.',
                style: const pw.TextStyle(fontSize: 10))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Tanggal', 'Keterangan', 'Nominal'],
              data: [
                for (final e in exp)
                  [
                    formatDateTime(e.datetime),
                    e.note.isEmpty ? '-' : e.note,
                    formatRupiah(e.amount),
                  ],
              ],
              headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.red100),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
              },
            ),

          pw.SizedBox(height: 16),
          pw.Text('Pembagian Metode Pembayaran',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['Metode', 'Nominal'],
            data: [
              for (final e in payMap.entries)
                [e.key, formatRupiah(e.value)],
            ],
            headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.green100),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
          ),

          pw.SizedBox(height: 16),
          pw.Divider(),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Dibuat ${formatDateTime(DateTime.now())} · Kasir ${settings.cashierName}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    return bytes;
  }

  /// Generates the monthly PDF and presents it through the system share sheet.
  /// Returns null on success, or a human-readable error message.
  static Future<String?> exportMonthly({
    required DateTime month,
    required List<Transaction> transactions,
    required List<Expense> expenses,
  }) async {
    final bytes = await generateBytes(
      month: month,
      transactions: transactions,
      expenses: expenses,
    );
    return _sharePdf(bytes, month);
  }

  /// Generates the monthly PDF and writes it permanently into [archiveDir]
  /// (the recap archive folder in app storage). Returns the saved [File].
  static Future<File> saveMonthly({
    required DateTime month,
    required List<Transaction> transactions,
    required List<Expense> expenses,
    required Directory archiveDir,
  }) async {
    final bytes = await generateBytes(
      month: month,
      transactions: transactions,
      expenses: expenses,
    );
    final file = File(
        '${archiveDir.path}${Platform.pathSeparator}billflow-rekap-${month.year}-${month.month.toString().padLeft(2, '0')}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static pw.Widget _dailyTable(
      pw.Context context, List<Transaction> tx, DateTime month) {
    final days = <DateTime>[];
    for (var d = 1; d <= DateTime(month.year, month.month + 1, 0).day; d++) {
      days.add(DateTime(month.year, month.month, d));
    }
    final rows = <List<String>>[];
    for (final day in days) {
      final start = DateTime(day.year, day.month, day.day);
      final end = DateTime(day.year, day.month, day.day + 1);
      final dayTx = tx
          .where((t) =>
              !t.datetime.isBefore(start) && t.datetime.isBefore(end))
          .toList();
      final total = dayTx.fold(0.0, (s, t) => s + t.total);
      rows.add([
        '${day.day} ${_months[day.month - 1]}',
        '${dayTx.length}',
        formatRupiah(total),
      ]);
    }
    return pw.TableHelper.fromTextArray(
      headers: ['Tanggal', 'Transaksi', 'Penjualan'],
      data: rows,
      headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
      },
    );
  }

  static Future<String?> _sharePdf(List<int> bytes, DateTime month) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}billflow-laporan-${month.year}-${(month.month).toString().padLeft(2, '0')}.pdf');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Laporan Penjualan BillFlow',
      text: 'Laporan penjualan ${_months[month.month - 1]} ${month.year}',
    ));
    return null;
  }
}
