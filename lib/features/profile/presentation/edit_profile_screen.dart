import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/validation/form_validators.dart';
import '../../../core/widgets/app_text_form_field.dart';
import '../data/avatar_storage_service.dart';
import 'profile_screen.dart';
import 'widgets/profile_avatar.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();
  final _preferredDurationController = TextEditingController();
  final _healthConditionsController = TextEditingController();
  String _fitnessLevel = 'beginner';
  String? _preferredDifficulty;
  bool _isSaving = false;
  File? _selectedImage;
  String? _existingAvatarUrl;
  final ImagePicker _picker = ImagePicker();
  final AvatarStorageService _avatarStorage = AvatarStorageService();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final data = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data != null && mounted) {
      setState(() {
        _nameController.text = data['full_name'] ?? '';
        _phoneController.text = data['phone_number']?.toString() ?? '';
        _ageController.text = data['age']?.toString() ?? '';
        _bioController.text = data['bio'] ?? '';
        _fitnessLevel = data['fitness_level'] ?? 'beginner';
        _experienceController.text = data['experience_count']?.toString() ?? '';
        _preferredDifficulty = data['preferred_difficulty'] as String?;
        _preferredDurationController.text =
            data['preferred_duration_h']?.toString() ?? '';
        _existingAvatarUrl = data['avatar_url'] as String?;
      });
    }

    final conditions = await Supabase.instance.client
        .from('profile_health_conditions')
        .select('condition')
        .eq('user_id', userId);

    if (mounted) {
      final values = List<Map<String, dynamic>>.from(conditions)
          .map((item) => item['condition']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
      _healthConditionsController.text = values.join(', ');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _preferredDurationController.dispose();
    _healthConditionsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка вибору фото: $e')),
        );
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Зробити фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Вибрати з галереї'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_selectedImage != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Видалити фото',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedImage = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      var avatarUrl = _existingAvatarUrl;
      if (_selectedImage != null) {
        try {
          avatarUrl = await _avatarStorage.uploadAvatar(
            userId: userId,
            imageFile: _selectedImage!,
          );
        } on AvatarUploadException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Аватар: ${e.message}')),
            );
          }
        }
      }

      final phone = _phoneController.text.trim();
      await Supabase.instance.client.from('profiles').upsert({
        'id': userId,
        'full_name': _nameController.text.trim(),
        'phone_number': phone.isEmpty ? null : phone,
        'age': int.tryParse(_ageController.text),
        'bio': _bioController.text.trim(),
        'fitness_level': _fitnessLevel,
        'experience_count': int.tryParse(_experienceController.text.trim()) ?? 0,
        'preferred_difficulty': _preferredDifficulty,
        'preferred_duration_h':
            double.tryParse(_preferredDurationController.text.trim()),
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final conditions = _healthConditionsController.text
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList();

      await Supabase.instance.client
          .from('profile_health_conditions')
          .delete()
          .eq('user_id', userId);

      if (conditions.isNotEmpty) {
        await Supabase.instance.client.from('profile_health_conditions').insert(
              conditions
                  .map(
                    (condition) => {
                      'user_id': userId,
                      'condition': condition,
                    },
                  )
                  .toList(),
            );
      }

      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профіль збережено')),
        );
        GoRouter.of(context).go('/profile');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = _nameController.text.trim();
    final initials = name.isNotEmpty
        ? name.split(' ').map((e) => e[0]).take(2).join()
        : (user?.email?[0].toUpperCase() ?? '?');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: const Text(
          'Редагування профілю',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              Stack(
                children: [
                  ProfileAvatar(
                    radius: 60,
                    initials: initials,
                    localImage: _selectedImage,
                    imageUrl: _selectedImage == null ? _existingAvatarUrl : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Material(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showImagePickerOptions,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Особиста інформація',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppTextFormField(
                      controller: _nameController,
                      validator: FormValidators.fullName,
                      decoration: _inputDecoration(
                        'Ім\'я та прізвище',
                        Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      validator: FormValidators.optionalPhone,
                      decoration: _inputDecoration(
                        'Номер телефону',
                        Icons.phone_outlined,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Видимість для інших — у Налаштування → Приватність',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      validator: (v) => FormValidators.age(v, requiredField: true),
                      decoration: _inputDecoration(
                        'Вік',
                        Icons.calendar_today,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _bioController,
                      maxLines: 4,
                      validator: FormValidators.bio,
                      decoration: _inputDecoration(
                        'Про себе',
                        Icons.description,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _experienceController,
                      keyboardType: TextInputType.number,
                      validator: (v) => FormValidators.optionalNonNegativeInt(
                        v,
                        field: 'Кількість походів',
                        max: 10000,
                      ),
                      decoration: _inputDecoration(
                        'Кількість попередніх походів',
                        Icons.hiking_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _preferredDurationController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => FormValidators.optionalDecimal(
                        v,
                        field: 'Тривалість',
                        min: 0,
                        max: 720,
                      ),
                      decoration: _inputDecoration(
                        'Бажана тривалість (год)',
                        Icons.timelapse_outlined,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppTextFormField(
                      controller: _healthConditionsController,
                      maxLines: 2,
                      validator: FormValidators.healthConditions,
                      decoration: _inputDecoration(
                        'Стан здоровʼя / хвороби (через кому)',
                        Icons.health_and_safety_outlined,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Рівень підготовки',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
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
                              child: Text('Досвідчений'),
                            ),
                            DropdownMenuItem(
                              value: 'advanced',
                              child: Text('Експерт'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _fitnessLevel = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Вподобана складність маршрутів',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _preferredDifficulty,
                          hint: const Text('Оберіть складність'),
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: 'easy',
                              child: Text('Легка'),
                            ),
                            DropdownMenuItem(
                              value: 'medium',
                              child: Text('Середня'),
                            ),
                            DropdownMenuItem(
                              value: 'hard',
                              child: Text('Складна'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _preferredDifficulty = v),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),

            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: _isSaving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF2E7D32).withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded),
                      SizedBox(width: 8),
                      Text(
                        'Зберегти зміни',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
