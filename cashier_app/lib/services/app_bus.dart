import 'package:flutter/foundation.dart';

/// A single app-wide change notifier so every screen stays in sync in real
/// time without manual refresh. Whenever any data the UI depends on changes
/// (products, categories, admin fees, transactions), the mutating screen calls
/// [notifyChanged] and every subscribed screen reloads.
///
/// Because the main tabs live inside an [IndexedStack], each screen stays alive,
/// so this direct signal is required to keep them up to date the moment a sale
/// completes or master data is edited elsewhere.
class AppBus extends ChangeNotifier {
  AppBus._();
  static final AppBus instance = AppBus._();

  void notifyChanged() => notifyListeners();
}