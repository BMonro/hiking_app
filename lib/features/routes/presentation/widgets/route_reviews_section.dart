import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/validation/form_validators.dart';
import '../../../profile/presentation/widgets/profile_avatar.dart';
import '../../../profile/presentation/widgets/user_profile_preview_sheet.dart';
import '../../domain/route_rating.dart';
import '../routes_provider.dart';

class RouteReviewsPreviewTile extends ConsumerWidget {
  final String routeId;
  final String authorId;

  const RouteReviewsPreviewTile({
    super.key,
    required this.routeId,
    required this.authorId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(routeReviewsProvider(routeId));

    return reviewsAsync.when(
      loading: () => const _PreviewShell(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (e, _) => _PreviewShell(
        onTap: () => openRouteReviewsSheet(
          context,
          ref,
          routeId: routeId,
          authorId: authorId,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.grey[600]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Відгуки — натисніть, щоб повторити',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[500]),
          ],
        ),
      ),
      data: (summary) => _PreviewShell(
        onTap: () => openRouteReviewsSheet(
          context,
          ref,
          routeId: routeId,
          authorId: authorId,
        ),
        child: Row(
          children: [
            if (summary.count > 0) ...[
              StarRatingDisplay(rating: summary.averageRating ?? 0, size: 20),
              const SizedBox(width: 10),
              Text(
                summary.averageLabel,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(width: 10),
            ] else
              Icon(Icons.star_outline, color: Colors.grey[500], size: 28),
            Expanded(
              child: Text(
                summary.count == 0
                    ? 'Ще без відгуків — відкрити'
                    : RouteReviewsSummary.reviewsCountLabel(summary.count),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }
}

class _PreviewShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PreviewShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: child,
        ),
      ),
    );
  }
}

Future<void> openRouteReviewsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String routeId,
  required String authorId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollController) => _RouteReviewsSheet(
        scrollController: scrollController,
        routeId: routeId,
        authorId: authorId,
      ),
    ),
  );
}

class _RouteReviewsSheet extends ConsumerWidget {
  final ScrollController scrollController;
  final String routeId;
  final String authorId;

  const _RouteReviewsSheet({
    required this.scrollController,
    required this.routeId,
    required this.authorId,
  });

  bool get _isAuthor {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    return uid != null && authorId == uid;
  }

  void _openComposer(BuildContext context, WidgetRef ref, RouteReview? existing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: _ReviewComposerPanel(
                routeId: routeId,
                existing: existing,
                onDone: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(routeReviewsProvider(routeId));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Рейтинг та відгуки',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: reviewsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Помилка: $e', textAlign: TextAlign.center),
                ),
              ),
              data: (summary) {
                final myReview = summary.myReview;
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          RatingSummaryHeader(summary: summary),
                          const SizedBox(height: 16),
                          if (summary.reviews.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Ще немає відгуків.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            )
                          else
                            ...summary.reviews.map(
                              (r) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: ReviewCard(review: r),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!_isAuthor)
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _openComposer(
                                context,
                                ref,
                                myReview,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              icon: Icon(
                                myReview != null
                                    ? Icons.edit_outlined
                                    : Icons.rate_review_outlined,
                              ),
                              label: Text(
                                myReview != null
                                    ? 'Редагувати мій відгук'
                                    : 'Залишити відгук',
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Автор маршруту не може залишати відгук.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RatingSummaryHeader extends StatelessWidget {
  final RouteReviewsSummary summary;

  const RatingSummaryHeader({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final avg = summary.averageRating;
    final count = summary.count;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                summary.averageLabel,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2E7D32),
                ),
              ),
              StarRatingDisplay(rating: avg ?? 0, size: 22),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              count == 0
                  ? 'Ще без оцінок'
                  : RouteReviewsSummary.reviewsCountLabel(count),
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[800],
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewCard extends ConsumerWidget {
  final RouteReview review;

  const ReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = review.createdAt;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    final comment = review.comment ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => showUserProfilePreview(
                  context,
                  ref,
                  userId: review.userId,
                ),
                child: ProfileAvatar(
                  radius: 18,
                  imageUrl: review.authorAvatarUrl,
                  initials: profileInitials(review.authorName),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => showUserProfilePreview(
                        context,
                        ref,
                        userId: review.userId,
                      ),
                      child: Text(
                        review.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        StarRatingDisplay(
                          rating: review.rating.toDouble(),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              comment,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewComposerPanel extends ConsumerStatefulWidget {
  final String routeId;
  final RouteReview? existing;
  final VoidCallback onDone;

  const _ReviewComposerPanel({
    required this.routeId,
    this.existing,
    required this.onDone,
  });

  @override
  ConsumerState<_ReviewComposerPanel> createState() =>
      _ReviewComposerPanelState();
}

class _ReviewComposerPanelState extends ConsumerState<_ReviewComposerPanel> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  int _rating = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _rating = existing.rating;
      _commentController.text = existing.comment ?? '';
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Оберіть оцінку від 1 до 5 зірок')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await ref.read(routeRatingsRepositoryProvider).submitReview(
            routeId: widget.routeId,
            rating: _rating,
            comment: _commentController.text,
          );
      ref
        ..invalidate(routeReviewsProvider(widget.routeId))
        ..invalidate(displayedRoutesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing != null
                  ? 'Відгук оновлено'
                  : 'Дякуємо за відгук!',
            ),
          ),
        );
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Помилка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            widget.existing != null ? 'Редагувати відгук' : 'Новий відгук',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text(
            'Оцінка',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          StarRatingInput(
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _commentController,
            maxLines: 4,
            maxLength: 1000,
            autofocus: true,
            validator: FormValidators.reviewComment,
            decoration: InputDecoration(
              hintText: 'Коментар (необовʼязково)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : widget.onDone,
                  child: const Text('Скасувати'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.existing != null ? 'Зберегти' : 'Надіслати',
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StarRatingInput extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final star = index + 1;
        final filled = star <= value;
        return IconButton(
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(minWidth: size + 4, minHeight: size + 4),
          onPressed: () => onChanged(star),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            color: filled ? const Color(0xFFFFB300) : Colors.grey[400],
            size: size,
          ),
        );
      }),
    );
  }
}

class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final double size;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final IconData icon;
        if (rating >= starIndex) {
          icon = Icons.star_rounded;
        } else if (rating >= starIndex - 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(
          icon,
          size: size,
          color: const Color(0xFFFFB300),
        );
      }),
    );
  }
}
