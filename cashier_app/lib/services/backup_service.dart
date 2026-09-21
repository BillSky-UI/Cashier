import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

/// Backup & Restore the local SQLite database.
///
/// Backup copies the whole [cashier.db] file (transactions, products,
/// categories, admin fees, and expenses) into a timestamped file, then presents
/// it through the system share sheet so it can be saved anywhere on the device
/// or sent to cloud storage.
///
/// Restore reads a previously-exported `.db` file picked by the user, replaces
/// the active database, and forces the app to reopen it. Returns a human
/// readable message on success, or null/error otherwise.
class BackupService {
  BackupService._();

  static String _timestamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// Exports the database and opens the share sheet to save the file.
  /// Returns a short result message, or null if the user cancelled.
  static Future<String?> backup() async {
    final dbPath = await DatabaseHelper.instance.databaseFilePath;
    final src = File(dbPath);
    if (!await src.exists()) {
      return 'File database tidak ditemukan.';
    }
    final bytes = await src.readAsBytes();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}billflow-backup-${_timestamp()}.db');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: 'Backup BillFlow',
        text: 'Backup data BillFlow (${file.path.split(Platform.pathSeparator).last})',
      ),
    );
    return null;
  }

  /// Restores the database from a user-picked `.db` file.
  /// Returns a short result message (non-null on error, or a success note).
  static Future<String?> restore() async {
    final file = await FilePicker.pickFile(
      type: FileType.any,
    );
    if (file == null) {
      return null; // user cancelled
    }
    final path = file.path;
    if (path == null) {
      return 'File yang dipilih tidak valid.';
    }
    final src = File(path);
    if (!await src.exists()) {
      return 'File tidak ditemukan.';
    }
    final bytes = await src.readAsBytes();

    // Close the active connection so the file is not locked before replacing.
    await DatabaseHelper.instance.close();
    final dbPath = await DatabaseHelper.instance.databaseFilePath;
    final dest = File(dbPath);
    await dest.writeAsBytes(bytes, flush: true);

    return 'Data berhasil dipulihkan. Aplikasi akan membaca database yang baru.';
  }
}
