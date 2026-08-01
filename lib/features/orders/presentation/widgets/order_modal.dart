import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';
import '../../data/order_repository.dart';
import '../../domain/masking.dart';
import '../../domain/order_models.dart';
import '../order_bloc.dart';
import '../order_state.dart';
import '../../../investor_identity/models/user_profile.dart';

class OrderModal extends StatefulWidget {
  final OrderRepository repository;
  final String? preSelectedClientId;
  final String? preSelectedClientName;
  final String? preSelectedWorkspaceId;

  const OrderModal({
    super.key,
    required this.repository,
    this.preSelectedClientId,
    this.preSelectedClientName,
    this.preSelectedWorkspaceId,
  });

  static void show(
    BuildContext context, {
    required OrderRepository repository,
    String? preSelectedClientId,
    String? preSelectedClientName,
    String? preSelectedWorkspaceId,
  }) {
    final showSidebar = MediaQuery.of(context).size.width > 900;
    if (showSidebar) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 850),
            child: OrderModal(
              repository: repository,
              preSelectedClientId: preSelectedClientId,
              preSelectedClientName: preSelectedClientName,
              preSelectedWorkspaceId: preSelectedWorkspaceId,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: OrderModal(
              repository: repository,
              preSelectedClientId: preSelectedClientId,
              preSelectedClientName: preSelectedClientName,
              preSelectedWorkspaceId: preSelectedWorkspaceId,
            ),
          ),
        ),
      );
    }
  }

  @override
  State<OrderModal> createState() => _OrderModalState();
}

class _OrderModalState extends State<OrderModal> {
  late final OrderBloc _bloc;
  final _amountController = TextEditingController();
  final _unitsController = TextEditingController();
  final _currencyFormat =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  bool _isAmountMode = true;
  bool _hasConfirmedReview = false;
  bool _hasInitialRefLoadCalled = false;

