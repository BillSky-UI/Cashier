class AdminFee {
  final int? id;
  final String name;
  final double amount;
  final int orderIndex;

  AdminFee({
    this.id,
    required this.name,
    required this.amount,
    this.orderIndex = 0,
  });

  AdminFee copyWith({String? name, double? amount, int? orderIndex}) {
    return AdminFee(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
      'order_index': orderIndex,
    };
  }

  factory AdminFee.fromMap(Map<String, dynamic> map) {
    return AdminFee(
      id: map['id'],
      name: map['name'],
      amount: (map['amount'] as num).toDouble(),
      orderIndex: map['order_index'] ?? 0,
    );
  }
}