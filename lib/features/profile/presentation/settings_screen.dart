import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkTheme = false;
  bool _weatherAlerts = true;
  bool _newAchievements = true;
  bool _recommendations = false;
  bool _autoSOS = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Налаштування'),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            const SizedBox(height: 8),
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
              title: 'Сповіщення',
              children: [
                _SettingsToggleTile(
                  title: 'Попередження про погоду',
                  icon: Icons.cloud_outlined,
                  value: _weatherAlerts,
                  onChanged: (value) => setState(() => _weatherAlerts = value),
                ),
                _SettingsToggleTile(
                  title: 'Нові досягнення',
                  icon: Icons.emoji_events_outlined,
                  value: _newAchievements,
                  onChanged: (value) =>
                      setState(() => _newAchievements = value),
                ),
                _SettingsToggleTile(
                  title: 'Рекомендації ШІ',
                  icon: Icons.smart_toy_outlined,
                  value: _recommendations,
                  onChanged: (value) =>
                      setState(() => _recommendations = value),
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
                  title: 'Профіль акаунту',
                  icon: Icons.person_outline,
                  onTap: () {},
                ),
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
              onPressed: () {},
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
