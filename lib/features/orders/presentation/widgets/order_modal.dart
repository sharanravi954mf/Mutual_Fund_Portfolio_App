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

  const OrderModal({
    super.key,
    required this.repository,
    this.preSelectedClientId,
    this.preSelectedClientName,
  });

  static void show(
    BuildContext context, {
    required OrderRepository repository,
    String? preSelectedClientId,
    String? preSelectedClientName,
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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final workspaceId = auth.userProfile?.role == UserRole.advisor
        ? auth.userProfile?.id ??
            '' // Default to advisor ID as workspace context if not pre-selected
        : auth.userAccount?.userId ?? '';

    // If pre-selected (advisor viewing client details), use client's profile ID
    final beneficiaryId =
        widget.preSelectedClientId ?? auth.userProfile?.id ?? '';

    _bloc = OrderBloc(
      widget.repository,
      workspaceId: workspaceId,
      investorProfileId: beneficiaryId,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialRefLoadCalled) {
      _hasInitialRefLoadCalled = true;
      final auth = Provider.of<AuthProvider>(context);
      final isAdvisor = auth.userProfile?.role == UserRole.advisor;
      final profileId = auth.userProfile?.id ?? '';
      _bloc.loadReferenceData(profileId, isAdvisor: isAdvisor);
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
    final isAdvisor = auth.userProfile?.role == UserRole.advisor;

    return ChangeNotifierProvider<OrderBloc>.value(
      value: _bloc,
      child: Consumer<OrderBloc>(
        builder: (context, bloc, child) {
          final state = bloc.state;

          if (state.phase == 'loadingReferenceData') {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.phase == 'submitted') {
            return _buildSuccessState(context, state, colors);
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

                    // Step 1: Beneficiary Information (Pre-selected or Dropdown)
                    _buildBeneficiaryCard(
                        context, state, colors, isAdvisor, auth),
                    const SizedBox(height: 20),

                    // Step 2: Order Details Form
                    if (state.phase == 'ready' ||
                        state.phase == 'failure' ||
                        state.phase == 'validating') ...[
                      _buildOrderTypeSelector(state, colors),
                      const SizedBox(height: 20),
                      _buildSchemeSelector(state, colors),
                      const SizedBox(height: 20),
                      if (state.draft.type == OrderType.switchOrder) ...[
                        _buildDestSchemeSelector(state, colors),
                        const SizedBox(height: 20),
                      ],
                      if (state.draft.type == OrderType.sell ||
                          state.draft.type == OrderType.switchOrder) ...[
                        _buildFolioSelector(state, colors),
                        const SizedBox(height: 20),
                      ],
                      _buildValueInput(state, colors),
                      const SizedBox(height: 24),
                      _buildReviewPanel(state, colors, isAdvisor, auth),
                      const SizedBox(height: 24),
                      _buildActionButtons(state, colors, isAdvisor, auth),
                    ],

                    if (state.phase == 'submitting') ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Submitting order securely to queue...'),
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
              Column(
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
            ],
          ),
        ),
      );
    }

    if (!isAdvisor) {
      // Self Investor Mode
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
                      'Beneficiary Investor',
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
                      const SizedBox(height: 2),
                      Text(
                        '${email.isNotEmpty ? MaskingUtil.maskEmail(email) : ''} | ${phone.isNotEmpty ? MaskingUtil.maskPhone(phone) : ''}',
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

    // Advisor Mode - select assigned investor
    if (state.assignedInvestors.isEmpty) {
      return Card(
        color: colors.surface,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No actively mapped investors found in your workspace.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Mapped Investor',
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: state.draft.investorProfileId.isEmpty
              ? null
              : state.draft.investorProfileId,
          items: state.assignedInvestors.map((investor) {
            return DropdownMenuItem<String>(
              value: investor.id,
              child: Text(
                  '${investor.fullName} (${MaskingUtil.maskEmail(investor.email ?? '')})'),
            );
          }).toList(),
          decoration: const InputDecoration(
            hintText: 'Choose client',
          ),
          onChanged: (val) {
            if (val != null) {
              _bloc.updateBeneficiary(val, val);
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
        Text(
          'Order Type',
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<OrderType>(
          segments: const [
            ButtonSegment(value: OrderType.buy, label: Text('Buy')),
            ButtonSegment(value: OrderType.sell, label: Text('Sell')),
            ButtonSegment(value: OrderType.switchOrder, label: Text('Switch')),
          ],
          selected: {state.draft.type},
          onSelectionChanged: (Set<OrderType> newSelection) {
            _bloc.updateOrderType(newSelection.first);
            _amountController.clear();
            _unitsController.clear();
          },
        ),
      ],
    );
  }

  Widget _buildSchemeSelector(OrderState state, AppThemeColors colors) {
    if (state.funds.isEmpty) {
      return const Text('Loading mutual funds...');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.draft.type == OrderType.switchOrder
              ? 'Source Scheme'
              : 'Scheme',
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: state.draft.schemeCode.isEmpty ? null : state.draft.schemeCode,
          items: state.funds.map((fund) {
            return DropdownMenuItem<String>(
              value: fund['scheme_code'] as String,
              child: Text('${fund['scheme_name']} (${fund['scheme_code']})'),
            );
          }).toList(),
          decoration: const InputDecoration(
            hintText: 'Select mutual fund',
          ),
          onChanged: (val) {
            if (val != null) {
              _bloc.updateScheme(val);
            }
          },
        ),
      ],
    );
  }

  Widget _buildDestSchemeSelector(OrderState state, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Destination Scheme',
          style: GoogleFonts.outfit(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: state.draft.destSchemeCode == null ||
                  state.draft.destSchemeCode!.isEmpty
              ? null
              : state.draft.destSchemeCode,
          items: state.funds.map((fund) {
            return DropdownMenuItem<String>(
              value: fund['scheme_code'] as String,
              child: Text('${fund['scheme_name']} (${fund['scheme_code']})'),
            );
          }).toList(),
          decoration: const InputDecoration(
            hintText: 'Select destination fund',
          ),
          onChanged: (val) {
            if (val != null) {
              _bloc.updateDestScheme(val);
            }
          },
        ),
      ],
    );
  }

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
              value: folio.normalizedFolioNumber,
              child: Text(
                  '${MaskingUtil.maskFolio(folio.normalizedFolioNumber)} (${folio.registrar})'),
            );
          }).toList(),
          decoration: const InputDecoration(
            hintText: 'Choose verified folio',
          ),
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
        Row(
          children: [
            Text(
              'Order Value',
              style: GoogleFonts.outfit(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
            const Spacer(),
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
            const SizedBox(width: 8),
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
        const SizedBox(height: 8),
        if (_isAmountMode)
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
            ],
            decoration: const InputDecoration(
              hintText: 'Enter amount in ₹ (e.g. 5000)',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
            onChanged: (val) {
              final d = double.tryParse(val);
              _bloc.updateAmount(d);
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
              hintText: 'Enter units (e.g. 10.456)',
              prefixIcon: Icon(Icons.dashboard_customize_outlined),
            ),
            onChanged: (val) {
              final d = double.tryParse(val);
              _bloc.updateUnits(d);
            },
          ),
      ],
    );
  }

  Widget _buildReviewPanel(
    OrderState state,
    AppThemeColors colors,
    bool isAdvisor,
    AuthProvider auth,
  ) {
    final validationErrors = state.draft.validate();
    final isValid = validationErrors == null || validationErrors.isEmpty;

    if (!isValid) return const SizedBox.shrink();

    final name = isAdvisor
        ? (widget.preSelectedClientId != null
            ? (widget.preSelectedClientName ?? 'Client')
            : state.assignedInvestors
                .firstWhere((i) => i.id == state.draft.investorProfileId,
                    orElse: () =>
                        const OrderInvestor(id: '', fullName: 'Client'))
                .fullName)
        : (auth.userProfile?.fullName ?? 'Investor');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Summary & Review',
              style: GoogleFonts.outfit(
                  color: colors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildReviewRow('Order Type',
                state.draft.type.databaseValue.toUpperCase(), colors),
            _buildReviewRow('Beneficiary', name, colors),
            _buildReviewRow('Scheme', state.draft.schemeCode, colors),
            if (state.draft.type == OrderType.switchOrder)
              _buildReviewRow(
                  'Dest Scheme', state.draft.destSchemeCode ?? '', colors),
            if (state.draft.type == OrderType.sell ||
                state.draft.type == OrderType.switchOrder)
              _buildReviewRow('Folio',
                  MaskingUtil.maskFolio(state.draft.folioNumber ?? ''), colors),
            _buildReviewRow(
              'Value',
              _isAmountMode
                  ? _currencyFormat.format(state.draft.amount ?? 0)
                  : '${state.draft.units?.toStringAsFixed(4) ?? '0'} Units',
              colors,
              isMonospace: true,
            ),
            _buildReviewRow(
                'Initiation',
                isAdvisor ? 'Advisor-assisted Portal' : 'Investor Portal',
                colors),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'I confirm this order request is qualified and mapped correctly. I understand this will enter the review pipeline.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: colors.textSecondary),
              ),
              value: _hasConfirmedReview,
              onChanged: (val) {
                setState(() {
                  _hasConfirmedReview = val ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewRow(String label, String value, AppThemeColors colors,
      {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  GoogleFonts.inter(color: colors.textSecondary, fontSize: 13)),
          Text(
            value,
            style: isMonospace
                ? GoogleFonts.inter(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )
                : GoogleFonts.inter(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    OrderState state,
    AppThemeColors colors,
    bool isAdvisor,
    AuthProvider auth,
  ) {
    final validationErrors = state.draft.validate();
    final isValid = (validationErrors == null || validationErrors.isEmpty) &&
        _hasConfirmedReview;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: isValid
                ? () {
                    _bloc.submitOrder(
                      initiatedByProfileId: auth.userProfile?.id ?? '',
                      initiatedByRole: isAdvisor ? 'advisor' : 'investor',
                      initiationChannel:
                          isAdvisor ? 'advisor_portal' : 'investor_portal',
                    );
                  }
                : null,
            child: const Text('Confirm & Submit'),
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 72, color: colors.success),
              const SizedBox(height: 24),
              Text(
                'Order Submitted Successfully',
                style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'The order request has been queued in status pending_qualification. You will be notified once qualified.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 24),
              Card(
                color: colors.activeBackground,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Order ID: ',
                          style:
                              GoogleFonts.inter(color: colors.textSecondary)),
                      SelectableText(
                        state.submittedOrderId ?? 'N/A',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
