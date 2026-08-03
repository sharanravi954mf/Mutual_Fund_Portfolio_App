import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../../orders/data/qualification_queue_repository.dart';
import '../../../orders/data/supabase_qualification_queue_repository.dart';
import '../../../orders/domain/order_models.dart';
import '../../../orders/domain/qualification_queue_models.dart';
import '../../../orders/presentation/qualification_queue_controller.dart';
import '../../models/user_profile.dart';

class MfdQueueScreen extends StatefulWidget {
  const MfdQueueScreen({
    super.key,
    this.repository,
    this.debounceDuration = const Duration(milliseconds: 350),
    this.periodicTimerFactory,
    this.oneShotTimerFactory,
  });

  final QualificationQueueRepository? repository;
  final Duration debounceDuration;
  final PeriodicTimerFactory? periodicTimerFactory;
  final OneShotTimerFactory? oneShotTimerFactory;

  @override
  State<MfdQueueScreen> createState() => _MfdQueueScreenState();
}

class MfdQueueCountBadge extends StatefulWidget {
  const MfdQueueCountBadge({super.key, this.repository});

  final QualificationQueueRepository? repository;

  @override
  State<MfdQueueCountBadge> createState() => _MfdQueueCountBadgeState();
}

class _MfdQueueCountBadgeState extends State<MfdQueueCountBadge> {
  late final QualificationQueueRepository _repository;
  Future<QualificationQueueSnapshot>? _snapshot;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ??
        SupabaseQualificationQueueRepository.fromDefaultClient();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = context.read<AuthProvider>().userProfile;
    if (_isAuthorisedMfdProfile(profile) && _snapshot == null) {
      _snapshot = _repository.fetchQueue(reviewerProfileId: profile!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().userProfile;
    if (!_isAuthorisedMfdProfile(profile)) return const SizedBox.shrink();

    return FutureBuilder<QualificationQueueSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.items.isEmpty) {
          return const SizedBox.shrink();
        }
        final count = snapshot.data!.items.length;
        return Container(
          constraints: const BoxConstraints(minWidth: 24, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        );
      },
    );
  }
}

class _MfdQueueScreenState extends State<MfdQueueScreen> {
  QualificationQueueController? _controller;
  String? _controllerProfileId;
  bool? _controllerAuthorized;
  final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: 'Rs ',
    decimalDigits: 2,
  );
  final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureController();
  }

  @override
  void didUpdateWidget(covariant MfdQueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.debounceDuration != widget.debounceDuration) {
      _disposeController();
      _ensureController();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _ensureController() {
    final profile = context.read<AuthProvider>().userProfile;
    final isAuthorized = _isAuthorisedMfdProfile(profile);
    if (_controller != null &&
        _controllerProfileId == profile?.id &&
        _controllerAuthorized == isAuthorized) {
      return;
    }

    _disposeController();
    final controller = QualificationQueueController(
      repository: widget.repository ??
          SupabaseQualificationQueueRepository.fromDefaultClient(),
      reviewerProfileId: profile?.id,
      isAuthorizedReviewer: isAuthorized,
      debounceDuration: widget.debounceDuration,
      periodicTimerFactory: widget.periodicTimerFactory,
      oneShotTimerFactory: widget.oneShotTimerFactory,
    );
    controller.addListener(_onControllerChanged);
    _controller = controller;
    _controllerProfileId = profile?.id;
    _controllerAuthorized = isAuthorized;
    unawaited(controller.start());
  }

  void _disposeController() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _controller = null;
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final profileId = context.watch<AuthProvider>().userProfile?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MFD qualification queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh queue',
            icon: const Icon(Icons.refresh),
            onPressed: controller.isRefreshing ? null : controller.refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _QueueHeader(
              count: controller.items.length,
              fetchedAt: controller.fetchedAt,
              phase: controller.phase,
              colors: colors,
            ),
            if (controller.isRefreshing)
              LinearProgressIndicator(color: colors.primary),
            if (controller.message != null)
              _InlineBanner(
                icon: Icons.check_circle_outline,
                message: controller.message!,
                color: colors.success,
              ),
            if (controller.errorMessage != null)
              _InlineBanner(
                icon: Icons.error_outline,
                message: controller.errorMessage!,
                color: colors.error,
              ),
            Expanded(
              child: _buildBody(controller, colors, profileId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    QualificationQueueController controller,
    AppThemeColors colors,
    String? profileId,
  ) {
    switch (controller.phase) {
      case QualificationQueuePhase.initial:
      case QualificationQueuePhase.loading:
        return const _QueueMessage(
          icon: Icons.hourglass_empty,
          message: 'Loading qualification queue',
          showSpinner: true,
        );
      case QualificationQueuePhase.accessDenied:
        return const _QueueMessage(
          icon: Icons.lock_outline,
          message: 'This queue is available only to authorised MFD users.',
        );
      case QualificationQueuePhase.offline:
        return _QueueMessage(
          icon: Icons.wifi_off_outlined,
          message: 'The qualification queue is offline.',
          actionLabel: 'Retry',
          onAction: controller.refresh,
        );
      case QualificationQueuePhase.failure:
        return _QueueMessage(
          icon: Icons.error_outline,
          message: 'The qualification queue is unavailable.',
          actionLabel: 'Retry',
          onAction: controller.refresh,
        );
      case QualificationQueuePhase.empty:
        return _QueueMessage(
          icon: Icons.inbox_outlined,
          message: 'No orders awaiting qualification.',
          actionLabel: 'Refresh',
          onAction: controller.refresh,
        );
      case QualificationQueuePhase.refreshing:
      case QualificationQueuePhase.ready:
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: controller.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = controller.items[index];
                  return _QualificationOrderCard(
                    item: item,
                    compact: compact,
                    currentProfileId: profileId,
                    colors: colors,
                    currency: _currency,
                    dateFormat: _dateFormat,
                    actionDecision: controller.activeActionOrderId == item.id
                        ? controller.activeActionDecision
                        : null,
                    onApprove: () => controller.approve(item),
                    onReject: () =>
                        _showRejectDialog(context, controller, item),
                  );
                },
              );
            },
          ),
        );
    }
  }

  Future<void> _showRejectDialog(
    BuildContext context,
    QualificationQueueController controller,
    QualificationQueueItem item,
  ) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject order'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Optional rejection note',
          ),
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.done,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.block),
            label: const Text('Reject'),
            onPressed: () => Navigator.of(context).pop(reasonController.text),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      reasonController.dispose();
    });
    if (reason == null || !mounted) return;
    await controller.reject(item, reason);
  }
}

