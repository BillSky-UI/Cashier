import 'package:flutter/material.dart';

/// Supported payment methods for a sale.
class PaymentMethod {
  final String key;
  final String label;
  final IconData icon;
  const PaymentMethod(this.key, this.label, this.icon);
}

const paymentMethods = <PaymentMethod>[
  PaymentMethod('cash', 'Tunai', Icons.payments_outlined),
  PaymentMethod('qris', 'QRIS', Icons.qr_code_2),
  PaymentMethod('ewallet', 'E-Wallet', Icons.account_balance_wallet_outlined),
  PaymentMethod('bank', 'Transfer Bank', Icons.account_balance_outlined),
];

/// Finds a [PaymentMethod] by key, falling back to cash.
PaymentMethod paymentMethodByKey(String? key) {
  return paymentMethods.firstWhere(
    (m) => m.key == key,
    orElse: () => paymentMethods.first,
  );
}

class TransactionItem {
  final int productId;
  final String productName;
  final int quantity;
  final double price;

  /// Snapshot of the product's cost price (Harga Modal) at sale time, so the
  /// profit of historical sales stays stable even if the product is edited.
  /// Defaults to 0 for sales recorded before this field existed.
  final double cost;

  TransactionItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.cost = 0,
  });

  double get subtotal => price * quantity;

  /// Net profit of this line: (sell price - cost price) x quantity.
  double get profit => (price - cost) * quantity;

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'price': price,
      'cost': cost,
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      productId: map['product_id'],
      productName: map['product_name'],
      quantity: map['quantity'],
      price: (map['price'] as num).toDouble(),
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Transaction {
  final int? id;
  final DateTime datetime;
  final List<TransactionItem> items;
  final double subtotal;
  final double adminFee;

  /// Applied discount (rupiah amount) deducted from [subtotal] before [total].
  final double discount;

  /// Human-readable description of the discount/voucher, e.g. "Diskon 10%"
  /// or "Voucher Rp 5.000". Optional, used on the receipt.
  final String? discountLabel;

  final double total;
  final double cashReceived;
  final double change;
  final String? buyerName;
  final String? paymentMethod;
  final String? paymentDetail;

  /// Reference to the selected master-data admin fee; null if none selected.
  final int? adminFeeId;

  /// Human-friendly unique bill reference shown as "No. Bill", e.g. "BLF-84920".
  final String? billNumber;

  /// Legacy tax value kept for reading old records; always 0 for new ones.
  final double tax;

  /// Kind of transaction: 'sale' (regular POS sale) or 'billing' (Payment
  /// Point / PPOB payment such as PLN, PDAM or BPJS). Defaults to 'sale' for
  /// every transaction recorded before this field existed.
  final String type;

  /// Payment Point service category, e.g. "PLN", "PDAM" or "BPJS". Null (and
  /// unused) for regular sales.
  final String? billingCategory;

  /// Customer reference for the billing: PLN token / meter number, PDAM
  /// customer number or BPJS participant number. Used on the struk.
  final String? billingReference;

  /// Optional additional admin charge (Admin Tambahan) on top of the selected
  /// master-data [adminFee]. Only used by Payment Point transactions.
  final double extraAdmin;

  /// PLN transaction kind: 'token' (prabayar) or 'pascabayar'. Null for PDAM /
  /// BPJS and regular sales.
  final String? billingSubcategory;

  /// Late-payment fine (Biaya Denda) charged on PLN pascabayar bills.
  /// Always 0 for prabayar, PDAM, BPJS and regular sales.
  final double billingFine;

  Transaction({
    this.id,
    required this.datetime,
    required this.items,
    required this.subtotal,
    this.adminFee = 0,
    this.discount = 0,
    this.discountLabel,
    required this.total,
    required this.cashReceived,
    required this.change,
    this.buyerName,
    this.paymentMethod,
    this.paymentDetail,
    this.adminFeeId,
    this.billNumber,
    this.tax = 0,
    this.type = 'sale',
    this.billingCategory,
    this.billingReference,
    this.extraAdmin = 0,
    this.billingSubcategory,
    this.billingFine = 0,
  }) : assert(
            subtotal + adminFee - discount + extraAdmin + billingFine == total,
            'total must equal subtotal plus admin fee plus extra admin plus '
            'billing fine minus discount');

  /// True for Payment Point / PPOB (PLN, PDAM, BPJS) transactions.
  bool get isBilling => type == 'billing';

  /// 'Prabayar' / 'Pascabayar' for PLN token / bayar-listrik transactions.
  String? get billingSubcategoryLabel {
    switch (billingSubcategory) {
      case 'token':
        return 'Prabayar';
      case 'pascabayar':
        return 'Pascabayar';
      default:
        return null;
    }
  }

  /// The "Jenis" line shown on the struk, e.g. "PLN (Pascabayar)".
  String get billingTypeDisplay => [
        if (billingCategory != null) billingCategory,
        if (billingSubcategoryLabel != null) '($billingSubcategoryLabel)',
      ].join(' ');

  /// Label printed on the struk for [billingReference], depends on the
  /// selected category and PLN sub-kind (token reads "Kode Token",
  /// pascabayar reads "No. Meteran").
  String? get billingReferenceLabel {
    switch (billingCategory) {
      case 'PLN':
        return billingSubcategory == 'pascabayar'
            ? 'No. Meteran'
            : 'Kode Token';
      case 'PDAM':
        return 'No. Pelanggan';
      case 'BPJS':
        return 'No. Peserta';
      default:
        return null;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'datetime': datetime.millisecondsSinceEpoch,
      'items': items.map((e) => e.toMap()).toList(),
      'subtotal': subtotal,
      'admin_fee': adminFee,
      'discount': discount,
      'discount_label': discountLabel,
      'total': total,
      'cash_received': cashReceived,
      'change': change,
      'buyer_name': buyerName,
      'payment_method': paymentMethod,
      'payment_detail': paymentDetail,
      'admin_fee_id': adminFeeId,
      'bill_number': billNumber,
      'type': type,
      'billing_category': billingCategory,
      'billing_reference': billingReference,
      'extra_admin': extraAdmin,
      'billing_subcategory': billingSubcategory,
      'billing_fine': billingFine,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      datetime: DateTime.fromMillisecondsSinceEpoch(map['datetime']),
      items: (map['items'] as List<dynamic>)
          .map((e) => TransactionItem.fromMap(e as Map<String, dynamic>))
          .toList(),
      subtotal: (map['subtotal'] as num).toDouble(),
      adminFee: (map['admin_fee'] as num?)?.toDouble() ?? 0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      discountLabel: map['discount_label'] as String?,
      total: (map['total'] as num).toDouble(),
      cashReceived: (map['cash_received'] as num).toDouble(),
      change: (map['change'] as num).toDouble(),
      buyerName: map['buyer_name'] as String?,
      paymentMethod: map['payment_method'] as String?,
      paymentDetail: map['payment_detail'] as String?,
      adminFeeId: map['admin_fee_id'] as int?,
      billNumber: map['bill_number'] as String?,
      tax: (map['tax'] as num?)?.toDouble() ?? 0,
      type: map['type'] as String? ?? 'sale',
      billingCategory: map['billing_category'] as String?,
      billingReference: map['billing_reference'] as String?,
      extraAdmin: (map['extra_admin'] as num?)?.toDouble() ?? 0,
      billingSubcategory: map['billing_subcategory'] as String?,
      billingFine: (map['billing_fine'] as num?)?.toDouble() ?? 0,
    );
  }
}