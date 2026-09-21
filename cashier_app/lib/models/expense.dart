/// A recorded operational store expense (outside of sales), e.g. electricity,
/// plastic bags, cleaning supplies. Stored locally so the shop's financial
/// picture is accurate alongside sales revenue.
class Expense {
  final int? id;
  final DateTime datetime;
  final double amount;
  final String note;

  const Expense({
    this.id,
    required this.datetime,
    required this.amount,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'datetime': datetime.millisecondsSinceEpoch,
      'amount': amount,
      'note': note,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      datetime: DateTime.fromMillisecondsSinceEpoch(map['datetime']),
      amount: (map['amount'] as num).toDouble(),
      note: map['note'],
    );
  }
}
