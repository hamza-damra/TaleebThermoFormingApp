import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/palletizing_provider.dart';

/// Wraps the content of a dialog / page that belongs to one palletizing line
/// and closes that route as soon as the line leaves the rendered list (an
/// administrator switched it off). The screen then shows the
/// "تم إيقاف الخط" notice.
///
/// The route is removed with [NavigatorState.removeRoute], so it targets this
/// exact route even when another dialog (the notice itself) is on top. A
/// `showDialog` future completes with `null`, which every line-scoped caller
/// already treats as "cancelled".
///
/// Do not wrap the pallet success dialog: a pallet created just before the
/// line was switched off must still be shown and printed.
class LineScopedRoute extends StatefulWidget {
  final int lineId;
  final Widget child;

  const LineScopedRoute({super.key, required this.lineId, required this.child});

  @override
  State<LineScopedRoute> createState() => _LineScopedRouteState();
}

class _LineScopedRouteState extends State<LineScopedRoute> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final rendered = context.select<PalletizingProvider, bool>(
      (p) => p.isLineRendered(widget.lineId),
    );
    if (!rendered && !_closing) {
      _closing = true;
      final route = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route != null && route.isActive) navigator.removeRoute(route);
      });
    }
    return widget.child;
  }
}
