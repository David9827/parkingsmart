import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'data/slot_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
/// ========== 1) DASHBOARD ==========

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;

    // stream thống kê slot (AVAILABLE / RESERVED / OCCUPIED)
    final slotsStream = fs.collection('slots').snapshots();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [

          // ====== THỐNG KÊ SLOT HIỆN THỜI ======
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: slotsStream,
            builder: (context, snap) {
              final counts = _countSlots(snap.data);
              return Wrap(
                spacing: 12, runSpacing: 12,
                children: [
                  _StatCard(title: 'Đang đỗ', value: '${counts.occupied}'),
                  _StatCard(title: 'Đã đặt', value: '${counts.reserved}'),
                  _StatCard(title: 'Còn trống', value: '${counts.available}'),
                  // Doanh thu hôm nay: nếu bạn có field 'amount' trong reservations
                  FutureBuilder<_TodayRevenue>(
                    future: _loadTodayRevenue(fs),
                    builder: (_, revSnap) {
                      final text = revSnap.hasData ? revSnap.data!.label : '—';
                      return _StatCard(title: 'Doanh thu hôm nay', value: text);
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
// ====== ĐƠN GIÁ (đ/phút) ======
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('Đơn giá: ', style: TextStyle(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: StreamBuilder<int?>(
                      stream: SlotService().pricePerMinuteStream(),
                      builder: (_, s) {
                        final ctl = TextEditingController(
                          text: (s.data ?? 0).toString(),
                        );
                        return TextField(
                          controller: ctl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'VND/phút',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) async {
                            final p = int.tryParse(v.trim()) ?? 0;
                            await SlotService().setPricePerMinute(p);
                            ScaffoldMessenger.of(_).showSnackBar(
                              const SnackBar(content: Text('Đã lưu đơn giá')),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('VND/phút'),
                ],
              ),
            ),
          ),

          // ====== BIỂU ĐỒ 5 NGÀY GẦN NHẤT ======
          const _SectionTitle('Thống kê 5 ngày gần nhất'),
          _Last5DaysChartFS(fs: fs),   // dùng Firestore
          const SizedBox(height: 16),

          // ====== LỊCH SỬ GẦN ĐÂY CỦA CHÍNH USER ======
          const _SectionTitle('Gần đây'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Lịch sử các phiên đã kết thúc của chính user, sắp theo thời điểm rời bãi
            stream: fs.collection('reservations')
                .where('accountEmail', isEqualTo: auth.currentUser?.email)
                .where('status', isEqualTo: 'RELEASED')
                .orderBy('releasedAt', descending: true) // 👈 sắp theo thời điểm rời bãi
                .limit(5)
                .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snap.hasError) {
                // HIỂN THỊ LỖI để biết có phải thiếu index/rules hay không
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Không tải được lịch sử'),
                    subtitle: Text('${snap.error}'),
                  ),
                );
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Chưa có phiên đỗ xe nào'),
                    subtitle: const Text('Khi bạn trả chuồng (FREE), phiên sẽ hiển thị ở đây'),
                  ),
                );
              }

              return Column(
                children: docs.map((d) {
                  final m = d.data();
                  final slotId = m['slotId'] ?? '—';
                  final plate  = m['plate'] ?? '—';
                  final amount = (m['amount'] is int) ? m['amount'] as int : 0;
                  final releasedAt = (m['releasedAt'] as Timestamp?)?.toDate();
                  final time = releasedAt != null
                      ? DateFormat('HH:mm dd/MM').format(releasedAt.toLocal())
                      : '—';

                  final subtitle = amount > 0
                      ? '$plate • ${DashboardPage._formatVnd(amount)}'
                      : plate;

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.local_parking),
                      title: Text('$slotId • ĐÃ RỜI BÃI'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Dòng 1: biển số + số tiền
                          Text(
                            amount is int ? '$plate • ${DashboardPage._formatVnd(amount)}' : plate,
                          ),
                          // Dòng 2: giờ bắt đầu đỗ – giờ rời bãi (+ thời lượng phút)
                          Builder(builder: (_) {
                            final occupiedAt = (m['occupiedAt'] as Timestamp?)?.toDate();
                            final releasedAt = (m['releasedAt'] as Timestamp?)?.toDate();

                            String range;
                            String dur = '';
                            if (occupiedAt != null && releasedAt != null) {
                              final start = _fmtHM(occupiedAt);
                              final end   = _fmtHM(releasedAt);
                              final minutes = ((releasedAt.difference(occupiedAt).inSeconds + 59) ~/ 60);
                              range = '$start–$end';
                              dur = ' • $minutes phút';
                            } else if (occupiedAt != null) {
                              range = '${_fmtHM(occupiedAt)}–…';
                            } else {
                              range = '—';
                            }
                            return Text('$range$dur',
                                style: Theme.of(context).textTheme.bodySmall);
                          }),
                        ],
                      ),
                      trailing: Text(
                        // Hiển thị ngày của releasedAt cho gọn
                        _fmtDay((m['releasedAt'] as Timestamp?)?.toDate()),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

        ],
      ),
    );
  }

  // ---- helpers ----
  String _fmtHM(DateTime dt) => DateFormat('HH:mm').format(dt.toLocal());
  String _fmtDay(DateTime? dt) =>
      dt == null ? '—' : DateFormat('dd/MM').format(dt.toLocal());
  _SlotCounts _countSlots(QuerySnapshot<Map<String, dynamic>>? snap) {
    int a = 0, r = 0, o = 0;
    if (snap != null) {
      for (final d in snap.docs) {
        final st = (d.data()['state'] as String?) ?? 'AVAILABLE';
        switch (st) {
          case 'AVAILABLE': a++; break;
          case 'RESERVED':  r++; break;
          case 'OCCUPIED':  o++; break;
        }
      }
    }
    return _SlotCounts(available: a, reserved: r, occupied: o);
  }

  Future<_TodayRevenue> _loadTodayRevenue(FirebaseFirestore fs) async {
    // Nếu chưa có field 'amount' trong reservations, bạn có thể trả về số lượt RELEASED hôm nay.
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final startTs = Timestamp.fromDate(start);

    final qs = await fs.collection('reservations')
        .where('reservedAt', isGreaterThanOrEqualTo: startTs)
        .get();

    int total = 0;
    for (final d in qs.docs) {
      final m = d.data();
      final amt = m['amount'];
      if (amt is int) total += amt;
    }
    // Nếu không có amount nào, hiển thị số lượt:
    if (total == 0) return _TodayRevenue(label: '${qs.docs.length} lượt');
    return _TodayRevenue(label: _formatVnd(total));
  }

  static String _formatVnd(int v) {
    final f = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0);
    return f.format(v);
  }
}

