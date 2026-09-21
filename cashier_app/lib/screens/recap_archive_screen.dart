import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';
import '../models/expense.dart';
import '../models/transaction.dart';
import '../services/recap_archive_service.dart';
import '../utils/format.dart';

/// Permanent monthly recap archive.
///
/// Lists every month that has a saved PDF recap. Each entry can be opened in
/// an external PDF viewer, shared, or deleted. The current month can be saved
/// ("Rekap Sekarang") from here, and the folder is scanned fresh on load so
/// archived reports are always up to date.
class RecapArchiveScreen extends StatefulWidget {
  const RecapArchiveScreen({super.key});

  @override
  State<RecapArchiveScreen> createState() => _RecapArchiveScreenState();
}

class _RecapArchiveScreenState extends State<RecapArchiveScreen> {
  List<Transaction> _transactions = [];
  List<Expense> _expenses = [];
  List<DateTime> _archived = [];
  bool _loading = true;

  static const _months = <String>[
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tx = await DatabaseHelper.instance.getTransactions();
    final expenses = await DatabaseHelper.instance.getExpenses();
    // Close out any months that ended while away.
    await RecapArchiveService.ensureRollover(
        transactions: tx, expenses: expenses);
    final archived = await RecapArchiveService.listArchivedMonths();
    if (mounted) {
      setState(() {
        _transactions = tx;
        _expenses = expenses;
        _archived = archived;
        _loading = false;
      });
    }
  }

  String _monthLabel(DateTime m) => '${_months[m.month - 1]} ${m.year}';

  Future<void> _archive(DateTime month) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text('Menyimpan rekap ${_monthLabel(month)}...'),
      duration: const Duration(seconds: 1),
    ));
    final file = await RecapArchiveService.archiveMonth(
      month: month,
      transactions: _transactions,
      expenses: _expenses,
    );
    if (!mounted) return;
    if (file == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk bulan tersebut.')),
      );
      return;
    }
    messenger.showSnackBar(
        SnackBar(content: Text('Rekap ${_monthLabel(month)} tersimpan.')));
    await _load();
  }

  Future<void> _open(DateTime month) async {
    final messenger = ScaffoldMessenger.of(context);
    final path = await RecapArchiveService.pathForMonth(month);
    if (path == null || !File(path).existsSync()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('File rekap tidak ditemukan.')),
      );
      return;
    }
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Tidak ada aplikasi PDF. Gunakan opsi Bagikan.')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Gagal membuka PDF. Gunakan opsi Bagikan.')));
    }
  }

  Future<void> _share(DateTime month) async {
    final path = await RecapArchiveService.pathForMonth(month);
    if (path == null) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: 'application/pdf')],
      subject: 'Rekap bulanan BillFlow',
      text: 'Rekap bulanan ${_monthLabel(month)}',
    ));
  }

  Future<void> _confirmDelete(DateTime month) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Rekap?'),
        content: Text(
            'Rekap ${_monthLabel(month)} akan dihapus dari penyimpanan aplikasi. '
            'Lanjutkan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await RecapArchiveService.deleteMonth(month);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rekap ${_monthLabel(month)} dihapus.')),
      );
      await _load();
    }
  }

  void _pickMonthToArchive() async {
    final now = DateTime.now();
    final months = <DateTime>[
      DateTime(now.year, now.month), // current
      DateTime(now.year, now.month - 1), // last month
      DateTime(now.year, now.month - 2),
      DateTime(now.year, now.month - 3),
    ];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Rekap Bulanan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final m in months)
              ListTile(
                leading: const Icon(Icons.assessment_outlined),
                title: Text(_monthLabel(m)),
                onTap: () => Navigator.pop(sheetContext, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _archive(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arsip Rekap Bulanan'),
        actions: [
          IconButton(
            tooltip: 'Rekap bulan baru',
            icon: const Icon(Icons.add_chart_outlined),
            onPressed: _loading ? null : _pickMonthToArchive,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _archived.isEmpty
              ? _emptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _archived.length,
                  itemBuilder: (context, index) =>
                      _archiveTile(context, _archived[index]),
                ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('Belum ada rekap tersimpan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Setiap pergantian bulan, rekap bulan sebelumnya tersimpan '
              'otomatis. Anda juga bisa menyimpan rekap bulan tertentu melalui '
              'ikon + di pojok kanan atas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _pickMonthToArchive,
              icon: const Icon(Icons.add_chart_outlined),
              label: const Text('Rekap Sekarang'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _archiveTile(BuildContext context, DateTime month) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Icon(Icons.picture_as_pdf_outlined,
              color: scheme.onPrimaryContainer),
        ),
        title: Text(_monthLabel(month),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Laporan rekap bulanan · ${formatRupiah(_monthTotal(month))}'),
        isThreeLine: false,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'open':
                _open(month);
              case 'share':
                _share(month);
              case 'delete':
                _confirmDelete(month);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'open', child: Text('Buka PDF')),
            PopupMenuItem(value: 'share', child: Text('Bagikan')),
            PopupMenuItem(value: 'delete', child: Text('Hapus')),
          ],
        ),
        onTap: () => _open(month),
      ),
    );
  }

  double _monthTotal(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    return _transactions
        .where((t) => !t.datetime.isBefore(start) && t.datetime.isBefore(end))
        .fold(0.0, (s, t) => s + t.total);
  }
}
