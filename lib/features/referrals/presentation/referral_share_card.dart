import 'dart:async';

import 'package:flutter/material.dart';

import '../../../providers/theme_provider.dart';
import '../application/referral_share_controller.dart';

class ReferralShareCard extends StatefulWidget {
  const ReferralShareCard({
    super.key,
    required this.controller,
    required this.colors,
  });

  final ReferralShareController controller;
  final AppThemeColors colors;

  @override
  State<ReferralShareCard> createState() => _ReferralShareCardState();
}

class _ReferralShareCardState extends State<ReferralShareCard> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.state == ReferralLoadState.idle) {
      unawaited(widget.controller.load());
    }
  }

  @override
  void didUpdateWidget(covariant ReferralShareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      if (widget.controller.state == ReferralLoadState.idle) {
        unawaited(widget.controller.load());
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Semantics(
      container: true,
      label: 'Invite friends to Money Bowl',
      child: Container(
        key: const Key('referral-share-card'),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.card_giftcard_rounded,
                    color: colors.success,
                    semanticLabel: 'Referral reward',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Invite friends',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share Money Bowl securely. Eligible successful '
                        'referrals receive a 30-day Premium reward.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildAction(context),
            if (widget.controller.errorMessage case final message?) ...[
              const SizedBox(height: 10),
              Text(
                message,
                key: const Key('referral-error-message'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    switch (widget.controller.state) {
      case ReferralLoadState.idle:
      case ReferralLoadState.loading:
        return const SizedBox(
          key: Key('referral-loading'),
          height: 48,
          child: Center(child: CircularProgressIndicator()),
        );
      case ReferralLoadState.failure:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            key: const Key('referral-retry-button'),
            onPressed: widget.controller.load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        );
      case ReferralLoadState.ready:
        return SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            key: const Key('referral-whatsapp-button'),
            onPressed: widget.controller.isSharing
                ? null
                : widget.controller.shareOnWhatsApp,
            icon: widget.controller.isSharing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_rounded),
            label: Text(
              widget.controller.isSharing
                  ? 'Opening WhatsApp…'
                  : 'Share on WhatsApp',
            ),
          ),
        );
    }
  }
}