class _SlotCounts {
  final int available, reserved, occupied;
  _SlotCounts({required this.available, required this.reserved, required this.occupied});
}

class _TodayRevenue {
  final String label;
  _TodayRevenue({required this.label});
}

/// Biểu đồ cột 5 ngày gần nhất (dữ liệu mock).

class _Last5DaysChartFS extends StatelessWidget {
  final FirebaseFirestore fs;
  const _Last5DaysChartFS({required this.fs, super.key});

  Future<List<_DayPoint>> _load() async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 4));
    final qs = await fs.collection('reservations')
        .where('reservedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(
      DateTime(from.year, from.month, from.day),
    ))
        .get();

    // gom theo ngày (yyyy-MM-dd) -> count
    final map = <String, int>{};
    for (final d in qs.docs) {
      final dt = (d['reservedAt'] as Timestamp?)?.toDate();
      if (dt == null) continue;
      final dayKey = DateFormat('yyyy-MM-dd').format(DateTime(dt.year, dt.month, dt.day));
      map.update(dayKey, (v) => v + 1, ifAbsent: () => 1);
    }

    // tạo đủ 5 điểm (kể cả ngày không có dữ liệu)
    final list = <_DayPoint>[];
    for (int i = 4; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
      list.add(_DayPoint(date: d, value: (map[key] ?? 0).toDouble()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DayPoint>>(
      future: _load(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
        }
        final points = snap.data!;
        final df = DateFormat('dd/MM');
        final maxY = (points.map((e) => e.value).fold<double>(0, (p, c) => c > p ? c : p) * 1.25).ceilToDouble();

        return Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.teal.withOpacity(0.06), Colors.blue.withOpacity(0.06)],
            ),
            border: Border.all(color: Colors.black12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: BarChart(
            BarChartData(
              maxY: maxY < 5 ? 5 : maxY,
              gridData: FlGridData(
                drawHorizontalLine: true, horizontalInterval: 1,
                getDrawingHorizontalLine: (v) => const FlLine(color: Colors.black12, strokeWidth: 1),
                drawVerticalLine: false,
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true, reservedSize: 28,
                    getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                        style: const TextStyle(color: Colors.black54, fontSize: 11)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(df.format(points[idx].date),
                            style: const TextStyle(fontSize: 11, color: Colors.black87)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                for (int i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i, barsSpace: 6,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].value,
                        width: 16,
                        gradient: const LinearGradient(
                          colors: [Colors.teal, Colors.blueAccent],
                          begin: Alignment.bottomCenter, end: Alignment.topCenter,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  ),
              ],
            ),
            swapAnimationDuration: const Duration(milliseconds: 600),
          ),
        );
      },
    );
  }
}

