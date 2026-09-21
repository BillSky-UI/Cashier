import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';
import '../models/transaction.dart';
import 'pdf_report_service.dart';

/// Manages the permanent monthly recap archive.
///
/// At the start of every new month the previous month's financial data is
/// "closed" (reset for the on-screen report) by generating a PDF recap and
/// storing it permanently inside the app's documents folder
/// (`.../rekap/billflow-rekap-YYYY-MM.pdf`). These archived PDFs are kept
/// forever and can be re-opened from the recap archive screen at any time.
class RecapArchiveService {
  RecapArchiveService._();

  static const _lastArchivedKey = 'billflow_last_archived_month';

  /// The archive folder (created on demand).
  static Future<Directory> archiveDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}rekap');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _monthKey(DateTime m) =>
      '${m.year}-${m.month.toString().padLeft(2, '0')}';

  static DateTime _parseKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  /// Reads the most recently archived month, or null if none yet.
  static Future<DateTime?> lastArchivedMonth() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastArchivedKey);
    return raw == null ? null : _parseKey(raw);
  }

  static Future<void> _setLastArchived(DateTime month) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastArchivedKey, _monthKey(month));
  }

  /// Months that already have a permanent PDF recap, newest first.
  static Future<List<DateTime>> listArchivedMonths() async {
    final dir = await archiveDir();
    final months = <DateTime>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final match = RegExp(r'^billflow-rekap-(\d{4})-(\d{2})\.pdf$')
          .firstMatch(name);
      if (match == null) continue;
      final y = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      months.add(DateTime(y, m));
    }
    months.sort((a, b) => b.compareTo(a));
    return months;
  }

  /// The file path of the archived recap for [month], or null if not archived.
  static Future<String?> pathForMonth(DateTime month) async {
    final dir = await archiveDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}billflow-rekap-${_monthKey(month)}.pdf');
    return await file.exists() ? file.path : null;
  }

  /// Generates and saves the permanent PDF recap for [month]. Returns the
  /// saved file, or null if the month has no data to report.
  static Future<File?> archiveMonth({
    required DateTime month,
    required List<Transaction> transactions,
    required List<Expense> expenses,
  }) async {
    final tx = transactions.where((t) {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      return !t.datetime.isBefore(start) && t.datetime.isBefore(end);
    }).toList();
    final exp = expenses.where((e) {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      return !e.datetime.isBefore(start) && e.datetime.isBefore(end);
    }).toList();
    if (tx.isEmpty && exp.isEmpty) return null;

    final dir = await archiveDir();
    final file = await PdfReportService.saveMonthly(
      month: month,
      transactions: transactions,
      expenses: expenses,
      archiveDir: dir,
    );
    await _setLastArchived(month);
    return file;
  }

  /// Deletes the archived recap for [month]. Returns true if a file existed.
  static Future<bool> deleteMonth(DateTime month) async {
    final dir = await archiveDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}billflow-rekap-${_monthKey(month)}.pdf');
    if (!await file.exists()) return false;
    await file.delete();
    return true;
  }

  /// Called on every app start / report open.
  ///
  /// When a new month begins (or the marker is behind), every fully-completed
  /// month that still lacks a permanent recap is archived automatically. This
  /// is what "resets the monthly data at the start of each new month": past
  /// months are permanently captured and the on-screen report starts fresh for
  /// the current month.
  static Future<void> ensureRollover({
    required List<Transaction> transactions,
    required List<Expense> expenses,
  }) async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 1);
    // The latest fully-completed month is the previous month.
    final latestCompleted = DateTime(current.year, current.month - 1, 1);
    final lastArchived = await lastArchivedMonth();

    final DateTime cursor;
    if (lastArchived != null) {
      // Start one month after the last archived month.
      cursor = DateTime(lastArchived.year, lastArchived.month + 1, 1);
    } else {
      cursor = _earliestMonth(transactions, expenses) ?? latestCompleted;
    }

    // Archive each month from cursor up to (and including) latestCompleted.
    var m = cursor;
    while (!m.isAfter(latestCompleted)) {
      await archiveMonth(
        month: m,
        transactions: transactions,
        expenses: expenses,
      );
      m = DateTime(m.year, m.month + 1, 1);
    }
  }

  static DateTime? _earliestMonth(
      List<Transaction> tx, List<Expense> exp) {
    DateTime? earliest;
    for (final t in tx) {
      final m = DateTime(t.datetime.year, t.datetime.month);
      if (earliest == null || m.isBefore(earliest)) earliest = m;
    }
    for (final e in exp) {
      final m = DateTime(e.datetime.year, e.datetime.month);
      if (earliest == null || m.isBefore(earliest)) earliest = m;
    }
    return earliest;
  }
}
