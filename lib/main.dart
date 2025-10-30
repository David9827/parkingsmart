import 'package:flutter/material.dart';
import 'pages.dart';
import 'auth_gate.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // file sinh bởi flutterfire configure
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ParkingApp());
}

class ParkingApp extends StatelessWidget {
  const ParkingApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parking',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const AuthGate(), // AuthGate dùng FirebaseAuth bình thường
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _pages = const [DashboardPage(), SlotsPage(), BillingPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(['Dashboard','Chuồng xe','Tính tiền'][_index]),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Đăng xuất?'),
                  content: const Text('Bạn có chắc muốn đăng xuất không?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
                  ],
                ),
              );
              if (ok == true) await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Chuồng'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'Tính tiền'),
        ],
      ),
    );
  }
}
