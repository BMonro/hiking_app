import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/validation/form_validators.dart';
import '../../../core/widgets/app_text_form_field.dart';
import '../domain/hike_qualification.dart';
import '../domain/hike_session_summary.dart';

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
  final formKey = GlobalKey<FormState>();

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
          child: Form(
            key: formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Запис у журнал',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              AppTextFormField(
                controller: titleController,
                validator: FormValidators.title,
                decoration: _decoration('Назва походу *'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextFormField(
                      controller: distanceController,
                      keyboardType: TextInputType.number,
                      validator: FormValidators.journalDistance,
                      decoration: _decoration('Відстань (км)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextFormField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      validator: FormValidators.journalDuration,
                      decoration: _decoration('Тривалість (год)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: ascentController,
                keyboardType: TextInputType.number,
                validator: FormValidators.journalAscent,
                decoration: _decoration('Перепад висот (м)'),
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: notesController,
                maxLines: 3,
                validator: FormValidators.notes,
                decoration: _decoration('Нотатки'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final distanceKm =
                      double.tryParse(distanceController.text) ?? 0;
                  final durationHours =
                      double.tryParse(durationController.text) ?? 0;
                  if (!HikeQualification.qualifies(
                    distanceKm: distanceKm,
                    durationHours: durationHours,
                    reachedFinish: summary.reachedFinish,
                  )) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Занадто мало для походу: '
                          '${HikeQualification.requirementHint}.',
                        ),
                      ),
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
