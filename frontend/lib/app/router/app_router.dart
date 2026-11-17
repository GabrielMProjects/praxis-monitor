import 'package:material_ui/material_ui.dart';

import '../../features/dashboard/presentation/pages/dashboard_page.dart';

/// Minimal named-route table (the app currently has a single screen).
abstract final class AppRouter {
  static const String dashboard = '/';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => const DashboardPage(),
    );
  }
}
