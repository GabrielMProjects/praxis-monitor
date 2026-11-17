import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/network/realtime_client.dart';

/// Mirrors the state of the single shared WebSocket for the UI.
class ConnectionCubit extends Cubit<ConnectionStatus> {
  ConnectionCubit(RealtimeClient client) : super(client.currentStatus) {
    _subscription = client.status.listen((status) {
      if (status != state) emit(status);
    });
  }

  late final StreamSubscription<ConnectionStatus> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
