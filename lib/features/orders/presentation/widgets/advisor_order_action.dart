import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/order_repository.dart';
import 'order_modal.dart';

/// A platform-neutral widget that renders an "Initiate Order" action button
/// for authorised MFD/advisor profiles.
///
/// This widget is deliberately isolated from web-only code so it can be
/// tested independently in Dart VM widget tests.
///
/// Access contract:
/// - Only rendered for profiles with role = advisor or admin (workspace-owner).
/// - Must NOT be shown to investors, exploring investors, family guests,
///   platform admins, or unauthenticated users.
/// - Authorisation is determined by the caller before constructing this widget.
class AdvisorOrderAction extends StatelessWidget {
  final OrderRepository repository;

  const AdvisorOrderAction({
    super.key,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('initiate_order_button'),
      icon: const Icon(Icons.add_shopping_cart, size: 18),
      label: Text(
        'Initiate Order',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      onPressed: () {
        OrderModal.show(
          context,
          repository: repository,
          // No pre-selected client: advisor selects from their relationship list
          preSelectedClientId: null,
          preSelectedClientName: null,
        );
      },
    );
  }
}
