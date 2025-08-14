// lib/models/purchase_transaction_adapter.dart
import 'package:hive/hive.dart';
import 'purchase_transaction.dart';

class PurchaseTransactionAdapter extends TypeAdapter<PurchaseTransaction> {
  @override
  final int typeId = 102; // unique & not reused elsewhere

  @override
  PurchaseTransaction read(BinaryReader r) {
    final dateMs = r.readInt();
    final amount = r.readDouble();
    final cost = r.readDouble();
    final hasExp = r.readBool();
    final expMs = hasExp ? r.readInt() : null;
    return PurchaseTransaction(
      date: DateTime.fromMillisecondsSinceEpoch(dateMs),
      amount: amount,
      cost: cost,
      expirationDate: expMs == null ? null : DateTime.fromMillisecondsSinceEpoch(expMs),
    );
  }

  @override
  void write(BinaryWriter w, PurchaseTransaction obj) {
    w
      ..writeInt(obj.date.millisecondsSinceEpoch)
      ..writeDouble(obj.amount)
      ..writeDouble(obj.cost)
      ..writeBool(obj.expirationDate != null);
    if (obj.expirationDate != null) {
      w.writeInt(obj.expirationDate!.millisecondsSinceEpoch);
    }
  }
}