  @override
  void initState() {
    super.initState();
    _bloc = OrderBloc(widget.repository);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialRefLoadCalled) {
      _hasInitialRefLoadCalled = true;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final profileId = auth.userProfile?.id ?? '';
      final userRole = auth.userProfile?.role;

      if (userRole == UserRole.advisor || userRole == UserRole.admin) {
        final role = userRole == UserRole.admin ? 'admin' : 'advisor';
        _bloc.initiateForAdvisor(
          advisorProfileId: profileId,
          preSelectedInvestorId: widget.preSelectedClientId,
          selectedWorkspaceId: widget.preSelectedWorkspaceId,
          initiatorProfileId: profileId,
          initiationRole: role,
          initiationChannel: 'advisor_portal',
        );
      } else if (userRole == UserRole.investor || userRole == UserRole.client) {
        _bloc.initiateForInvestor(
          investorProfileId: profileId,
          initiatorProfileId: profileId,
          initiationRole: 'investor',
          initiationChannel: 'investor_portal',
        );
      } else {
        _bloc.setAccessDenied("Access Denied: Unsupported role for order initiation.");
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _unitsController.dispose();
    _bloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode(context);
    final colors = AppThemeColors(isDark);
    final auth = Provider.of<AuthProvider>(context);
    final isAdvisor = auth.userProfile?.role == UserRole.advisor || auth.userProfile?.role == UserRole.admin;

    return ChangeNotifierProvider<OrderBloc>.value(
      value: _bloc,
      child: Consumer<OrderBloc>(
        builder: (context, bloc, child) {
          final state = bloc.state;

          if (state.phase == OrderPhase.loadingReferenceData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (state.phase == OrderPhase.submitted) {
            return _buildSuccessState(context, state, colors);
          }

          if (state.phase == OrderPhase.accessDenied) {
            return _buildErrorState(
              context,
              'Access Denied',
              state.errorMessage ??
                  'You do not have permission to access this relationship.',
              colors,
            );
          }

          if (state.phase == OrderPhase.offline) {
            return _buildErrorState(
              context,
              'Network Offline',
              'Please check your internet connection and try again.',
              colors,
            );
          }

          if (state.phase == OrderPhase.emptyInvestors) {
            return _buildErrorState(
              context,
              'No Mapped Investors',
              'There are no actively mapped investors in your workspaces.',
              colors,
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(
                isAdvisor
                    ? 'Advisor-Assisted Order'
                    : 'Place Mutual Fund Order',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: colors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: colors.error),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: GoogleFonts.inter(
                                    color: colors.error, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildBeneficiaryCard(
                        context, state, colors, isAdvisor, auth),
                    const SizedBox(height: 20),
                    if (state.phase == OrderPhase.ready ||
                        state.phase == OrderPhase.failure ||
                        state.phase == OrderPhase.validating) ...[
                      _buildOrderTypeSelector(state, colors),
                      const SizedBox(height: 20),
                      if (state.draft.type == OrderType.buy) ...[
                        _buildSchemeInputs(state, colors),
                        const SizedBox(height: 20),
                        _buildValueInput(state, colors),
                        const SizedBox(height: 24),
                        _buildReviewPanel(state, colors, isAdvisor, auth),
                        const SizedBox(height: 24),
                        _buildActionButtons(state, colors, isAdvisor, auth),
                      ] else ...[
                        _buildUnavailableNotice(state.draft.type, colors),
                      ],
                    ],
                    if (state.phase == OrderPhase.submitting) ...[
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(
                                'Submitting order securely to queue...',
                                style: GoogleFonts.inter(
                                    color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(
      BuildContext context, String title, String msg, AppThemeColors colors) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colors.error),
              const SizedBox(height: 24),
              Text(
                title,
                style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: colors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeneficiaryCard(
    BuildContext context,
    OrderState state,
    AppThemeColors colors,
    bool isAdvisor,
    AuthProvider auth,
  ) {
    if (widget.preSelectedClientId != null) {
      return Card(
        color: colors.activeBackground,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.assignment_ind_outlined, color: colors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beneficiary Client (Locked)',
                      style: GoogleFonts.inter(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.preSelectedClientName ?? 'Unnamed Client',
                      style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!isAdvisor) {
      final name = auth.userProfile?.fullName ?? 'Unnamed Investor';
      final email = auth.userProfile?.email ?? '';
      final phone = auth.userProfile?.phoneNumber ?? '';
      return Card(
        color: colors.activeBackground,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.person_outline, color: colors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Investor Beneficiary',
                      style: GoogleFonts.inter(
                          color: colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: GoogleFonts.outfit(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    if (email.isNotEmpty || phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${MaskingUtil.maskEmail(email)} | ${MaskingUtil.maskPhone(phone)}',
                        style: GoogleFonts.inter(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Select Mapped Investor',
          child: Text(
            'Select Mapped Investor',
            style: GoogleFonts.outfit(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<OrderInvestor>(
          // ignore: deprecated_member_use
          isExpanded: true,
          value: state.draft.context == null
              ? null
              : state.assignedInvestors.firstWhere(
                  (i) => i.investorProfileId == state.draft.context!.investorProfileId &&
                         i.workspaceId == state.draft.context!.workspaceId,
                  orElse: () => state.assignedInvestors.first,
                ),
          items: state.assignedInvestors.map((investor) {
            final wsAbbr = investor.workspaceId.length > 5
                ? investor.workspaceId.substring(0, 5)
                : investor.workspaceId;
            return DropdownMenuItem<OrderInvestor>(
              value: investor,
              child: Text(
                '${investor.investorFullName} (${MaskingUtil.maskEmail(investor.email ?? '')}) [WS: $wsAbbr]',
                style: GoogleFonts.inter(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          decoration: const InputDecoration(
            hintText: 'Choose client',
          ),
          onChanged: (val) {
            if (val != null) {
              _bloc.updateBeneficiary(val.investorProfileId, val.workspaceId);
            }
          },
        ),
      ],
    );
  }

  Widget _buildOrderTypeSelector(OrderState state, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Transaction Type',
          child: Text(
            'Transaction Type',
            style: GoogleFonts.outfit(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<OrderType>(
          segments: const [
            ButtonSegment(value: OrderType.buy, label: Text('Buy')),
            ButtonSegment(value: OrderType.sell, label: Text('Sell')),
            ButtonSegment(value: OrderType.switchOrder, label: Text('Switch')),
          ],
          selected: {state.draft.type},
          onSelectionChanged: (set) {
            if (set.isNotEmpty) {
              _bloc.updateOrderType(set.first);
            }
          },
        ),
      ],
    );
  }

  Widget _buildUnavailableNotice(OrderType type, AppThemeColors colors) {
    final message = type == OrderType.sell
        ? 'Sell requests are temporarily unavailable while the secure folio-order contract is being completed.'
        : 'Switch requests are temporarily unavailable while source-folio and destination-scheme persistence is being completed.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Temporarily Unavailable',
                style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.inter(
              color: colors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeInputs(OrderState state, AppThemeColors colors) {
    if (state.draft.type == OrderType.buy) {
      return SearchableSchemePicker(
        initialItems: state.funds,
        selectedSchemeCode: state.draft.schemeCode,
        onSelected: (code) => _bloc.updateScheme(code),
        onSearch: (q) => widget.repository.searchMutualFunds(q),
        label: 'Scheme',
      );
    }

    if (state.draft.type == OrderType.sell) {
      return _buildHoldingsSelector(
        state: state,
        label: 'Holding Scheme to Sell',
        selectedCode: state.draft.schemeCode,
        onSelected: (code) => _bloc.updateScheme(code),
        colors: colors,
      );
    }

    // Switch Order: Source (holdings) and Destination (searchable scheme universe)
    return Column(
      children: [
        _buildHoldingsSelector(
          state: state,
          label: 'Source Scheme (from holdings)',
          selectedCode: state.draft.schemeCode,
          onSelected: (code) => _bloc.updateScheme(code),
          colors: colors,
        ),
        const SizedBox(height: 20),
        SearchableSchemePicker(
          initialItems: state.funds,
          selectedSchemeCode: state.draft.destSchemeCode,
          onSelected: (code) => _bloc.updateDestScheme(code),
          onSearch: (q) => widget.repository.searchMutualFunds(q),
          label: 'Destination Scheme',
        ),
      ],
    );
  }

  Widget _buildHoldingsSelector({
    required OrderState state,
    required String label,
    required String? selectedCode,
    required ValueChanged<String> onSelected,
    required AppThemeColors colors,
  }) {
    if (state.holdings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No holdings found in this portfolio context. You cannot execute a Sell/Switch.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedCode == null || selectedCode.isEmpty
              ? null
              : selectedCode,
          items: state.holdings.map((h) {
            return DropdownMenuItem<String>(
              value: h['scheme_code'] as String,
              child: Text('${h['scheme_name']} (${h['scheme_code']})'),
            );
          }).toList(),
          decoration: const InputDecoration(hintText: 'Select held scheme'),
          onChanged: (val) {
            if (val != null) {
              onSelected(val);
            }
          },
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildFolioSelector(OrderState state, AppThemeColors colors) {
    if (state.folios.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'No eligible verified folios found. Sell/Switch requires a linked folio.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verified Folio',
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: state.draft.folioNumber == null ||
                  state.draft.folioNumber!.isEmpty
              ? null
              : state.draft.folioNumber,
          items: state.folios.map((folio) {
            return DropdownMenuItem<String>(
              value: folio.folioReferenceId,
              child: Text(
                  '${folio.maskedFolioDisplay} (${folio.registrar})'),
            );
          }).toList(),
          decoration: const InputDecoration(hintText: 'Choose verified folio'),
          onChanged: (val) {
            if (val != null) {
              _bloc.updateFolio(val);
            }
          },
        ),
      ],
    );
  }

  Widget _buildValueInput(OrderState state, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Order Value inputs',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Order Value',
                style: GoogleFonts.outfit(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Amount (₹)'),
                    selected: _isAmountMode,
                    onSelected: (val) {
                      setState(() {
                        _isAmountMode = true;
                        _unitsController.clear();
                        _bloc.updateUnits(null);
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Units'),
                    selected: !_isAmountMode,
                    onSelected: (val) {
                      setState(() {
                        _isAmountMode = false;
                        _amountController.clear();
                        _bloc.updateAmount(null);
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_isAmountMode)
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
            ],
            decoration: const InputDecoration(
              hintText: 'Enter amount in ₹',
              prefixText: '₹ ',
            ),
            onChanged: (val) {
              final parsed = double.tryParse(val);
              _bloc.updateAmount(parsed);
            },
          )
        else
          TextFormField(
            controller: _unitsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}'))
            ],
            decoration: const InputDecoration(
              hintText: 'Enter quantity of units',
            ),
            onChanged: (val) {
              final parsed = double.tryParse(val);
              _bloc.updateUnits(parsed);
            },
          ),
      ],
    );
  }

  Widget _buildReviewPanel(OrderState state, AppThemeColors colors,
      bool isAdvisor, AuthProvider auth) {
    final errors = state.draft.validate();
    if (errors != null) return const SizedBox.shrink();

    final draft = state.draft;
    final ctx = draft.context!;

    return Card(
      color: colors.activeBackground,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Preview',
              style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary),
            ),
            const SizedBox(height: 12),
            _buildReviewRow('Beneficiary', ctx.investorFullName, colors),
            _buildReviewRow('Workspace ID', ctx.workspaceId, colors),
            _buildReviewRow(
                'Order Type',
                draft.type == OrderType.switchOrder
                    ? 'Switch'
                    : draft.type.name.toUpperCase(),
                colors),
            _buildReviewRow('Source Scheme', draft.schemeCode, colors),
            if (draft.type == OrderType.switchOrder)
              _buildReviewRow(
                  'Destination Scheme', draft.destSchemeCode ?? '', colors),
            if (draft.type == OrderType.sell ||
                draft.type == OrderType.switchOrder)
              _buildReviewRow('Verified Folio',
                  MaskingUtil.maskFolio(draft.folioNumber ?? ''), colors),
            if (draft.amount != null)
              _buildReviewRow(
                  'Amount', _currencyFormat.format(draft.amount), colors),
            if (draft.units != null)
              _buildReviewRow('Units', draft.units!.toStringAsFixed(4), colors),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _hasConfirmedReview,
                  onChanged: (val) {
                    setState(() {
                      _hasConfirmedReview = val ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'I confirm that these details are correct. By confirming, I agree to submit this order request for qualification. The order status will start strictly as pending_qualification and will be reviewed.',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewRow(String label, String value, AppThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style:
                  GoogleFonts.inter(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.inter(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(OrderState state, AppThemeColors colors,
      bool isAdvisor, AuthProvider auth) {
    final isValid = state.draft.validate() == null;

    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Semantics(
            label: 'Submit Order Request',
            child: ElevatedButton(
              onPressed: isValid &&
                      _hasConfirmedReview &&
                      state.phase != OrderPhase.submitting
                  ? () => _bloc.submitOrder()
                  : null,
              child: const Text('Submit Request'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState(
      BuildContext context, OrderState state, AppThemeColors colors) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 72, color: Colors.green),
              ),
              const SizedBox(height: 24),
              Text(
                'Request Submitted',
                style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'Your order request was submitted successfully with status pending_qualification and is now in review.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    color: colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 8),
              if (state.submittedOrderId != null)
                Text(
                  'ID: ${state.submittedOrderId}',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colors.primary),
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchableSchemePicker extends StatefulWidget {
  final List<Map<String, dynamic>> initialItems;
  final String? selectedSchemeCode;
  final ValueChanged<String> onSelected;
  final Future<List<Map<String, dynamic>>> Function(String query) onSearch;
  final String label;

  const SearchableSchemePicker({
    required this.initialItems,
    required this.selectedSchemeCode,
    required this.onSelected,
    required this.onSearch,
    required this.label,
    super.key,
  });

  @override
  State<SearchableSchemePicker> createState() => _SearchableSchemePickerState();
}

class _SearchableSchemePickerState extends State<SearchableSchemePicker> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isSearching = false;
  bool _isOpen = false;
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;
  int _currentSearchId = 0;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.initialItems.take(10).toList();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isOpen = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    if (val.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredItems = widget.initialItems.take(10).toList();
          _isSearching = false;
          _searchError = null;
        });
      }
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final searchId = ++_currentSearchId;
      if (mounted) {
        setState(() {
          _isSearching = true;
          _searchError = null;
        });
      }

      try {
        final results = await widget.onSearch(val);
        if (!mounted || searchId != _currentSearchId) {
          return;
        }
        setState(() {
          _filteredItems = results;
          _isSearching = false;
        });
      } catch (e) {
        if (!mounted || searchId != _currentSearchId) return;
        setState(() {
          _isSearching = false;
          _searchError = 'Search failed. Please try again.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = widget.initialItems.firstWhere(
      (item) => item['scheme_code'] == widget.selectedSchemeCode,
      orElse: () => <String, dynamic>{},
    );
    final selectedName = selectedItem['scheme_name'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextFormField(
          focusNode: _focusNode,
          controller: _searchController,
          decoration: InputDecoration(
            hintText:
                selectedName.isNotEmpty ? selectedName : 'Search schemes...',
            suffixIcon: const Icon(Icons.search),
          ),
          onChanged: _onSearchChanged,
        ),
        if (_isOpen) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _isSearching
                ? const Center(
                    child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator()))
                : _searchError != null
                    ? Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _searchError!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _filteredItems.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text('No matching schemes found.'),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredItems.length,
                            itemBuilder: (context, idx) {
                              final item = _filteredItems[idx];
                              final code = item['scheme_code'] as String;
                              final name = item['scheme_name'] as String;
                              return ListTile(
                                title: Text(name),
                                subtitle: Text(code),
                                onTap: () {
                                  widget.onSelected(code);
                                  _searchController.clear();
                                  _focusNode.unfocus();
                                  setState(() {
                                    _isOpen = false;
                                  });
                                },
                              );
                            },
                          ),
          ),
        ],
      ],
    );
  }
}
