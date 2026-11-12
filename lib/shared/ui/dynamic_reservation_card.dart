import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dynamic_post.dart';
import '../../features/dynamic/application/dynamic_content_state.dart';
import '../../features/dynamic/application/dynamic_reservation_controller.dart';
import 'app_notice.dart';
import 'dynamic_content_card.dart';

class DynamicReservationCard extends ConsumerWidget {
  const DynamicReservationCard({
    super.key,
    required this.post,
    required this.card,
    required this.onLogin,
    this.onOpenLink,
  });
  final DynamicPost post;
  final DynamicContentCard card;
  final VoidCallback onLogin;
  final ValueChanged<Uri>? onOpenLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = card.reservation;
    if (seed == null) {
      return DynamicContentCardView(card: card, onOpenLink: onOpenLink);
    }
    final provider = dynamicReservationProvider(seed.id);
    final state = ref.watch(provider);
    final reservation = seed.withCachedState(
      ref.watch(
        dynamicContentProvider.select(
          (content) => content.reservations[seed.id],
        ),
      ),
    );
    final jump = reservation.hasJump;
    return DynamicContentCardView(
      card: card,
      reservation: reservation,
      onOpenLink: onOpenLink,
      handleAction: !jump,
      actionLabel: jump || reservation.ended
          ? null
          : state.uncertain
          ? '刷新预约状态'
          : reservation.label,
      onAction:
          state.busy ||
              post.unavailable ||
              (!state.uncertain && !reservation.canToggle)
          ? null
          : () async {
              if (!state.uncertain && !state.signedIn) {
                onLogin();
                return;
              }
              final controller = ref.read(provider.notifier);
              if (state.uncertain) {
                await controller.refresh(post.id, reservation);
              } else {
                await controller.toggle(post.id, reservation);
              }
              if (!context.mounted) return;
              final message = ref.read(provider).message;
              if (message != null) showAppNotice(context, message);
            },
    );
  }
}
