import 'package:flutter/material.dart';

import 'app_state.dart';

/// Small dialog for correcting the manufacturer/model shown on the Check
/// step's fixture-name header card (screens/review.dart). Mirrors
/// channel_editor.dart's showChannelEditor: capture the edited values, show
/// a dialog, then hand the result to DmxtractState on save.
///
/// Fields use `initialValue` + `onChanged` rather than a TextEditingController
/// — same as the value-range fields in channel_editor.dart — so there is no
/// controller to dispose, and therefore nothing that can be torn down while
/// the dialog's exit transition is still animating out.
///
/// Fields prefill with the current value, except when that value starts
/// with "Unknown" (the placeholder extraction_rules.dart falls back to when
/// it could not read a name from the manual) — those start blank with a
/// hint, so beginners aren't left editing the word "Unknown" by hand.
Future<bool> showFixtureNameEditor(
  BuildContext context,
  DmxtractState state,
) async {
  final fixture = state.fixture!;
  var manufacturer = fixture.manufacturer.startsWith('Unknown')
      ? ''
      : fixture.manufacturer;
  var model = fixture.model.startsWith('Unknown') ? '' : fixture.model;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit fixture name'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              initialValue: manufacturer,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Manufacturer',
                hintText: 'e.g. Generic',
              ),
              onChanged: (value) => manufacturer = value,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: model,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'e.g. Generic',
              ),
              onChanged: (value) => model = value,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save changes'),
        ),
      ],
    ),
  );
  if (save != true) return false;
  state.editFixtureName(manufacturer, model);
  return true;
}
