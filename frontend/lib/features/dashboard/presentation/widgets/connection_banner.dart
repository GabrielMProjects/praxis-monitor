import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/realtime_client.dart';
import '../cubit/connection_cubit.dart';

/// Small "Live" indicator for the app bar.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionCubit, ConnectionStatus>(
      builder: (context, status) {
        final (label, color, icon) = switch (status) {
          ConnectionStatus.connected => (
            'Live verbunden',
            const Color(0xFF2E7D32),
            Icons.wifi,
          ),
          ConnectionStatus.connecting => (
            'Verbinde …',
            const Color(0xFFF9A825),
            Icons.sync,
          ),
          ConnectionStatus.disconnected => (
            'Getrennt',
            const Color(0xFFC62828),
            Icons.wifi_off,
          ),
        };
        return Semantics(
          container: true,
          liveRegion: true, // connection changes are announced
          label: 'Echtzeit-Verbindung: $label',
          child: ExcludeSemantics(
            child: Chip(
              avatar: Icon(icon, size: 18, color: color),
              label: Text(label),
              side: BorderSide(color: color),
            ),
          ),
        );
      },
    );
  }
}

/// Full-width warning while the live connection is down. Data stays visible (stale) and is
/// re-synchronised automatically once the connection is back.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionCubit, ConnectionStatus>(
      builder: (context, status) {
        if (status == ConnectionStatus.connected) {
          return const SizedBox.shrink();
        }
        final text = status == ConnectionStatus.connecting
            ? 'Verbindung zum Echtzeit-Server wird aufgebaut …'
            : 'Echtzeit-Verbindung getrennt – Anzeige evtl. veraltet. Verbindung wird automatisch neu aufgebaut.';
        return Semantics(
          liveRegion: true,
          child: Material(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
