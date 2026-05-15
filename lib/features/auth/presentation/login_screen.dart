import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Заповніть всі поля');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('Введіть коректну електронну пошту');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('Щось пішло не так. Спробуйте ще раз');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.flutter://login-callback/',
      );
      if (!launched && mounted) {
        _showError('Не вдалося відкрити сторінку входу Google');
      }
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('Не вдалося увійти через Google');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _normalizeEmail(_emailController.text);
    if (!_isValidEmail(email)) {
      _showError('Введіть email для відновлення паролю');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb
            ? null
            : 'io.supabase.flutter://login-callback/',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Лист для відновлення надіслано')),
        );
      }
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
    } catch (_) {
      _showError('Не вдалося надіслати лист для відновлення');
    }
  }

  String _normalizeEmail(String raw) {
    var s = raw.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u2060]'), '');
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r == 0xFF20) {
        buf.write('@');
      } else if (r == 0x0430) {
        buf.write('a');
      } else if (r == 0x0435) {
        buf.write('e');
      } else if (r == 0x0456) {
        buf.write('i');
      } else if (r == 0x043E) {
        buf.write('o');
      } else if (r == 0x0440) {
        buf.write('p');
      } else if (r == 0x0441) {
        buf.write('c');
      } else if (r == 0x0443) {
        buf.write('y');
      } else if (r == 0x0445) {
        buf.write('x');
      } else {
        buf.writeCharCode(r);
      }
    }
    return buf.toString();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  String _mapAuthError(String message) {
    final text = message.toLowerCase();
    if (text.contains('invalid login credentials')) {
      return 'Неправильна пошта або пароль';
    }
    if (text.contains('email not confirmed')) {
      return 'Підтвердіть email перед входом';
    }
    if (text.contains('unable to validate email') ||
        text.contains('invalid format')) {
      return 'Некоректна адреса пошти. Перевірте написання (латиниця, один @).';
    }
    if (text.contains('otp_expired') ||
        text.contains('invalid or has expired')) {
      return 'Посилання недійсне або прострочене. Запросіть новий лист підтвердження.';
    }
    if (text.contains('already registered') ||
        text.contains('user already registered')) {
      return 'Користувач з такою поштою вже існує';
    }
    return message;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.terrain,
                    size: 80,
                    color: Color(0xFF2E7D32),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Вхід',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Мобільний застосунок для гірських походів',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Увійти',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _resetPassword,
                      child: const Text(
                        'Забули пароль?',
                        style: TextStyle(color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        (_isLoading || _isGoogleLoading) ? null : _submitGoogle,
                    icon: _isGoogleLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.g_mobiledata, size: 20),
                    label: const Text('Увійти через Google'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text(
                      'Немає акаунту? Зареєструватися',
                      style: TextStyle(color: Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
