import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/data/avatar_storage_service.dart';

import '../../../core/validation/form_validators.dart';
import '../data/auth_service.dart';
import 'widgets/auth_form_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.physicalStepOnly = false,
  });

  final bool physicalStepOnly;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthService();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _ageController = TextEditingController();
  final _experienceController = TextEditingController();
  String _fitnessLevel = 'intermediate';
  final Set<String> _selectedInterests = {};
  File? _avatarFile;
  final ImagePicker _picker = ImagePicker();

  int _step = 1;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _ageError;
  String? _experienceError;
  StreamSubscription<AuthState>? _authSub;

  static const _interests = [
    ('Природа', 'nature'),
    ('Вершини', 'peaks'),
    ('Водоспади', 'waterfalls'),
    ('Ночівлі', 'overnight'),
    ('Групові походи', 'group'),
  ];

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      switch (data.event) {
        case AuthChangeEvent.signedIn:
          if (_isGoogleLoading) setState(() => _isGoogleLoading = false);
          _afterGoogleSignIn();
        case AuthChangeEvent.signedOut:
          if (_isGoogleLoading) setState(() => _isGoogleLoading = false);
        default:
          break;
      }
    });
    if (widget.physicalStepOnly) {
      _step = 2;
      _prefillFromSession();
    }
  }

  Future<void> _afterGoogleSignIn() async {
    if (widget.physicalStepOnly || _step == 2) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final meta = user.userMetadata;
    if (meta?['onboarding_complete'] == true) return;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('age')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null && profile['age'] != null) return;
    } catch (_) {}

    if (!mounted) return;
    context.go('/register?oauth=1');
  }

  Future<void> _prefillFromSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final meta = user.userMetadata;
    if (meta != null) {
      final fn = meta['first_name']?.toString();
      final ln = meta['last_name']?.toString();
      if (fn != null && fn.isNotEmpty) _firstNameController.text = fn;
      if (ln != null && ln.isNotEmpty) _lastNameController.text = ln;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _ageController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() => _avatarFile = File(picked.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не вдалося вибрати фото: $e')),
        );
      }
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final launched = await _auth.signInWithGoogle();
      if (!launched && mounted) {
        _showError('Не вдалося відкрити Google');
        setState(() => _isGoogleLoading = false);
      }
    } on AuthException catch (e) {
      _showError(_mapAuthError(e.message));
      if (mounted) setState(() => _isGoogleLoading = false);
    } catch (_) {
      _showError('Не вдалося увійти через Google');
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _clearStep1Errors() {
    setState(() {
      _firstNameError = null;
      _lastNameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmPasswordError = null;
    });
  }

  bool _validateStep1({
    required String first,
    required String last,
    required String email,
    required String password,
    required String confirm,
  }) {
    final firstNameError = FormValidators.personName(first, fieldLabel: 'імʼя');
    final lastNameError =
        FormValidators.personName(last, fieldLabel: 'прізвище');
    final emailError = FormValidators.email(email);
    final passwordError = FormValidators.password(password);
    final confirmPasswordError =
        FormValidators.confirmPassword(confirm, password);
    final ok = firstNameError == null &&
        lastNameError == null &&
        emailError == null &&
        passwordError == null &&
        confirmPasswordError == null;

    setState(() {
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmPasswordError = confirmPasswordError;
    });
    return ok;
  }

  Future<void> _showEmailConfirmationDialog(String email) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Підтвердіть email'),
        content: Text(
          'На адресу $email надіслано лист.\n\n'
          'Будь ласка, відкрийте його та натисніть на посилання для підтвердження реєстрації.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await _auth.resendSignupConfirmation(email);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Лист надіслано повторно')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Помилка: $e')),
                  );
                }
              }
            },
            child: const Text('Надіслати знову'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) context.go('/login');
            },
            child: const Text('До входу'),
          ),
        ],
      ),
    );
  }

  Future<void> _continueStep1() async {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final email = _normalizeEmail(_emailController.text);
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    _clearStep1Errors();
    if (!_validateStep1(
      first: first,
      last: last,
      email: email,
      password: password,
      confirm: confirm,
    )) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fullName = '$first $last'.trim();
      final response = await _auth.signUpWithEmail(
        email: email,
        password: password,
        data: {
          'first_name': first,
          'last_name': last,
          'full_name': fullName,
        },
      );

      if (response.session == null) {
        if (mounted) {
          await _showEmailConfirmationDialog(email);
        }
        return;
      }

      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'full_name': fullName,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) setState(() => _step = 2);
    } on AuthException catch (e) {
      final msg = _mapAuthError(e.message);
      setState(() {
        if (msg.contains('пошт') || msg.contains('email')) {
          _emailError = msg;
        } else {
          _passwordError = msg;
        }
      });
    } catch (_) {
      setState(() => _passwordError = 'Не вдалося зареєструватися');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _uploadAvatarOrContinueWithout(
    String userId,
    File file,
  ) async {
    try {
      return await AvatarStorageService().uploadAvatar(
        userId: userId,
        imageFile: file,
      );
    } on AvatarUploadException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Фото не завантажено: ${e.message} Профіль збережено без аватара.',
            ),
          ),
        );
      }
      return null;
    }
  }

  String _friendlySaveError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('row-level security') ||
        s.contains('storageexception') && s.contains('403')) {
      return 'Помилка збереження: не вдалося завантажити фото. Профіль збережено без аватара.';
    }
    return 'Помилка збереження: $e';
  }

  String? _resolvedFullName(
    User user,
    Map<String, dynamic>? existingProfile,
  ) {
    final meta = user.userMetadata;
    String? nameFromMeta = meta?['full_name']?.toString().trim();
    if (nameFromMeta == null || nameFromMeta.isEmpty) {
      final joined = [
        meta?['given_name'],
        meta?['family_name'],
      ]
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(' ');
      if (joined.isNotEmpty) nameFromMeta = joined;
    }
    if (nameFromMeta == null || nameFromMeta.isEmpty) {
      final fn = meta?['first_name']?.toString().trim() ?? '';
      final ln = meta?['last_name']?.toString().trim() ?? '';
      final combined = '$fn $ln'.trim();
      if (combined.isNotEmpty) nameFromMeta = combined;
    }

    final fromDb = (existingProfile?['full_name'] as String?)?.trim();
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;
    if (nameFromMeta != null && nameFromMeta.isNotEmpty) return nameFromMeta;

    final local =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();
    return local.isNotEmpty ? local : null;
  }

  Future<void> _skipProfileLater() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final existingProfile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      final fullName = _resolvedFullName(user, existingProfile);

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        if (fullName != null) 'full_name': fullName,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'onboarding_complete': true}),
      );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlySaveError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _finishStep2() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      context.go('/login');
      return;
    }

    final ageError =
        FormValidators.age(_ageController.text, requiredField: true);
    final experienceError =
        FormValidators.experienceText(_experienceController.text);
    if (ageError != null || experienceError != null) {
      setState(() {
        _ageError = ageError;
        _experienceError = experienceError;
      });
      return;
    }
    setState(() {
      _ageError = null;
      _experienceError = null;
    });
    final age = int.parse(_ageController.text.trim());

    setState(() => _isLoading = true);
    try {
      final existingProfile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();

      String? avatarUrl;
      if (_avatarFile != null) {
        avatarUrl = await _uploadAvatarOrContinueWithout(user.id, _avatarFile!);
      }

      final experienceText = _experienceController.text.trim();
      final fullName = _resolvedFullName(user, existingProfile);

      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        if (fullName != null) 'full_name': fullName,
        'age': age,
        'fitness_level': _fitnessLevel,
        'experience_count': 0,
        if (experienceText.isNotEmpty) 'bio': experienceText,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'hiking_interests': _selectedInterests.toList(),
            'onboarding_complete': true,
          },
        ),
      );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlySaveError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    if (text.contains('already registered') ||
        text.contains('user already registered')) {
      return 'Користувач з такою поштою вже існує';
    }
    if (text.contains('unable to validate email') ||
        text.contains('invalid format')) {
      return 'Некоректна адреса пошти';
    }
    return message;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _initials() {
    final f = _firstNameController.text.trim();
    final l = _lastNameController.text.trim();
    if (f.isNotEmpty && l.isNotEmpty) {
      return '${f[0]}${l[0]}'.toUpperCase();
    }
    if (f.isNotEmpty) return f[0].toUpperCase();
    final email = Supabase.instance.client.auth.currentUser?.email;
    return email != null && email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isLoading ? null : () => context.go('/login'),
        ),
        title: Text(_step == 1 ? 'Реєстрація' : 'Розкажіть про себе'),
      ),
      body: SafeArea(
        child: _step == 1 ? _buildStep1() : _buildStep2(),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Крок 1 з 2 • Обліковий запис',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.5,
              backgroundColor: Colors.grey[200],
              color: const Color(0xFF2E7D32),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 28),
          AuthFormField(
            controller: _firstNameController,
            errorText: _firstNameError,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_firstNameError != null)
                setState(() => _firstNameError = null);
            },
            decoration: _decoration('Імʼя', Icons.person_outline),
          ),
          const SizedBox(height: 16),
          AuthFormField(
            controller: _lastNameController,
            errorText: _lastNameError,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_lastNameError != null) setState(() => _lastNameError = null);
            },
            decoration: _decoration('Прізвище', Icons.person_outline),
          ),
          const SizedBox(height: 16),
          AuthFormField(
            controller: _emailController,
            errorText: _emailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
            decoration: _decoration('Email', Icons.email_outlined),
          ),
          const SizedBox(height: 16),
          AuthFormField(
            controller: _passwordController,
            errorText: _passwordError,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
            decoration: _decoration('Пароль', Icons.lock_outlined).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AuthFormField(
            controller: _confirmPasswordController,
            errorText: _confirmPasswordError,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_confirmPasswordError != null) {
                setState(() => _confirmPasswordError = null);
              }
            },
            decoration:
                _decoration('Підтвердіть пароль', Icons.lock_outline).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmPassword = !_obscureConfirmPassword,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _isLoading || _isGoogleLoading ? null : _continueStep1,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Далі'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isLoading || _isGoogleLoading ? null : _submitGoogle,
            icon: _isGoogleLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.g_mobiledata, size: 22),
            label: const Text('Продовжити з Google'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Вже є акаунт? Увійти'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Крок 2 з 2 • Туристичний профіль',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 1,
              backgroundColor: Color(0xFFE0E0E0),
              color: Color(0xFF2E7D32),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: const Color(0xFFE8F5E9),
                    backgroundImage:
                        _avatarFile != null ? FileImage(_avatarFile!) : null,
                    child: _avatarFile == null
                        ? Text(
                            _initials(),
                            style: const TextStyle(
                              fontSize: 32,
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
                TextButton(
                  onPressed: _pickAvatar,
                  child: const Text('Змінити фото'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AuthFormField(
            controller: _ageController,
            errorText: _ageError,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_ageError != null) setState(() => _ageError = null);
            },
            decoration: _decoration('Вік', Icons.calendar_today_outlined),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Рівень підготовки',
              prefixIcon: const Icon(Icons.fitness_center_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _fitnessLevel,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'beginner',
                    child: Text('Початківець'),
                  ),
                  DropdownMenuItem(
                    value: 'intermediate',
                    child: Text('Середній'),
                  ),
                  DropdownMenuItem(
                    value: 'advanced',
                    child: Text('Експерт'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _fitnessLevel = v ?? 'intermediate'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AuthFormField(
            controller: _experienceController,
            maxLines: 2,
            errorText: _experienceError,
            onChanged: (_) {
              if (_experienceError != null) {
                setState(() => _experienceError = null);
              }
            },
            decoration: _decoration(
              'Попередній досвід',
              Icons.hiking_outlined,
            ).copyWith(
              hintText: 'Наприклад: ~150 км за 2 роки',
              hintStyle: TextStyle(color: Colors.grey[500]),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Уподобання',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _interests.map((item) {
              final label = item.$1;
              final key = item.$2;
              final sel = _selectedInterests.contains(key);
              return FilterChip(
                label: Text(label),
                selected: sel,
                onSelected: (_) {
                  setState(() {
                    if (sel) {
                      _selectedInterests.remove(key);
                    } else {
                      _selectedInterests.add(key);
                    }
                  });
                },
                selectedColor: const Color(0xFFC8E6C9),
                checkmarkColor: const Color(0xFF2E7D32),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _isLoading ? null : _finishStep2,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Зберегти та продовжити'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isLoading ? null : _skipProfileLater,
            child: const Text('Заповнити профіль пізніше'),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label.isEmpty ? null : label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
