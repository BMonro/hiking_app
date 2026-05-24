import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/validation/form_validators.dart';
import '../data/auth_service.dart';
import 'widgets/auth_form_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!_isGoogleLoading || !mounted) return;
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
          setState(() => _isGoogleLoading = false);
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearFieldErrors() {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });
  }

  bool _validateForm({required String email, required String password}) {
    final emailError = FormValidators.email(email);
    final passwordError = FormValidators.password(password);
    final ok = emailError == null && passwordError == null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    return ok;
  }

  Future<void> _submit() async {
    final email = _normalizeEmail(_emailController.text);
    final password = _passwordController.text;

    _clearFieldErrors();
    if (!_validateForm(email: email, password: password)) return;

    setState(() => _isLoading = true);

    try {
      await _auth.signInWithPassword(email: email, password: password);
      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      final msg = _mapAuthError(e.message);
      final raw = e.message.toLowerCase();
      if (raw.contains('email not confirmed') && mounted) {
        await _offerResendConfirmation(email);
      }
      setState(() {
        if (raw.contains('email not confirmed') ||
            raw.contains('unable to validate email') ||
            raw.contains('invalid format')) {
          _emailError = msg;
        } else if (raw.contains('invalid login credentials')) {
          _passwordError = msg;
        } else if (raw.contains('email')) {
          _emailError = msg;
        } else {
          _passwordError = msg;
        }
      });
    } catch (_) {
      setState(() => _passwordError = 'Щось пішло не так. Спробуйте ще раз');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _offerResendConfirmation(String email) async {
    final resend = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Підтвердіть email'),
        content: const Text(
          'Акаунт ще не активований. Відкрийте лист підтвердження на цьому телефоні '
          '(посилання має відкрити застосунок Hikora). Можна надіслати лист повторно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Закрити'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Надіслати знову'),
          ),
        ],
      ),
    );
    if (resend != true || !mounted) return;
    try {
      await _auth.resendSignupConfirmation(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Лист підтвердження надіслано повторно')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showGlobalError(_mapAuthError(e.message));
      }
    } catch (_) {
      if (mounted) {
        _showGlobalError('Не вдалося надіслати лист');
      }
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final launched = await _auth.signInWithGoogle();
      if (!launched && mounted) {
        _showGlobalError('Не вдалося відкрити сторінку входу Google');
        setState(() => _isGoogleLoading = false);
      }
    } on AuthException catch (e) {
      _showGlobalError(_mapAuthError(e.message));
      if (mounted) setState(() => _isGoogleLoading = false);
    } catch (_) {
      _showGlobalError('Не вдалося увійти через Google');
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _normalizeEmail(_emailController.text);
    _clearFieldErrors();
    final emailError = FormValidators.email(email);
    if (emailError != null) {
      setState(() => _emailError = emailError);
      return;
    }
    try {
      await _auth.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Лист для відновлення надіслано')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _emailError = _mapAuthError(e.message));
    } catch (_) {
      setState(
        () => _emailError = 'Не вдалося надіслати лист для відновлення',
      );
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

  void _showGlobalError(String message) {
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
                  AuthFormField(
                    controller: _emailController,
                    errorText: _emailError,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AuthFormField(
                    controller: _passwordController,
                    errorText: _passwordError,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) {
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
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
