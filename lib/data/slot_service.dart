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
  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw Exception('Chưa đăng nhập');
    return u.uid;
  }
  String get _email => _auth.currentUser?.email ?? 'unknown';
  // config/pricing
  DocumentReference<Map<String, dynamic>> get _cfgRef =>
      _db.collection('config').doc('pricing');

// Stream đơn giá (để bind lên UI)
  Stream<int?> pricePerMinuteStream() => _cfgRef.snapshots().map((d) {
    final m = d.data();
    return (m?['pricePerMinute'] as int?);
  });

// Set đơn giá
  Future<void> setPricePerMinute(int price) async {
    await _cfgRef.set({'pricePerMinute': price}, SetOptions(merge: true));
  }
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
    final slotRef = _db.collection('slots').doc(slotId);
    final userRef = _db.collection('userStates').doc(_uid);
    final reservations = _db.collection('reservations');

    await _db.runTransaction((tx) async {
      final slot = await tx.get(slotRef);
      if (!slot.exists) throw Exception('Slot không tồn tại');
      final m = slot.data() as Map<String, dynamic>;
      if (m['state'] != 'AVAILABLE') throw Exception('Slot không khả dụng');

      // tạo reservation log
      final resRef = reservations.doc();
      tx.set(resRef, {
        'id': resRef.id,
        'slotId': slotId,
        'accountEmail': _email,
        'status': 'RESERVED',
        'reservedAt': FieldValue.serverTimestamp(),
        'plate': null,
        'releasedAt': null,
        'amount': null,
      });

      // cập nhật slot -> RESERVED
      tx.update(slotRef, {
        'state': 'RESERVED',
        'reservedBy': _email,
        'reservedAt': FieldValue.serverTimestamp(), // 👈 timer dựa vào đây
        'plate': null,
      });

      // cập nhật trạng thái user (để rules biết “đang giữ slot nào”)
      tx.set(userRef, {
        'activeSlotId': slotId,
        'activeReservationId': resRef.id,
      }, SetOptions(merge: true));
    });
  }


  /// HỦY chỗ: RESERVED -> AVAILABLE (chỉ chủ sở hữu)
  Future<void> cancel(String slotId) async {
    final slotRef = _db.collection('slots').doc(slotId);
    final userRef = _db.collection('userStates').doc(_uid);

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      final userSnap = await tx.get(userRef);
      if (!slotSnap.exists || !userSnap.exists) {
        throw Exception('Dữ liệu không hợp lệ');
      }
      final m = slotSnap.data() as Map<String, dynamic>;
      final u = userSnap.data() as Map<String, dynamic>;

      if (m['state'] != 'RESERVED' || m['reservedBy'] != _email) {
        throw Exception('Bạn không phải người đặt chuồng này');
      }
      if (u['activeSlotId'] != slotId) {
        throw Exception('Trạng thái người dùng không khớp');
      }

      final resId = u['activeReservationId'] as String?;

      // slot -> AVAILABLE
      tx.update(slotRef, {
        'state': 'AVAILABLE',
        'reservedBy': null,
        'reservedAt': null,
        'plate': null,
      });

      // userStates -> clear
      tx.update(userRef, {
        'activeSlotId': null,
        'activeReservationId': null,
      });

      // reservation -> CANCELLED (nếu có log)
      if (resId != null) {
        tx.update(_db.collection('reservations').doc(resId), {
          'status': 'CANCELLED',
          'closedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }
  Future<void> expireIfTimedOut(String slotId) async {
    final slotRef = _db.collection('slots').doc(slotId);
    await slotRef.update({
      'state': 'AVAILABLE',
      'reservedBy': null,
      'reservedAt': null,
      'plate': null,
    }).catchError((_) {
      // Nếu chưa đủ 10' theo server, rules sẽ từ chối -> bỏ qua
    });
  }


  /// ĐÁNH DẤU ĐÃ ĐỖ: (có thể từ AVAILABLE hoặc RESERVED) -> OCCUPIED + biển số
  Future<void> occupy(String slotId, String plate) async {
    final slotRef = _db.collection('slots').doc(slotId);
    final userRef = _db.collection('userStates').doc(_uid);

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      final userSnap = await tx.get(userRef);
      if (!slotSnap.exists || !userSnap.exists) {
        throw Exception('Dữ liệu không hợp lệ');
      }

      final m = slotSnap.data() as Map<String, dynamic>;
      final u = userSnap.data() as Map<String, dynamic>;
      if (m['state'] == 'AVAILABLE') {
        // Cho phép “đến thẳng” không reserve trước
      } else if (m['state'] == 'RESERVED') {
        if (m['reservedBy'] != _email) {
          throw Exception('Chuồng đã được người khác đặt');
        }
      } else if (m['state'] == 'OCCUPIED') {
        throw Exception('Chuồng đang có xe đỗ');
      }

      final resId = (u['activeReservationId'] as String?) ?? _db.collection('reservations').doc().id;

      // upsert reservation -> OCCUPIED
      final resRef = _db.collection('reservations').doc(resId);
      tx.set(resRef, {
        'id': resId,
        'slotId': slotId,
        'accountEmail': _email,
        'status': 'OCCUPIED',
        'plate': plate,
        'reservedAt': m['reservedAt'] ?? FieldValue.serverTimestamp(),
        'occupiedAt': FieldValue.serverTimestamp(), // 👈 thời điểm bắt đầu tính tiền
      }, SetOptions(merge: true));

      // slot -> OCCUPIED
      tx.update(slotRef, {
        'state': 'OCCUPIED',
        'reservedBy': _email,
        'reservedAt': m['reservedAt'] ?? FieldValue.serverTimestamp(),
        'plate': plate,
      });

      // user state
      tx.set(userRef, {
        'activeSlotId': slotId,
        'activeReservationId': resId,
      }, SetOptions(merge: true));
    });
  }

  /// TRẢ CHUỒNG: OCCUPIED -> AVAILABLE (xóa biển số)
  Future<void> free(String slotId) async {
    final slotRef = _db.collection('slots').doc(slotId);
    final userRef = _db.collection('userStates').doc(_uid);

    await _db.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      final userSnap = await tx.get(userRef);
      final cfgSnap  = await tx.get(_cfgRef);

      if (!slotSnap.exists || !userSnap.exists) {
        throw Exception('Dữ liệu không hợp lệ');
      }
      final slot = slotSnap.data() as Map<String, dynamic>;
      final user = userSnap.data() as Map<String, dynamic>;
      final price = (cfgSnap.data()?['pricePerMinute'] as int?) ?? 0;

      if (slot['state'] != 'OCCUPIED') {
        throw Exception('Chuồng chưa ở trạng thái OCCUPIED');
      }
      if (user['activeSlotId'] != slotId) {
        // cho phép trả ngay cả khi userStates lệch? Tùy: ở đây check chặt
        throw Exception('Trạng thái người dùng không khớp');
      }
      final resId = user['activeReservationId'] as String?;
      if (resId == null) throw Exception('Không tìm thấy reservation hiện tại');

      // đọc occupiedAt để tính phút
      final resRef = _db.collection('reservations').doc(resId);
      final resSnap = await tx.get(resRef);
      final res = resSnap.data() as Map<String, dynamic>?;

      final occupiedAt = (res?['occupiedAt'] as Timestamp?) ??
          (slot['reservedAt'] as Timestamp?); // fallback
      if (occupiedAt == null) throw Exception('Thiếu occupiedAt');

      // TÍNH PHÚT: ceil (now - occupiedAt).inMinutes
      final int minutes = ((DateTime.now().difference(occupiedAt.toDate()).inSeconds + 59) ~/ 60);
      final int amount = (minutes * price).clamp(0, 1<<31);

      // 1) reservation -> RELEASED
      tx.update(resRef, {
        'status': 'RELEASED',
        'releasedAt': FieldValue.serverTimestamp(),
        'minutes': minutes,
        'pricePerMinute': price,
        'amount': amount,              // 👈 VND
      });

      // 2) slot -> AVAILABLE
      tx.update(slotRef, {
        'state': 'AVAILABLE',
        'reservedBy': null,
        'reservedAt': null,
        'plate': null,
      });

      // 3) user state -> clear
      tx.update(userRef, {
        'activeSlotId': null,
        'activeReservationId': null,
      });
    });
  }

}