class _DayPoint {
  final DateTime date;
  final double value;
  _DayPoint({required this.date, required this.value});
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160, height: 96,
      child: Card(
        elevation: 0.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// ========== 2) CÁC CHUỒNG XE ==========
/// ========== 2) CÁC CHUỒNG XE (Firestore + thao tác trực tiếp) ==========



class SlotsPage extends StatefulWidget {
  const SlotsPage({super.key});
  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> {
  final svc = SlotService();
  String? email;

  @override
  void initState() {
    super.initState();
    email = FirebaseAuth.instance.currentUser?.email;
    svc.seedIfEmpty();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // thanh trạng thái nhỏ
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Text('Tài khoản: ${email ?? "—"}', style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              FilledButton.tonal(onPressed: () => svc.seedIfEmpty(), child: const Text('Seed 5 chuồng')),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<List<Slot>>(
            stream: svc.streamAll(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Lỗi: ${snap.error}'));
              }
              final data = snap.data ?? const [];
              if (data.isEmpty) return const Center(child: Text('Chưa có chuồng nào'));

              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5, crossAxisSpacing: 1, mainAxisSpacing: 8, childAspectRatio: 0.6,
                ),
                itemCount: data.length,
                itemBuilder: (_, i) {
                  final s = data[i];
                  final isMine = s.reservedBy == email;
                  final color = switch (s.state) {
                    'AVAILABLE' => Colors.green,
                    'RESERVED'  => isMine ? Colors.red.shade700 : Colors.red,
                    'OCCUPIED'  => Colors.black,
                    _           => Colors.grey,
                  };

                  return Card(
                    color: color,
                    child: InkWell(
                      onTap: () => _openSlotActions(s),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (s.state == 'RESERVED' && s.reservedAt != null)
                              _ReserveCountdown(slot: s, svc: svc),

                            Text(s.id,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                            if (s.state == 'OCCUPIED' && (s.plate?.isNotEmpty ?? false)) ...[
                              const SizedBox(height: 4),
                              Text(s.plate!, style: const TextStyle(color: Colors.white)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              s.state == 'AVAILABLE'
                                  ? 'AVAILABLE'
                                  : s.state == 'RESERVED'
                                  ? (isMine ? 'RESERVED (bạn)' : 'RESERVED')
                                  : 'OCCUPIED',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const _LegendBarNew(),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _openSlotActions(Slot s) async {
    // Mở bottom sheet các hành động hợp lệ theo trạng thái hiện tại
    final actions = <_ActionItem>[];

    switch (s.state) {
      case 'AVAILABLE':
        actions.add(_ActionItem(
          label: 'Đặt chỗ (RESERVE)',
          icon: Icons.event_available,
          run: () async {
            final plate = await _askPlate(context);
            if (plate != null && plate.isNotEmpty) {
              await svc.reserve(s.id, plate);
              _toast('Đã đặt ${s.id}');
            }
          },
        ));
        actions.add(_ActionItem(
          label: 'Đánh dấu đã đỗ (OCCUPY)',
          icon: Icons.directions_car,
          run: () async {
            final plate = await _askPlate(context);
            if (plate != null && plate.isNotEmpty) {
              await svc.occupy(s.id, plate);
              _toast('Đã chuyển ${s.id} -> OCCUPIED');
            }
          },
        ));
        break;

      case 'RESERVED':
        final isMine = s.reservedBy == email;
        if (isMine) {
          actions.add(_ActionItem(
            label: 'Hủy đặt (CANCEL)',
            icon: Icons.cancel,
            run: () async {
              await svc.cancel(s.id);
              _toast('Đã hủy đặt ${s.id}');
            },
          ));
          actions.add(_ActionItem(
            label: 'Đánh dấu đã đỗ (OCCUPY)',
            icon: Icons.directions_car,
            run: () async {
              final plate = await _askPlate(context);
              if (plate != null && plate.isNotEmpty) {
                await svc.occupy(s.id, plate);
                _toast('Đã chuyển ${s.id} -> OCCUPIED');
              }
            },
          ));
        } else {
          actions.add(_ActionItem(
            label: 'Chuồng đã được đặt bởi người khác',
            icon: Icons.info_outline,
            enabled: false,
            run: () async {},
          ));
        }
        break;

      case 'OCCUPIED':
        actions.add(_ActionItem(
          label: 'Trả chuồng (FREE)',
          icon: Icons.open_in_browser,
          run: () async {
            await svc.free(s.id);
            _toast('Đã trả ${s.id}');
          },
        ));
        break;
    }

    // show sheet
    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('Hành động cho ${s.id}')),
            const Divider(height: 1),
            for (final a in actions)
              ListTile(
                enabled: a.enabled,
                leading: Icon(a.icon),
                title: Text(a.label),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await a.run();
                  } catch (e) {
                    _toast('$e');
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<String?> _askPlate(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nhập biển số'),
        content: TextField(
          controller: ctl,
          decoration: const InputDecoration(
            labelText: 'Biển số xe',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    return ok == true ? ctl.text.trim() : null;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _ActionItem {
  final String label;
  final IconData icon;
  final Future<void> Function() run;
  final bool enabled;
  _ActionItem({required this.label, required this.icon, required this.run, this.enabled = true});
}

class _LegendBarNew extends StatelessWidget {
  const _LegendBarNew();
  Widget dot(Color c) => Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(children: [dot(Colors.green), const SizedBox(width: 6), const Text('AVAILABLE')]),
          Row(children: [dot(Colors.red), const SizedBox(width: 6), const Text('RESERVED')]),
          Row(children: [dot(Colors.black), const SizedBox(width: 6), const Text('OCCUPIED + biển số')]),
        ],
      ),
    );
  }
}

/// ========== 3) TÍNH TIỀN THEO THỜI GIAN ==========
class BillingPage extends StatefulWidget {
  const BillingPage({super.key});
  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  final _priceCtl = TextEditingController(text: '1000');     // VND/phút
  final _freeCtl  = TextEditingController(text: '10');        // phút miễn phí
  final _minutesCtl = TextEditingController(text: '45');      // demo input
  String _result = '—';

  @override
  void dispose() {
    _priceCtl.dispose(); _freeCtl.dispose(); _minutesCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // TODO: sau này thay minutes bằng (endAt - startAt) từ session Firestore
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _SectionTitle('Thông số tính tiền'),
          Row(
            children: [
              Expanded(child: _LabeledField(label: 'Giá (đ/phút)', controller: _priceCtl)),
              const SizedBox(width: 12),
              Expanded(child: _LabeledField(label: 'Miễn phí (phút)', controller: _freeCtl)),
            ],
          ),
          const SizedBox(height: 12),
          _LabeledField(label: 'Số phút đỗ (ví dụ)', controller: _minutesCtl),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _compute,
            icon: const Icon(Icons.calculate),
            label: const Text('Tính'),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Kết quả'),
              subtitle: Text(_result, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        ],
      ),
    );
  }

  void _compute() {
    final price = int.tryParse(_priceCtl.text.trim()) ?? 0;
    final free = int.tryParse(_freeCtl.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutesCtl.text.trim()) ?? 0;

    final billable = (minutes - free).clamp(0, 1 << 31);
    final amount = billable * price;

    setState(() {
      _result = 'Số phút tính phí: $billable\nThành tiền: ${_formatVnd(amount)}';
    });
  }

  String _formatVnd(int v) {
    // Placeholder gọn; có thể dùng intl NumberFormat sau
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final rev = s.length - i;
      buf.write(s[i]);
      if (rev > 1 && rev % 3 == 1) buf.write(',');
    }
    return '$buf đ';
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _LabeledField({required this.label, required this.controller});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}

class _ReserveCountdown extends StatefulWidget {
  final Slot slot;
  final SlotService svc;
  const _ReserveCountdown({required this.slot, required this.svc});

  @override
  State<_ReserveCountdown> createState() => _ReserveCountdownState();
}

class _ReserveCountdownState extends State<_ReserveCountdown> {
  late final Stream<int> _ticker;
  bool _expireCalled = false;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i);
  }
///Timer đếm giờ đợi reset về AVAILABLE
  @override
  Widget build(BuildContext context) {
    final ts = widget.slot.reservedAt; // Timestamp?
    if (ts == null) return const SizedBox.shrink();

    final start = ts.toDate();
    final deadline = start.add(const Duration(minutes: 10));

    return StreamBuilder<int>(
      stream: _ticker,
      builder: (_, __) {
        final remain = deadline.difference(DateTime.now()).inSeconds;

        if (remain <= 0 && !_expireCalled) {
          _expireCalled = true;
          widget.svc.expireIfTimedOut(widget.slot.id).catchError((_) {});
        }

        final text = remain > 0 ? _fmt(remain) : '00:00';
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        );
      },
    );
  }

  String _fmt(int secs) {
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

