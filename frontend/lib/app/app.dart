import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../features/dashboard/presentation/cubit/connection_cubit.dart';
import '../features/rooms/presentation/bloc/rooms_bloc.dart';
import '../features/triage_queue/presentation/bloc/triage_queue_bloc.dart';
import 'di/app_dependencies.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Owns the dependency container (and with it the single WebSocket) and provides the BLoCs.
class PraxisMonitorApp extends StatefulWidget {
  const PraxisMonitorApp({super.key, this.dependencies});

  /// Injectable for tests; production uses the default container.
  final AppDependencies? dependencies;

  @override
  State<PraxisMonitorApp> createState() => _PraxisMonitorAppState();
}

class _PraxisMonitorAppState extends State<PraxisMonitorApp> {
  late final AppDependencies _deps = widget.dependencies ?? AppDependencies();

  @override
  void initState() {
    super.initState();
    _deps.realtime.connect();
  }

  @override
  void dispose() {
    _deps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ConnectionCubit(_deps.realtime)),
        BlocProvider(
          create: (_) =>
              TriageQueueBloc(repository: _deps.patients)
                ..add(const QueueStarted()),
        ),
        BlocProvider(
          create: (_) =>
              RoomsBloc(repository: _deps.rooms)..add(const RoomsStarted()),
        ),
      ],
      child: MaterialApp(
        title: 'Praxis Monitor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        initialRoute: AppRouter.dashboard,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
