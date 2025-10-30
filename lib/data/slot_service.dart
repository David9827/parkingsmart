import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Slot {
  final String id;
  final String state;      // "AVAILABLE" | "RESERVED" | "OCCUPIED"
  final String? reservedBy;
  final Timestamp? reservedAt;
  final String? plate;

  Slot({
    required this.id,
    required this.state,
    this.reservedBy,
    this.reservedAt,
    this.plate,
  });

  factory Slot.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Slot(
      id: d.id,
      state: (m['state'] as String?) ?? 'AVAILABLE',
      reservedBy: m['reservedBy'] as String?,
      reservedAt: m['reservedAt'] as Timestamp?,
      plate: m['plate'] as String?,
    );
  }
}

class SlotService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _email => _auth.currentUser?.email ?? 'unknown';

  /// Stream 5 chuồng (S1..S5) theo docId
  Stream<List<Slot>> streamAll() {
    return _db.collection('slots')
        .orderBy(FieldPath.documentId) // ✅ bỏ dấu ngoặc
        .snapshots()
        .map((snap) => snap.docs.map(Slot.fromDoc).toList());
  }

  /// Seed 5 chuồng nếu collection rỗng
  Future<void> seedIfEmpty() async {
    final has = await _db.collection('slots').limit(1).get();
    if (has.docs.isNotEmpty) return;
    final batch = _db.batch();
    for (int i = 1; i <= 5; i++) {
      final id = 'S$i';
      batch.set(_db.collection('slots').doc(id), {
        'state': 'AVAILABLE',
        'reservedBy': null,
        'reservedAt': null,
        'plate': null,
      });
    }
    await batch.commit();
  }

  /// ĐẶT chỗ: AVAILABLE -> RESERVED (người đặt = email hiện tại)
  Future<void> reserve(String slotId) async {
    final ref = _db.collection('slots').doc(slotId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Slot không tồn tại');
      final m = snap.data() as Map<String, dynamic>;
      if (m['state'] != 'AVAILABLE') throw Exception('Chuồng hiện không trống');
      tx.update(ref, {
        'state': 'RESERVED',
        'reservedBy': _email,
        'reservedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// HỦY chỗ: RESERVED -> AVAILABLE (chỉ chủ sở hữu)
  Future<void> cancel(String slotId) async {
    final ref = _db.collection('slots').doc(slotId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw Exception('Slot không tồn tại');
      final m = snap.data() as Map<String, dynamic>;
      if (m['state'] != 'RESERVED') throw Exception('Chuồng chưa được đặt');
      if (m['reservedBy'] != _email) throw Exception('Bạn không phải người đặt chuồng này');
      tx.update(ref, {
        'state': 'AVAILABLE',
        'reservedBy': null,
        'reservedAt': null,
        'plate': null,
      });
    });
  }

  /// ĐÁNH DẤU ĐÃ ĐỖ: (có thể từ AVAILABLE hoặc RESERVED) -> OCCUPIED + biển số
  Future<void> occupy(String slotId, String plate) async {
    final ref = _db.collection('slots').doc(slotId);
    await ref.update({
      'state': 'OCCUPIED',
      'plate': plate,
      // giữ nguyên reservedBy/reservedAt nếu trước đó là RESERVED (tuỳ bạn)
    });
  }

  /// TRẢ CHUỒNG: OCCUPIED -> AVAILABLE (xóa biển số)
  Future<void> free(String slotId) async {
    final ref = _db.collection('slots').doc(slotId);
    await ref.update({
      'state': 'AVAILABLE',
      'reservedBy': null,
      'reservedAt': null,
      'plate': null,
    });
  }
}
