import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:path/path.dart';

import '../models/admin_fee.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/transaction.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _database;

  DatabaseHelper._();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'cashier.db');
    return openDatabase(
      path,
      version: 11,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            cost_price REAL NOT NULL DEFAULT 0,
            stock INTEGER NOT NULL,
            category TEXT,
            category_id INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            datetime INTEGER NOT NULL,
            items TEXT NOT NULL,
            subtotal REAL NOT NULL,
            admin_fee REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            discount_label TEXT,
            total REAL NOT NULL,
            cash_received REAL NOT NULL,
            change REAL NOT NULL,
            buyer_name TEXT,
            payment_method TEXT,
            payment_detail TEXT,
            admin_fee_id INTEGER,
            bill_number TEXT,
            type TEXT NOT NULL DEFAULT 'sale',
            billing_category TEXT,
            billing_reference TEXT,
            extra_admin REAL NOT NULL DEFAULT 0,
            billing_subcategory TEXT,
            billing_fine REAL NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE admin_fees (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            amount REAL NOT NULL DEFAULT 0,
            order_index INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            order_index INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            datetime INTEGER NOT NULL,
            amount REAL NOT NULL,
            note TEXT NOT NULL DEFAULT ''
          )
        ''');

        await _seedDefaultAdminFees(db);
        await _seedDefaultCategories(db);
      },
      onOpen: (db) async {
        // Defensive repair: an older release could have created a `transactions`
        // table WITHOUT the admin_fee_id column while already recording DB
        // version 4 (so onUpgrade never re-runs). Ensure the column exists on
        // every open so inserts never fail with "no column named admin_fee_id".
        await _ensureColumn(db, 'transactions', 'admin_fee_id',
            'ALTER TABLE transactions ADD COLUMN admin_fee_id INTEGER');

        // bill_number (v6) — random bill reference shown on the receipt. Repair
        // it too so old rows can always be read.
        await _ensureColumn(db, 'transactions', 'bill_number',
            'ALTER TABLE transactions ADD COLUMN bill_number TEXT');

        // discount / discount_label (v7) — applied voucher/discount shown on the
        // receipt. Repair so old rows can always be read.
        await _ensureColumn(db, 'transactions', 'discount',
            'ALTER TABLE transactions ADD COLUMN discount REAL NOT NULL DEFAULT 0');
        await _ensureColumn(db, 'transactions', 'discount_label',
            'ALTER TABLE transactions ADD COLUMN discount_label TEXT');

        // Payment Point / PPOB (v10) — type of transaction plus billing
        // details (category, customer reference, additional admin charge).
        await _ensureColumn(db, 'transactions', 'type',
            "ALTER TABLE transactions ADD COLUMN type TEXT NOT NULL DEFAULT 'sale'");
        await _ensureColumn(db, 'transactions', 'billing_category',
            'ALTER TABLE transactions ADD COLUMN billing_category TEXT');
        await _ensureColumn(db, 'transactions', 'billing_reference',
            'ALTER TABLE transactions ADD COLUMN billing_reference TEXT');
        await _ensureColumn(db, 'transactions', 'extra_admin',
            'ALTER TABLE transactions ADD COLUMN extra_admin REAL NOT NULL DEFAULT 0');

        // PLN token vs bayar-listrik (v11) — sub-kind plus the postpaid fine.
        await _ensureColumn(db, 'transactions', 'billing_subcategory',
            'ALTER TABLE transactions ADD COLUMN billing_subcategory TEXT');
        await _ensureColumn(db, 'transactions', 'billing_fine',
            'ALTER TABLE transactions ADD COLUMN billing_fine REAL NOT NULL DEFAULT 0');

        // Ensure the admin-fee master table exists and is seeded, in case a
        // device upgraded from a very old build that never created it.
        try {
          final result = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='admin_fees'");
          if (result.isEmpty) {
            await db.execute('''
              CREATE TABLE admin_fees (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                amount REAL NOT NULL DEFAULT 0,
                order_index INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await _seedDefaultAdminFees(db);
            debugPrint('Skema diperbaiki: membuat tabel admin_fees.');
          }
        } catch (e) {
          debugPrint('Gagal memeriksa tabel admin_fees: $e');
        }

        // Ensure the categories table and products.category_id exist even if a
        // device upgraded from a build that never created them (same reasoning
        // as admin_fee_id above).
        await _ensureColumn(db, 'products', 'category_id',
            'ALTER TABLE products ADD COLUMN category_id INTEGER');

        // cost_price (v9) — cost/modal tracked on the product. Repair so old
        // installs can always insert/read products.
        await _ensureColumn(db, 'products', 'cost_price',
            'ALTER TABLE products ADD COLUMN cost_price REAL NOT NULL DEFAULT 0');

        try {
          final result = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'");
          if (result.isEmpty) {
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                order_index INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await _seedDefaultCategories(db);
            debugPrint('Skema diperbaiki: membuat tabel categories.');
          }
        } catch (e) {
          debugPrint('Gagal memeriksa tabel categories: $e');
        }

        // Ensure the expenses table exists (feature added in v8). Repair it on
        // open so the Expense screen never crashes on an older install.
        try {
          final result = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='expenses'");
          if (result.isEmpty) {
            await db.execute('''
              CREATE TABLE expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                datetime INTEGER NOT NULL,
                amount REAL NOT NULL,
                note TEXT NOT NULL DEFAULT ''
              )
            ''');
            debugPrint('Skema diperbaiki: membuat tabel expenses.');
          }
        } catch (e) {
          debugPrint('Gagal memeriksa tabel expenses: $e');
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 -> v2 added tax columns; we no longer create/use the taxes table,
        // but existing databases may already have it. We leave it in place and
        // simply don't read from it.
        if (oldVersion < 2) {
          // Keep the taxes table installed from v2 databases only if present.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS taxes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              value REAL NOT NULL,
              builtin INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }

        // v2 -> v3: drop the old tax snapshot column and add the new fields.
        if (oldVersion < 3) {
          final columns = await db.rawQuery('PRAGMA table_info(transactions)');
          final colNames = columns.map((c) => c['name']).toSet();

          if (!colNames.contains('admin_fee')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN admin_fee REAL NOT NULL DEFAULT 0');
          }
          if (!colNames.contains('buyer_name')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN buyer_name TEXT');
          }
          if (!colNames.contains('payment_method')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN payment_method TEXT');
          }
          if (!colNames.contains('payment_detail')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN payment_detail TEXT');
          }
        }

        // v3 -> v4: admin fee master data + link on transactions.
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS admin_fees (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              amount REAL NOT NULL DEFAULT 0,
              order_index INTEGER NOT NULL DEFAULT 0
            )
          ''');

          final columns = await db.rawQuery('PRAGMA table_info(transactions)');
          final colNames = columns.map((c) => c['name']).toSet();
          if (!colNames.contains('admin_fee_id')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN admin_fee_id INTEGER');
          }

          // Seed sensible defaults only if the table was just created (empty).
          final count = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM admin_fees'))!;
          if (count == 0) {
            await _seedDefaultAdminFees(db);
          }
        }

        // v4 -> v5: managed product categories + link on products.
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              order_index INTEGER NOT NULL DEFAULT 0
            )
          ''');

          final pcols = await db.rawQuery('PRAGMA table_info(products)');
          final pcolNames = pcols.map((c) => c['name']).toSet();
          if (!pcolNames.contains('category_id')) {
            await db.execute('ALTER TABLE products ADD COLUMN category_id INTEGER');
          }

          // Seed default categories only if the table is empty.
          final catCount = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM categories'))!;
          if (catCount == 0) {
            await _seedDefaultCategories(db);
          }

          // Backfill: map any legacy free-text category names to the new
          // category rows so existing products keep their grouping.
          await _backfillCategoryIds(db);
        }

        // v5 -> v6: random bill reference for the receipt.
        if (oldVersion < 6) {
          final columns = await db.rawQuery('PRAGMA table_info(transactions)');
          final colNames = columns.map((c) => c['name']).toSet();
          if (!colNames.contains('bill_number')) {
            await db.execute('ALTER TABLE transactions ADD COLUMN bill_number TEXT');
          }
        }

        // v6 -> v7: applied discount / voucher on transactions.
        if (oldVersion < 7) {
          final columns = await db.rawQuery('PRAGMA table_info(transactions)');
          final colNames = columns.map((c) => c['name']).toSet();
          if (!colNames.contains('discount')) {
            await db.execute(
                'ALTER TABLE transactions ADD COLUMN discount REAL NOT NULL DEFAULT 0');
          }
          if (!colNames.contains('discount_label')) {
            await db.execute(
                'ALTER TABLE transactions ADD COLUMN discount_label TEXT');
          }
        }

        // v7 -> v8: operational store expenses.
        if (oldVersion < 8) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                datetime INTEGER NOT NULL,
                amount REAL NOT NULL,
                note TEXT NOT NULL DEFAULT ''
              )
            ''');
          } catch (e) {
            debugPrint('Gagal membuat tabel expenses: $e');
          }
        }

        // v8 -> v9: cost (modal) on products.
        if (oldVersion < 9) {
          try {
            final pcols = await db.rawQuery('PRAGMA table_info(products)');
            final pcolNames = pcols.map((c) => c['name']).toSet();
            if (!pcolNames.contains('cost_price')) {
              await db.execute(
                  'ALTER TABLE products ADD COLUMN cost_price REAL NOT NULL DEFAULT 0');
            }
          } catch (e) {
            debugPrint('Gagal menambah cost_price: $e');
          }
        }

        // v9 -> v10: Payment Point (PPOB) columns on transactions.
        if (oldVersion < 10) {
          try {
            final tcols = await db.rawQuery('PRAGMA table_info(transactions)');
            final tcolNames = tcols.map((c) => c['name']).toSet();
            if (!tcolNames.contains('type')) {
              await db.execute(
                  "ALTER TABLE transactions ADD COLUMN type TEXT NOT NULL DEFAULT 'sale'");
            }
            if (!tcolNames.contains('billing_category')) {
              await db.execute(
                  'ALTER TABLE transactions ADD COLUMN billing_category TEXT');
            }
            if (!tcolNames.contains('billing_reference')) {
              await db.execute(
                  'ALTER TABLE transactions ADD COLUMN billing_reference TEXT');
            }
            if (!tcolNames.contains('extra_admin')) {
              await db.execute(
                  'ALTER TABLE transactions ADD COLUMN extra_admin REAL NOT NULL DEFAULT 0');
            }
          } catch (e) {
            debugPrint('Gagal menambah kolom PPOB transactions: $e');
          }
        }
        if (oldVersion < 11) {
          try {
            final tcols = await db.rawQuery('PRAGMA table_info(transactions)');
            final tcolNames = tcols.map((c) => c['name']).toSet();
            if (!tcolNames.contains('billing_subcategory')) {
              await db.execute(
                  'ALTER TABLE transactions ADD COLUMN billing_subcategory TEXT');
            }
            if (!tcolNames.contains('billing_fine')) {
              await db.execute(
                  'ALTER TABLE transactions ADD COLUMN billing_fine REAL NOT NULL DEFAULT 0');
            }
          } catch (e) {
            debugPrint('Gagal menambah kolom PLN transactions: $e');
          }
        }
      },
    );
  }

  Future<void> _seedDefaultAdminFees(Database db) async {
    final fees = [
      {'name': 'Tanpa Admin', 'amount': 0.0, 'order_index': 0},
      {'name': 'Admin QRIS', 'amount': 1000.0, 'order_index': 1},
      {'name': 'Admin Bank', 'amount': 2500.0, 'order_index': 2},
    ];
    for (final fee in fees) {
      await db.insert('admin_fees', fee);
    }
  }

  Future<void> _seedDefaultCategories(Database db) async {
    const names = ['Pakan Ayam', 'Voucher Wifi', 'Pulsa', 'Bensin'];
    for (var i = 0; i < names.length; i++) {
      await db.insert('categories', {
        'name': names[i],
        'order_index': i,
      });
    }
  }

  /// Matches legacy free-text product categories to rows in the new categories
  /// table, creating a category on demand, and stores the resolved id on the
  /// product. Idempotent: only touches products that lack a category_id.
  Future<void> _backfillCategoryIds(Database db) async {
    try {
      final rows = await db.rawQuery('''
        SELECT id, category FROM products
        WHERE (category IS NOT NULL AND category != '' AND category_id IS NULL)
      ''');
      for (final row in rows) {
        final name = (row['category'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;

        var existing = await db.query(
          'categories',
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        int? catId;
        if (existing.isEmpty) {
          final order = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COALESCE(MAX(order_index), -1) + 1 AS n FROM categories'))!;
          catId = await db.insert('categories', {
            'name': name,
            'order_index': order,
          });
        } else {
          catId = existing.first['id'] as int;
        }

        await db.update(
          'products',
          {'category_id': catId},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    } catch (e) {
      debugPrint('Gagal mengisi category_id produk: $e');
    }
  }

  Future<void> _ensureColumn(
      Database db, String table, String column, String sql) async {
    try {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      final colNames = columns.map((c) => c['name']).toSet();
      if (!colNames.contains(column)) {
        await db.execute(sql);
        debugPrint('Skema diperbaiki: menambahkan kolom $column pada $table.');
      }
    } catch (e) {
      debugPrint('Gagal memeriksa kolom $column di $table: $e');
    }
  }

  // ---------------- Products ----------------
  Future<List<Product>> getProducts({String? searchQuery}) async {
    final db = await instance.database;
    final sql = searchQuery == null || searchQuery.isEmpty
        ? '''
            SELECT p.id, p.name, p.price, p.cost_price, p.stock, p.category,
                   p.category_id, COALESCE(c.name, p.category) AS category_name
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            ORDER BY p.name ASC
          '''
        : '''
            SELECT p.id, p.name, p.price, p.cost_price, p.stock, p.category,
                   p.category_id, COALESCE(c.name, p.category) AS category_name
            FROM products p
            LEFT JOIN categories c ON c.id = p.category_id
            WHERE p.name LIKE ?
            ORDER BY p.name ASC
          ''';
    final rows = await db.rawQuery(
      sql,
      searchQuery == null || searchQuery.isEmpty ? [] : ['%$searchQuery%'],
    );
    return rows
        .map((e) => Product.fromMap({
              ...e,
              'category': e['category_name'],
            }))
        .toList();
  }

  /// Returns all categories in sort order, together with their products. Used
  /// by the POS screen to render the product grid grouped by category.
  Future<List<MapEntry<Category, List<Product>>>> getProductsByCategory() async {
    final categories = await getCategories();
    final products = await getProducts();
    return categories
        .map((cat) => MapEntry(
              cat,
              products.where((p) => p.categoryId == cat.id).toList(),
            ))
        .toList();
  }

  Future<int> insertProduct(Product product) async {
    final db = await instance.database;
    return db.insert('products', product.toMap());
  }

  Future<int> updateProduct(Product product) async {
    final db = await instance.database;
    return db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> reduceStock(int productId, int quantity) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE id = ?',
      [quantity, productId],
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  // ---------------- Admin Fees ----------------
  Future<List<AdminFee>> getAdminFees() async {
    final db = await instance.database;
    final rows = await db.query('admin_fees', orderBy: 'order_index ASC, id ASC');
    return rows.map((e) => AdminFee.fromMap(e)).toList();
  }

  Future<int> insertAdminFee(AdminFee fee) async {
    final db = await instance.database;
    final map = fee.toMap()..remove('id');
    final nextOrder = await db
        .rawQuery('SELECT COALESCE(MAX(order_index), -1) + 1 AS n FROM admin_fees');
    map['order_index'] = Sqflite.firstIntValue(nextOrder)!;
    return db.insert('admin_fees', map);
  }

  Future<int> updateAdminFee(AdminFee fee) async {
    final db = await instance.database;
    return db.update(
      'admin_fees',
      fee.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [fee.id],
    );
  }

  Future<int> deleteAdminFee(int id) async {
    final db = await instance.database;
    return db.delete('admin_fees', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAdminFeeOrder(int id, int orderIndex) async {
    final db = await instance.database;
    await db.update(
      'admin_fees',
      {'order_index': orderIndex},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- Categories ----------------
  Future<List<Category>> getCategories() async {
    final db = await instance.database;
    final rows =
        await db.query('categories', orderBy: 'order_index ASC, id ASC');
    return rows.map((e) => Category.fromMap(e)).toList();
  }

  Future<int> insertCategory(Category category) async {
    final db = await instance.database;
    final map = category.toMap()..remove('id');
    final nextOrder = await db
        .rawQuery('SELECT COALESCE(MAX(order_index), -1) + 1 AS n FROM categories');
    map['order_index'] = Sqflite.firstIntValue(nextOrder)!;
    return db.insert('categories', map);
  }

  Future<int> updateCategory(Category category) async {
    final db = await instance.database;
    return db.update(
      'categories',
      category.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategory(int id) async {
    final db = await instance.database;
    // Detach products from the deleted category before removing the row.
    await db.update(
      'products',
      {'category_id': null},
      where: 'category_id = ?',
      whereArgs: [id],
    );
    return db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateCategoryOrder(int id, int orderIndex) async {
    final db = await instance.database;
    await db.update(
      'categories',
      {'order_index': orderIndex},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- Transactions ----------------
  Future<List<Transaction>> getTransactions() async {
    final db = await instance.database;
    final rows = await db.query('transactions', orderBy: 'datetime DESC');
    return rows.map((e) {
      final map = Map<String, dynamic>.from(e);
      map['items'] = jsonDecode(map['items'] as String);
      return Transaction.fromMap(map);
    }).toList();
  }

  Future<int> insertTransaction(Transaction transaction) async {
    final db = await instance.database;
    final map = <String, dynamic>{
      'datetime': transaction.datetime.millisecondsSinceEpoch,
      'items': jsonEncode(
          transaction.items.map((e) => e.toMap()).toList()),
      'subtotal': transaction.subtotal,
      'admin_fee': transaction.adminFee,
      'discount': transaction.discount,
      'discount_label': transaction.discountLabel,
      'total': transaction.total,
      'cash_received': transaction.cashReceived,
      'change': transaction.change,
      'buyer_name': transaction.buyerName,
      'payment_method': transaction.paymentMethod,
      'payment_detail': transaction.paymentDetail,
      'admin_fee_id': transaction.adminFeeId,
      'bill_number': transaction.billNumber,
      'type': transaction.type,
      'billing_category': transaction.billingCategory,
      'billing_reference': transaction.billingReference,
      'extra_admin': transaction.extraAdmin,
      'billing_subcategory': transaction.billingSubcategory,
      'billing_fine': transaction.billingFine,
    };
    return db.insert('transactions', map);
  }

  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// Absolute filesystem path of the SQLite database file. Used by the
  /// Backup feature to copy the whole database off-device.
  Future<String> get databaseFilePath async {
    return join(await getDatabasesPath(), 'cashier.db');
  }

  // ---------------- Expenses ----------------
  Future<List<Expense>> getExpenses() async {
    final db = await instance.database;
    final rows = await db.query('expenses', orderBy: 'datetime DESC');
    return rows.map((e) => Expense.fromMap(e)).toList();
  }

  /// Expenses whose [Expense.datetime] falls within [start] (inclusive) and
  /// [end] (exclusive), ordered oldest-first. Used for monthly reports.
  Future<List<Expense>> getExpensesInRange(
      DateTime start, DateTime end) async {
    final db = await instance.database;
    final rows = await db.query(
      'expenses',
      where: 'datetime >= ? AND datetime < ?',
      whereArgs: [
        start.millisecondsSinceEpoch,
        end.millisecondsSinceEpoch,
      ],
      orderBy: 'datetime ASC',
    );
    return rows.map((e) => Expense.fromMap(e)).toList();
  }

  Future<int> insertExpense(Expense expense) async {
    final db = await instance.database;
    final map = expense.toMap()..remove('id');
    return db.insert('expenses', map);
  }

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }
}