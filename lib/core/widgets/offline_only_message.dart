import 'package:flutter/material.dart';

/// Повідомлення, коли функція недоступна без інтернету.
class OfflineOnlyMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const OfflineOnlyMessage({
    super.key,
    this.icon = Icons.cloud_off,
    this.title = 'Недоступно офлайн',
    this.subtitle =
        'Ця функція потребує інтернету. Підключіть мережу або вимкніть офлайн-навігацію.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showWeatherOfflineSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Погода недоступна без інтернету'),
      duration: Duration(seconds: 3),
    ),
  );
}