bool _isAuthorisedMfdProfile(UserProfile? profile) {
  if (profile == null || !profile.isActive) return false;
  return profile.role == UserRole.advisor || profile.role == UserRole.admin;
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.count,
    required this.fetchedAt,
    required this.phase,
    required this.colors,
  });

  final int count;
  final DateTime? fetchedAt;
  final QualificationQueuePhase phase;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final status = fetchedAt == null
        ? 'Awaiting first refresh'
        : 'Last refreshed ${DateFormat('hh:mm:ss a').format(fetchedAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            'Orders awaiting qualification',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
          ),
          Chip(
            avatar: const Icon(Icons.assignment_turned_in_outlined, size: 18),
            label: Text('$count pending'),
          ),
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _QualificationOrderCard extends StatelessWidget {
  const _QualificationOrderCard({
    required this.item,
    required this.compact,
    required this.currentProfileId,
    required this.colors,
    required this.currency,
    required this.dateFormat,
    required this.actionDecision,
    required this.onApprove,
    required this.onReject,
  });

  final QualificationQueueItem item;
  final bool compact;
  final String? currentProfileId;
  final AppThemeColors colors;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final QualificationDecision? actionDecision;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final isBusy = actionDecision != null;
    final sameInitiator = item.isSameInitiator(currentProfileId);
    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          icon: isBusy && actionDecision == QualificationDecision.rejected
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.block),
          label: const Text('Reject'),
          onPressed: isBusy ? null : onReject,
        ),
        FilledButton.icon(
          icon: isBusy && actionDecision == QualificationDecision.approved
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Approve'),
          onPressed: isBusy ? null : onApprove,
        ),
      ],
    );

    final details = [
      _DetailLine(
        icon: Icons.person_outline,
        label: 'Investor',
        value: item.investorName,
      ),
      _DetailLine(
        icon: Icons.alternate_email,
        label: 'Masked email',
        value: item.maskedEmail,
      ),
      _DetailLine(
        icon: Icons.phone_outlined,
        label: 'Masked phone',
        value: item.maskedPhone,
      ),
      _DetailLine(
        icon: Icons.account_circle_outlined,
        label: 'Initiator',
        value: item.initiatorName,
      ),
      _DetailLine(
        icon: Icons.badge_outlined,
        label: 'Role and channel',
        value:
            '${_label(item.initiatedByRole)} / ${_label(item.initiationChannel)}',
      ),
      _DetailLine(
        icon: Icons.timeline_outlined,
        label: 'Status',
        value: _label(item.status.databaseValue),
      ),
      _DetailLine(
        icon: Icons.swap_horiz,
        label: 'Order type',
        value: item.orderTypeLabel,
      ),
      _DetailLine(
        icon: Icons.account_balance_outlined,
        label: 'Scheme',
        value: item.schemeDisplay,
      ),
      if (item.type == OrderType.switchOrder)
        _DetailLine(
          icon: Icons.call_split_outlined,
          label: 'Destination',
          value: item.destinationSchemeDisplay,
        ),
      _DetailLine(
        icon: Icons.payments_outlined,
        label: 'Amount / units',
        value: _amountUnitsLabel(item),
      ),
      _DetailLine(
        icon: Icons.schedule,
        label: 'Created',
        value: dateFormat.format(item.createdAt),
      ),
    ];

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Order ${_shortId(item.id)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                ),
                if (sameInitiator)
                  const Chip(
                    avatar: Icon(Icons.info_outline, size: 18),
                    label: Text('Initiated by you'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (compact) ...[
              ...details,
              const SizedBox(height: 12),
              actionButtons,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 10,
                      children: details
                          .map((detail) => SizedBox(width: 260, child: detail))
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 188),
                    child: actionButtons,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _amountUnitsLabel(QualificationQueueItem item) {
    final amount = item.amount == null ? null : currency.format(item.amount);
    final units =
        item.units == null ? null : '${item.units!.toStringAsFixed(4)} units';
    return [
      if (amount != null) amount,
      if (units != null) units,
    ].join(' / ');
  }

  static String _label(String value) =>
      value.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'^.'), (match) => match.group(0)!.toUpperCase());

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(value, overflow: TextOverflow.visible),
              ],
            ),
          ),
        ],
      );
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      );
}

class _QueueMessage extends StatelessWidget {
  const _QueueMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.showSpinner = false,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const CircularProgressIndicator()
              else
                Icon(icon, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onAction != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(actionLabel!),
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      );
}
