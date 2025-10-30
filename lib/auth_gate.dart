import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'pages.dart'; // dùng HomeShell sau khi đăng nhập
import 'main.dart'; // dùng HomeShell sau khi đăng nhập

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data == null) return const _AuthSwitcher(); // chưa đăng nhập
        return const HomeShell(); // đã đăng nhập
      },
    );
  }
}

/// Widget chuyển giữa Login <-> Signup
class _AuthSwitcher extends StatefulWidget {
  const _AuthSwitcher();

  @override
  State<_AuthSwitcher> createState() => _AuthSwitcherState();
}

class _AuthSwitcherState extends State<_AuthSwitcher> {
  bool _isLogin = true;

  @override
  Widget build(BuildContext context) {
    return _isLogin
        ? _SignInPage(onSwitch: () => setState(() => _isLogin = false))
        : _SignUpPage(onSwitch: () => setState(() => _isLogin = true));
  }
}

/// ===================== ĐĂNG NHẬP =====================
class _SignInPage extends StatefulWidget {
  final VoidCallback onSwitch;
  const _SignInPage({required this.onSwitch});

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _signIn,
                  icon: _loading ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
                  ) : const Icon(Icons.login),
                  label: const Text('Đăng nhập'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onSwitch,
                  child: const Text('Chưa có tài khoản? Đăng ký'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ===================== ĐĂNG KÝ =====================
class _SignUpPage extends StatefulWidget {
  final VoidCallback onSwitch;
  const _SignUpPage({required this.onSwitch});

  @override
  State<_SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<_SignUpPage> {
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String? _error;

  Future<void> _signUp() async {
    final email = _email.text.trim();
    final pass  = _pass.text.trim();
    final conf  = _confirm.text.trim();

    if (email.isEmpty || pass.isEmpty || conf.isEmpty) {
      setState(() => _error = 'Vui lòng nhập đầy đủ thông tin.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Mật khẩu tối thiểu 6 ký tự.');
      return;
    }
    if (pass != conf) {
      setState(() => _error = 'Xác nhận mật khẩu không khớp.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pass);
      // (tuỳ chọn) Gửi email xác minh:
      // await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo tài khoản thành công!')),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _email.dispose(); _pass.dispose(); _confirm.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _obscure1,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure2,
                  decoration: InputDecoration(
                    labelText: 'Xác nhận mật khẩu',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _loading ? null : _signUp,
                  icon: _loading ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
                  ) : const Icon(Icons.app_registration),
                  label: const Text('Đăng ký'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onSwitch,
                  child: const Text('Đã có tài khoản? Đăng nhập'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
