import 'package:flutter/material.dart';

import 'app_state.dart';
import 'gdtf_attribute_catalog.dart';
import 'model.dart';

Future<bool> showChannelEditor(
  BuildContext context,
  DmxtractState state,
  int index, {
  bool retest = false,
  int? displayNumber,
}) async {
  final channel = state.fixture!.channels[index];
  final name = TextEditingController(text: channel.name);
  var selectedAttribute =
      channel.gdtfAttribute ??
      defaultGdtfAttribute(channel.kind, channel.color);
  var selectedFeature =
      channel.gdtfFeature ?? defaultGdtfFeature(selectedAttribute);
  final ranges = channel.ranges
      .map(
        (range) => DmxRange(
          start: range.start,
          end: range.end,
          name: range.name,
          safety: range.safety,
          confidence: range.confidence,
        ),
      )
      .toList();
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Edit channel ${displayNumber ?? index + 1}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (retest) ...[
                  const Text(
                    'What you saw did not match the manual. Correct the control or its value ranges, then test it again.',
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'What it controls',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Channel type',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Start typing what this control does. The GDTF name is shown second for lighting software.',
                ),
                const SizedBox(height: 8),
                Autocomplete<GdtfAttributeDefinition>(
                  initialValue: TextEditingValue(text: selectedAttribute),
                  displayStringForOption: (option) => option.concreteName,
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return gdtfAttributeCatalog.take(20);
                    }
                    return gdtfAttributeCatalog
                        .where((option) => option.searchText.contains(query))
                        .take(30);
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) =>
                          TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onSubmitted: (_) => onFieldSubmitted(),
                            onChanged: (value) => setDialogState(() {
                              selectedAttribute = value.trim();
                              selectedFeature = defaultGdtfFeature(
                                selectedAttribute,
                              );
                            }),
                            decoration: InputDecoration(
                              labelText: 'Search channel types',
                              hintText: 'Try brightness, red, pan, gobo…',
                              helperText: 'GDTF feature: $selectedFeature',
                              prefixIcon: const Icon(Icons.search),
                            ),
                          ),
                  optionsViewBuilder: (context, onSelected, options) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxHeight: 300,
                          maxWidth: 560,
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option.beginnerLabel),
                              subtitle: Text(
                                '${option.concreteName} · ${option.feature}',
                              ),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  onSelected: (option) => setDialogState(() {
                    selectedAttribute = option.concreteName;
                    selectedFeature = option.feature;
                  }),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Value ranges',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (
                  var rangeIndex = 0;
                  rangeIndex < ranges.length;
                  rangeIndex++
                )
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: TextFormField(
                            initialValue: '${ranges[rangeIndex].start}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'From',
                            ),
                            onChanged: (value) => ranges[rangeIndex].start =
                                int.tryParse(value)?.clamp(0, 255) ??
                                ranges[rangeIndex].start,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 72,
                          child: TextFormField(
                            initialValue: '${ranges[rangeIndex].end}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'To'),
                            onChanged: (value) => ranges[rangeIndex].end =
                                int.tryParse(value)?.clamp(0, 255) ??
                                ranges[rangeIndex].end,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: ranges[rangeIndex].name,
                            decoration: const InputDecoration(
                              labelText: 'What happens',
                            ),
                            onChanged: (value) =>
                                ranges[rangeIndex].name = value,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove this range',
                          onPressed: () =>
                              setDialogState(() => ranges.removeAt(rangeIndex)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setDialogState(
                    () => ranges.add(
                      DmxRange(start: 0, end: 255, name: 'New range'),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add range'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: Icon(retest ? Icons.replay_outlined : Icons.save_outlined),
            label: Text(retest ? 'Save and retest' : 'Save changes'),
          ),
        ],
      ),
    ),
  );
  final editedName = name.text;
  name.dispose();
  if (save != true) return false;
  if (selectedAttribute.trim().isEmpty) {
    selectedAttribute = defaultGdtfAttribute(channel.kind, channel.color);
  }
  final definition = gdtfDefinitionFor(selectedAttribute);
  selectedFeature = definition?.feature ?? selectedFeature;
  state.editChannel(
    index,
    editedName,
    selectedAttribute,
    selectedFeature,
    kindForGdtfAttribute(selectedAttribute),
    ranges,
  );
  if (retest) await state.retestChannel();
  return true;
}
