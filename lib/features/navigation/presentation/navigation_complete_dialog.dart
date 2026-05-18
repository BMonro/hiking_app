import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/hike_session_summary.dart';

/// Діалог завершення походу та форма збереження в журнал.
Future<void> showHikeCompletionFlow(
  BuildContext context,
  HikeSessionSummary summary,
) async {
  final distanceStr = summary.distanceKm.toStringAsFixed(2);
  final hours = summary.durationHours.floor();
  final minutes = ((summary.durationHours - hours) * 60).round();

  final save = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        summary.reachedFinish ? Icons.flag_circle : Icons.hiking,
        color: const Color(0xFF2E7D32),
        size: 40,
      ),
      title: Text(
        summary.reachedFinish ? 'Маршрут пройдено!' : 'Навігацію завершено',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            icon: Icons.straighten,
            label: 'Відстань',
            value: '$distanceStr км',
          ),
          const SizedBox(height: 6),
          _SummaryRow(
            icon: Icons.schedule,
            label: 'Час',
            value: hours > 0 ? '$hours год $minutes хв' : '$minutes хв',
          ),
          if (summary.suggestedAscentM != null && summary.suggestedAscentM! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _SummaryRow(
                icon: Icons.terrain,
                label: 'Набір висоти (орієнт.)',
                value: '${summary.suggestedAscentM} м',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Зберегти похід у журналі?',
            style: TextStyle(color: Colors.grey[700], fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Пізніше'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
          ),
          child: const Text('Зберегти в журнал'),
        ),
      ],
    ),
  );

  if (save != true || !context.mounted) return;
  await _showJournalSaveSheet(context, summary);
}

Future<void> _showJournalSaveSheet(
  BuildContext context,
  HikeSessionSummary summary,
) async {
  final titleController = TextEditingController(text: summary.title);
  final distanceController = TextEditingController(
    text: summary.distanceKm.toStringAsFixed(2),
  );
  final durationController = TextEditingController(
    text: summary.durationHours.toStringAsFixed(1),
  );
  final ascentController = TextEditingController(
    text: summary.suggestedAscentM?.toString() ?? '',
  );
  final notesController = TextEditingController(
    text: summary.reachedFinish
        ? 'Завершено навігацією маршруту.'
        : 'Завершено навігацію достроково.',
  );

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Запис у журнал',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: _decoration('Назва походу *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: distanceController,
                      keyboardType: TextInputType.number,
                      decoration: _decoration('Відстань (км)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: _decoration('Тривалість (год)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ascentController,
                keyboardType: TextInputType.number,
                decoration: _decoration('Перепад висот (м)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: _decoration('Нотатки'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Введіть назву')),
                    );
                    return;
                  }
                  try {
                    final userId =
                        Supabase.instance.client.auth.currentUser!.id;
                    final payload = <String, dynamic>{
                      'user_id': userId,
                      'title': titleController.text.trim(),
                      'date': DateTime.now().toIso8601String().split('T')[0],
                      'notes': notesController.text.trim(),
                      'actual_distance_km':
                          double.tryParse(distanceController.text),
                      'actual_duration_h':
                          double.tryParse(durationController.text),
                      'actual_ascent_m': int.tryParse(ascentController.text),
                    };
                    if (summary.routeId != null) {
                      payload['route_id'] = summary.routeId;
                    }
                    await Supabase.instance.client
                        .from('journal_entries')
                        .insert(payload);

                    try {
                      final granted = await Supabase.instance.client
                          .rpc<int>('sync_my_achievements');
                      if (ctx.mounted && granted > 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Нове досягнення: +$granted',
                            ),
                          ),
                        );
                      }
                    } catch (_) {}

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Похід збережено в журнал'),
                        ),
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
                child: const Text('Зберегти запис'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (context.mounted) context.push('/journal');
                },
                child: const Text('Перейти до журналу'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    titleController.dispose();
    distanceController.dispose();
    durationController.dispose();
    ascentController.dispose();
    notesController.dispose();
  }
}

InputDecoration _decoration(String label) {
  return InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[700])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
