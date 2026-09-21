import 'dart:async';

import 'package:flutter/material.dart';

import 'database/database_helper.dart';
import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'services/printer_permissions.dart';
import 'services/recap_archive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  // Close out and permanently archive completed previous month(s) whenever the
  // app starts in a new month (the monthly report "reset").
  unawaited(_runMonthlyRollover());
  // Pre-request Bluetooth/location runtime permissions so scanning/connecting
  // a thermal printer later is never blocked by a denied permission.
  unawaited(requestBluetoothPermissionsSilently());
  runApp(const CashierApp());
}

Future<void> _runMonthlyRollover() async {
  try {
    final transactions = await DatabaseHelper.instance.getTransactions();
    final expenses = await DatabaseHelper.instance.getExpenses();
    await RecapArchiveService.ensureRollover(
        transactions: transactions, expenses: expenses);
  } catch (_) {
    // Non-fatal: rollover retries on the next app start / report open.
  }
}

class CashierApp extends StatefulWidget {
  const CashierApp({super.key});

  @override
  State<CashierApp> createState() => _CashierAppState();
}

class _CashierAppState extends State<CashierApp> {
  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BillFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      themeMode: AppSettings.instance.themeMode,
      home: const HomeScreen(),
    );
  }
}