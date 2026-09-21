import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/expense.dart';
import '../models/transaction.dart';
import '../services/app_bus.dart';
import '../services/pdf_report_service.dart';
import '../services/recap_archive_service.dart';
import '../utils/format.dart';
import '../utils/profit.dart';
import 'recap_archive_screen.dart';

/// Weekday display names in Indonesian, indexed by [DateTime.weekday]
/// (1 = Monday ... 7 = Sunday).
const _weekdayNames = <int, String>{
  1: 'Senin',
  2: 'Selasa',
  3: 'Rabu',
  4: 'Kamis',
  5: 'Jumat',
  6: 'Sabtu',
  7: 'Minggu',
};

/// End-of-day / monthly sales report.
///
/// Top section summarises *today* (the "Tutup Kasir" summary): total revenue,
/// number of transactions, items sold, and a breakdown by payment method.
///
/// Below it, a monthly rekap lists every day of the selected month, grouped in
/// weekday order (Senin → Minggu), so it reads as a full month. The month is
/// navigable (previous/next) so it naturally continues into the following
/// month. All figures come from the local SQLite database (offline-first).
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List<Transaction> _transactions = [];
  List<Expense> _expenses = [];
  bool _loading = true;
  int? _selectedDay;
  late DateTime _month =
      DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
    _runRollover();
    AppBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_load);
    super.dispose();
  }

  /// Archives the completed previous month(s) permanently when a new month
  /// begins (the "reset" for the monthly report).
  Future<void> _runRollover() async {
    final tx = await DatabaseHelper.instance.getTransactions();
    final expenses = await DatabaseHelper.instance.getExpenses();
    await RecapArchiveService.ensureRollover(
        transactions: tx, expenses: expenses);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tx = await DatabaseHelper.instance.getTransactions();
    final expenses = await DatabaseHelper.instance.getExpenses();
    if (mounted) {
      setState(() {
        _transactions = tx;
        _expenses = expenses;
        _loading = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_monthTx.isEmpty && _monthExpenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data untuk dicetak.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Membuat PDF...'),
        duration: Duration(seconds: 1),
      ),
    );
    final error = await PdfReportService.exportMonthly(
      month: _month,
      transactions: _transactions,
      expenses: _expenses,
    );
    if (error != null && error.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  List<Expense> get _monthExpenses {
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 1);
    return _expenses
        .where((e) => !e.datetime.isBefore(start) && e.datetime.isBefore(end))
        .toList();
  }

  // ---------------- Today (Tutup Kasir) ----------------

  List<Transaction> get _todaysTx {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _transactions.where((t) => !t.datetime.isBefore(start)).toList();
  }

  double get _todayRevenue =>
      _todaysTx.fold(0.0, (sum, t) => sum + t.total);

  int get _todayItems =>
      _todaysTx.fold(0, (sum, t) => sum + (t.isBilling ? 0 : t.items.length));

  int get _todayCount => _todaysTx.length;

  Map<String, double> get _todayPaymentBreakdown {
    final map = <String, double>{};
    for (final t in _todaysTx) {
      final key = paymentMethodByKey(t.paymentMethod).label;
      map[key] = (map[key] ?? 0) + t.total;
    }
    return map;
  }

  void _showCloseDialog() {
    final breakdown = _todayPaymentBreakdown;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        title: const Text('Tutup Kasir — Hari Ini'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _summaryLine('Tanggal', _formattedToday()),
              const Divider(),
              _summaryLine('Total Penjualan', formatRupiah(_todayRevenue)),
              _summaryLine('Jumlah Transaksi', '$_todayCount'),
              _summaryLine('Item Terjual', '$_todayItems'),
              const Divider(),
              const Text('Pembagian Metode:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final entry in breakdown.entries)
                _summaryLine(entry.key, formatRupiah(entry.value)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String _formattedToday() {
    final now = DateTime.now();
    return '${_weekdayNames[now.weekday]} · ${formatDateTime(now)}';
  }

  // ---------------- Monthly rekap ----------------

  List<Transaction> get _monthTx {
    final nextMonth =
        DateTime(_month.year, _month.month + 1, 1);
    return _transactions
        .where((t) =>
            !t.datetime.isBefore(_month) &&
            t.datetime.isBefore(nextMonth))
        .toList();
  }

  void _prevMonth() => setState(() {
        _month = DateTime(_month.year, _month.month - 1);
        _selectedDay = null;
      });

  void _nextMonth() => setState(() {
        _month = DateTime(_month.year, _month.month + 1);
        _selectedDay = null;
      });

  double _dayTotal(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _monthTx
        .where((t) =>
            !t.datetime.isBefore(start) && t.datetime.isBefore(end))
        .fold(0.0, (sum, t) => sum + t.total);
  }

  int _dayCount(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _monthTx
        .where((t) =>
            !t.datetime.isBefore(start) && t.datetime.isBefore(end))
        .length;
  }

  // ---------------- Daily detail ----------------

  List<Transaction> _dayTx(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _monthTx
        .where((t) =>
            !t.datetime.isBefore(start) && t.datetime.isBefore(end))
        .toList();
  }

  List<Expense> _dayExp(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    return _monthExpenses
        .where((e) =>
            !e.datetime.isBefore(start) && e.datetime.isBefore(end))
        .toList();
  }

  double _dayRevenue(DateTime day) =>
      _dayTx(day).fold(0.0, (s, t) => s + t.total);

  double _dayExpenseTotal(DateTime day) =>
      _dayExp(day).fold(0.0, (s, e) => s + e.amount);

  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan & Tutup Kasir'),
        actions: [
          IconButton(
            tooltip: 'Arsip Rekap Bulanan',
            icon: const Icon(Icons.folder_zip_outlined),
            onPressed: _loading
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RecapArchiveScreen()),
                    ),
          ),
          IconButton(
            tooltip: 'Ekspor PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _loading ? null : _exportPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _sectionHeader(context, 'Tutup Kasir — Hari Ini'),
                    _todayCard(context),
                    const SizedBox(height: 16),
                    _sectionHeader(context, 'Rekap Bulanan'),
                    _monthNavigator(context),
                    const SizedBox(height: 8),
                    _profitCard(context),
                    const SizedBox(height: 8),
                    _dateStrip(context),
                    if (_selectedDay != null) ...[
                      const SizedBox(height: 8),
                      _dayDetail(context),
                    ],
                    const SizedBox(height: 8),
                    _sectionHeader(context, 'Rincian Bulanan'),
                    if (isWide)
                      _monthlyGrid(context)
                    else
                      _monthlyList(context),
                  ],
                );
              },
            ),
    );
  }

  // ---------------- Today card ----------------

  Widget _todayCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final breakdown = _todayPaymentBreakdown;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined,
                    color: scheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatRupiah(_todayRevenue),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary)),
                      const SizedBox(height: 2),
                      Text('$_todayCount transaksi · $_todayItems item',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Pembagian Metode Pembayaran',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (breakdown.isEmpty)
              const Text('Belum ada penjualan hari ini.',
                  style: TextStyle(color: Colors.grey))
            else
              for (final entry in breakdown.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key),
                      Text(formatRupiah(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _todayCount == 0 ? null : _showCloseDialog,
              icon: const Icon(Icons.lock_clock_outlined),
              label: const Text('Tutup Kasir'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Month navigation ----------------

  Widget _monthNavigator(BuildContext context) {
    const months = <String>[
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Bulan sebelumnya',
              icon: const Icon(Icons.chevron_left),
              onPressed: _prevMonth,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${months[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _monthTotal().toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Bulan berikutnya',
              icon: const Icon(Icons.chevron_right),
              onPressed: _nextMonth,
            ),
          ],
        ),
      ),
    );
  }

  String _monthTotal() {
    final total = _monthTx.fold(0.0, (sum, t) => sum + t.total);
    return '${_monthTx.length} transaksi · ${formatRupiah(total)}';
  }

  // ---------------- Monthly profit / loss ----------------

  /// Month-to-date profit & loss: revenue minus cost of goods sold, then minus
  /// operational expenses. Net negative = rugi (loss).
  Widget _profitCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = ProfitCalculator.summarize(
      transactions: _monthTx,
      expenses: _monthExpenses,
    );
    final isEmpty = _monthTx.isEmpty && _monthExpenses.isEmpty;
    final netPositive = summary.netProfit >= 0;
    final netColor = netPositive ? Colors.green.shade700 : scheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Laba / Rugi Bulanan',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const Divider(height: 20),
            if (isEmpty)
              Text('Belum ada data bulan ini.',
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else ...[
              _summaryLine('Pendapatan (Total Penjualan)',
                  formatRupiah(summary.revenue)),
              _summaryLine('HPP (Modal Barang Terjual)',
                  formatRupiah(summary.cogs)),
              _summaryLine('Laba Kotor', formatRupiah(summary.grossProfit)),
              _summaryLine('Pengeluaran Operasional',
                  formatRupiah(summary.expenses)),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    netPositive ? 'LABA BERSIH' : 'RUGI BERSIH',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    formatRupiah(summary.netProfit),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: netColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------- Monthly day rows ----------------

  /// Builds day entries ordered by weekday (Senin → Minggu) then by day number.
  List<DateTime> _orderedDays() {
    final days = <DateTime>[];
    for (var d = 1; d <= DateTime(_month.year, _month.month + 1, 0).day; d++) {
      days.add(DateTime(_month.year, _month.month, d));
    }
    days.sort((a, b) {
      final w = a.weekday.compareTo(b.weekday);
      return w != 0 ? w : a.day.compareTo(b.day);
    });
    return days;
  }

  /// Horizontal, tappable strip of every day in the selected month (the
  /// interactive date picker). Tapping a day reveals that day's detail card.
  Widget _dateStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _daysInMonth,
        itemBuilder: (context, index) {
          final dayNumber = index + 1;
          final day = DateTime(_month.year, _month.month, dayNumber);
          final hasSales = _dayTx(day).isNotEmpty;
          final selected = _selectedDay == dayNumber;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() =>
                  _selectedDay = selected ? null : dayNumber),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primary
                      : hasSales
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? scheme.onPrimary
                            : hasSales
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _weekdayNames[day.weekday]!.substring(0, 3),
                      style: TextStyle(
                        fontSize: 10,
                        color: selected
                            ? scheme.onPrimary
                            : hasSales
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Detail card for the currently selected day: total revenue, total expenses
  /// and the number of successful transactions that day, plus a breakdown of
  /// expenses.
  Widget _dayDetail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final day = DateTime(_month.year, _month.month, _selectedDay!);
    final revenue = _dayRevenue(day);
    final expense = _dayExpenseTotal(day);
    final count = _dayTx(day).length;
    final expenses = _dayExp(day);

    return Card(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_view_day_outlined,
                    color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rincian ${_weekdayNames[day.weekday]}, '
                    '${day.day} ${_monthNameShort(day.month)} ${day.year}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup rincian',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedDay = null),
                ),
              ],
            ),
            const Divider(),
            _summaryLine('Total Pendapatan', formatRupiah(revenue)),
            if (count > 0)
              _summaryLine(
                  'Laba Kotor',
                  formatRupiah(revenue - ProfitCalculator.cogsOf(_dayTx(day)))),
            _summaryLine('Total Pengeluaran', formatRupiah(expense)),
            _summaryLine('Jumlah Transaksi', '$count'),
            if (_selectedDay != null &&
                _selectedDay == DateTime.now().day &&
                _month.year == DateTime.now().year &&
                _month.month == DateTime.now().month) ...[
              const Divider(),
              _summaryLine('Item Terjual', '${_dayCount(day)}'),
            ],
            if (expenses.isNotEmpty) ...[
              const Divider(),
              const Text('Rincian Pengeluaran:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final e in expenses)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          e.note.isEmpty
                              ? formatDateTime(e.datetime)
                              : e.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(formatRupiah(e.amount),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthlyList(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final day in _orderedDays())
            _dayTile(context, day),
        ],
      ),
    );
  }

  Widget _monthlyGrid(BuildContext context) {
    final days = _orderedDays();
    return LayoutBuilder(
      builder: (context, constraints) {
        const colWidth = 220.0;
        final columns =
            (constraints.maxWidth / colWidth).floor().clamp(1, 5);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemCount: days.length,
          itemBuilder: (context, index) {
            return _dayCard(context, days[index]);
          },
        );
      },
    );
  }

  Widget _dayTile(BuildContext context, DateTime day) {
    final scheme = Theme.of(context).colorScheme;
    final total = _dayTotal(day);
    final count = _dayCount(day);
    final hasSales = count > 0;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: hasSales ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: hasSales ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(_weekdayNames[day.weekday]!),
      subtitle: Text('${day.day} ${_monthNameShort(day.month)}'),
      trailing: hasSales
          ? Text(
              '${formatRupiah(total)}\n$count transaksi',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            )
          : const Text('-', style: TextStyle(color: Colors.grey)),
    );
  }

  Widget _dayCard(BuildContext context, DateTime day) {
    final scheme = Theme.of(context).colorScheme;
    final total = _dayTotal(day);
    final count = _dayCount(day);
    final hasSales = count > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: hasSales
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: hasSales
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_weekdayNames[day.weekday]}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasSales ? formatRupiah(total) : '-',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hasSales ? scheme.primary : Colors.grey,
              ),
            ),
            Text(
              hasSales ? '$count transaksi' : 'Tidak ada penjualan',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _monthNameShort(int month) {
    const names = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return names[month - 1];
  }

  // ---------------- Helpers ----------------

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
