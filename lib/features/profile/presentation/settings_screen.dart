import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/notifications/notification_preferences_provider.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _scrollController = ScrollController();
  final _notificationsSectionKey = GlobalKey();

  bool _darkTheme = false;
  bool _autoSOS = true;
  bool _publicProfile = true;
  bool _showEmail = false;
  bool _showPhone = false;
  bool _privacyLoading = true;
  bool _privacySaving = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _privacyLoading = false);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('phone_visible')
          .eq('id', userId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _showPhone = data?['phone_visible'] as bool? ?? false;
          _privacyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _privacyLoading = false);
    }
  }

  Future<void> _savePrivacySettings() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _privacySaving = true);
    try {
      await Supabase.instance.client.from('profiles').update({
        'phone_visible': _showPhone,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      ref.invalidate(profileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Налаштування приватності збережено'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка збереження: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _privacySaving = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToNotifications() {
    final ctx = _notificationsSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Future<void> _showChangePasswordDialog() async {
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final messenger = ScaffoldMessenger.of(context);
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Змінити пароль'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: newController,
                      obscureText: true,
                      enableInteractiveSelection: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Новий пароль',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Введіть пароль';
                        if (v.length < 6) return 'Мінімум 6 символів';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmController,
                      obscureText: true,
                      enableInteractiveSelection: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Підтвердіть пароль',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) {
                        if (v != newController.text) {
                          return 'Паролі не співпадають';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Скасувати'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => saving = true);
                          try {
                            await Supabase.instance.client.auth.updateUser(
                              UserAttributes(
                                password: newController.text.trim(),
                              ),
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Пароль оновлено'),
                                ),
                              );
                            }
                          } on AuthException catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(e.message)),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Помилка: $e')),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Зберегти'),
                ),
              ],
            );
          },
        );
      },
    );

    newController.dispose();
    confirmController.dispose();
  }

  void _showPrivacySheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Приватність',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Керуйте видимістю профілю для інших користувачів.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Публічний профіль'),
                    subtitle: const Text(
                      'Інші бачать ваше імʼя та статистику в походах',
                    ),
                    value: _publicProfile,
                    onChanged: (v) {
                      setSheetState(() => _publicProfile = v);
                      setState(() => _publicProfile = v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Показувати email'),
                    subtitle: const Text('Лише організаторам групових походів'),
                    value: _showEmail,
                    onChanged: (v) {
                      setSheetState(() => _showEmail = v);
                      setState(() => _showEmail = v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Показувати номер телефону'),
                    subtitle: const Text(
                      'Інші користувачі бачать телефон у прев’ю профілю',
                    ),
                    value: _showPhone,
                    onChanged: _privacyLoading
                        ? null
                        : (v) {
                            setSheetState(() => _showPhone = v);
                            setState(() => _showPhone = v);
                          },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _privacySaving
                        ? null
                        : () async {
                            await _savePrivacySettings();
                            if (context.mounted) Navigator.pop(context);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _privacySaving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Готово'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вийти з акаунту?'),
        content: const Text('Вам потрібно буде увійти знову.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Вийти'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.toolbarBackground,
        surfaceTintColor: Colors.transparent,
        title: const Text('Налаштування'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            const SizedBox(height: 8),
            _SettingsSection(
              title: 'Акаунт',
              children: [
                _SettingsTile(
                  title: 'Змінити пароль',
                  icon: Icons.lock_outline,
                  onTap: _showChangePasswordDialog,
                ),
                _SettingsTile(
                  title: 'Приватність',
                  icon: Icons.privacy_tip_outlined,
                  onTap: _showPrivacySheet,
                ),
                _SettingsTile(
                  title: 'Повідомлення',
                  description: 'Прокрутити до розділу сповіщень',
                  icon: Icons.notifications_outlined,
                  onTap: _scrollToNotifications,
                ),
                _SettingsTile(
                  title: 'Редагувати профіль',
                  icon: Icons.person_outline,
                  onTap: () => context.push('/edit-profile'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Загальне',
              children: [
                _SettingsTile(
                  title: 'Мова',
                  description: 'Українська',
                  icon: Icons.language,
                  onTap: () {},
                ),
                _SettingsToggleTile(
                  title: 'Темна тема',
                  icon: Icons.dark_mode,
                  value: _darkTheme,
                  onChanged: (value) => setState(() => _darkTheme = value),
                ),
                _SettingsTile(
                  title: 'Одиниці',
                  description: 'Метричні',
                  icon: Icons.straighten,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              key: _notificationsSectionKey,
              title: 'Сповіщення',
              children: [
                _SettingsTile(
                  title: 'Усі сповіщення',
                  description: 'Історія та непрочитані',
                  icon: Icons.inbox_outlined,
                  onTap: () => context.push('/notifications'),
                ),
                _SettingsToggleTile(
                  title: 'Нові досягнення',
                  icon: Icons.emoji_events_outlined,
                  value: ref.watch(notificationPreferencesProvider).newAchievements,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setNewAchievements(v),
                ),
                _SettingsToggleTile(
                  title: 'Заявки на похід',
                  icon: Icons.person_add_alt_1_outlined,
                  value: ref.watch(notificationPreferencesProvider).tripRequests,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setTripRequests(v),
                ),
                _SettingsToggleTile(
                  title: 'Схвалення / відхилення',
                  icon: Icons.how_to_reg_outlined,
                  value: ref.watch(notificationPreferencesProvider).tripDecisions,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setTripDecisions(v),
                ),
                _SettingsToggleTile(
                  title: 'Повідомлення в чаті походу',
                  icon: Icons.chat_bubble_outline,
                  value: ref.watch(notificationPreferencesProvider).tripChatMessages,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setTripChatMessages(v),
                ),
                _SettingsToggleTile(
                  title: 'Попередження про погоду',
                  icon: Icons.cloud_outlined,
                  value: ref.watch(notificationPreferencesProvider).weatherAlerts,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setWeatherAlerts(v),
                ),
                _SettingsToggleTile(
                  title: 'Рекомендації ШІ',
                  icon: Icons.smart_toy_outlined,
                  value: ref.watch(notificationPreferencesProvider).aiRecommendations,
                  onChanged: (v) =>
                      ref.read(notificationPreferencesProvider.notifier).setAiRecommendations(v),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Безпека',
              children: [
                _SettingsTile(
                  title: 'Екстрений контакт',
                  description: 'Марія К.',
                  icon: Icons.contact_phone_outlined,
                  onTap: () {},
                ),
                _SettingsToggleTile(
                  title: 'Автоматичний SOS',
                  icon: Icons.phone_android_outlined,
                  value: _autoSOS,
                  onChanged: (value) => setState(() => _autoSOS = value),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SettingsSection(
              title: 'Підтримка',
              children: [
                _SettingsTile(
                  title: 'Допомога та FAQ',
                  icon: Icons.help_outline,
                  onTap: () {},
                ),
                _SettingsTile(
                  title: 'Про додаток',
                  icon: Icons.info_outline,
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Вийти з акаунту'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.title,
    this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: Colors.grey.withOpacity(0.08),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.grey.shade700, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        secondary: Icon(icon, color: Colors.grey.shade700),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
