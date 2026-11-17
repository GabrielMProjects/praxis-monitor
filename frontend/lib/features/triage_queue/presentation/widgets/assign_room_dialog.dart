import 'package:material_ui/material_ui.dart';

/// A room the user may pick for a patient. Deliberately a tiny feature-local type: the triage feature
/// must not depend on the rooms feature; the dashboard maps rooms to options.
class RoomOption {
  const RoomOption({required this.id, required this.name});
  final String id;
  final String name;
}

/// Lets the user choose one of the available rooms. Returns the chosen room id (or null).
Future<String?> showAssignRoomDialog(
  BuildContext context, {
  required String patientName,
  required List<RoomOption> rooms,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('$patientName – Raum wählen'),
      children: [
        for (final room in rooms)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(room.id),
            child: Row(
              children: [
                const Icon(Icons.meeting_room_outlined),
                const SizedBox(width: 12),
                Text(room.name),
              ],
            ),
          ),
      ],
    ),
  );
}
