import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../app_state.dart';
import '../channel_editor.dart';
import '../components.dart';
import '../fixture_name_editor.dart';
import '../gdtf_lookup.dart';
import '../model.dart';
import '../theme.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final fixture = state.fixture!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check what we found',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 10),
        Text(
          'We found a ${fixture.manufacturer} ${fixture.model} with ${fixture.modes.length} ${fixture.modes.length == 1 ? 'mode' : 'modes'} and up to ${fixture.maxModeChannelCount} controls.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        FixtureSummaryCard(
          manufacturer: fixture.manufacturer,
          model: fixture.model,
          modes: fixture.modes.length,
          controls: fixture.maxModeChannelCount,
          onEdit: () => showFixtureNameEditor(context, state),
        ),
        if (state.gdtfMatches.isNotEmpty) ...[
          const SizedBox(height: 18),
          _ExistingProfileCard(matches: state.gdtfMatches),
        ],
        const SizedBox(height: 26),
        Text(
          'Which mode will you use on the light?',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 5),
        const Text('Export keeps every mode. This only chooses what you test.'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var index = 0; index < fixture.modes.length; index++)
              _ModeCard(
                mode: fixture.modes[index],
                selected: state.selectedMode == index,
                onTap: () => state.selectMode(index),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Not sure? Check the mode or personality on the display on the back of your light.',
          style: TextStyle(color: DmxColors.muted),
        ),
        if (state.questions.isNotEmpty) ...[
          const SizedBox(height: 26),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${state.questions.length} ${state.questions.length == 1 ? 'thing needs' : 'things need'} your help:',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final question in state.questions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.help_outline,
                            color: DmxColors.amber,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              question,
                              style: const TextStyle(color: DmxColors.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        AdvancedDisclosurePanel(
          title: 'Edit DMX table',
          child: _ChannelTable(fixture: fixture, state: state),
        ),
        const SizedBox(height: 26),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => state.goTo(2),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Test your light'),
          ),
        ),
      ],
    );
  }
}

class _ExistingProfileCard extends StatelessWidget {
  const _ExistingProfileCard({required this.matches});
  final List<GdtfProfileMatch> matches;

  @override
  Widget build(BuildContext context) => Card(
    color: DmxColors.rustDark,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: DmxColors.amber),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.travel_explore, color: DmxColors.amber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      matches.length == 1
                          ? 'This light may already have a profile'
                          : 'This light may already have profiles',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Using an existing GDTF may include verified geometry, wheel art, and details that are not in your manual.',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final match in matches)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DmxColors.iron,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: DmxColors.border),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${match.manufacturer} ${match.fixture}',
                        style: const TextStyle(
                          color: DmxColors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(_matchDetails(match)),
                    ],
                  );
                  final button = OutlinedButton.icon(
                    onPressed: () => web.window.open(
                      match.url,
                      '_blank',
                      'noopener,noreferrer',
                    ),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Get from GDTF Share'),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [details, const SizedBox(height: 10), button],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 12),
                      button,
                    ],
                  );
                },
              ),
            ),
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: DmxColors.teal),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Only the manufacturer, model, and mode sizes were checked. Your manual stayed on this device.',
                  style: TextStyle(color: DmxColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _matchDetails(GdtfProfileMatch match) {
    final parts = <String>[
      match.source == 'manufacturer'
          ? 'Manufacturer profile'
          : 'Community profile',
      if (match.revision.isNotEmpty) match.revision,
      if (match.modeFootprints.isNotEmpty)
        '${match.modeFootprints.join(' / ')} channels',
      if (match.rating != null) '${match.rating!.toStringAsFixed(1)} ★',
    ];
    return parts.join(' · ');
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });
  final FixtureMode mode;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      color: selected ? DmxColors.rustDark : DmxColors.iron,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? DmxColors.amber : DmxColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? DmxColors.amber : DmxColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: DmxColors.text,
                      ),
                    ),
                    Text('${mode.channelIds.length} channels'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChannelTable extends StatelessWidget {
  const _ChannelTable({required this.fixture, required this.state});
  final FixtureProject fixture;
  final DmxtractState state;
  @override
  Widget build(BuildContext context) {
    if (fixture.modes.isEmpty) {
      return const ExplanationCallout(
        title: 'No DMX mode found yet',
        body:
            'Add a mode before editing channels, or choose the DMX table again on the manual page.',
        icon: Icons.info_outline,
      );
    }
    final mode =
        fixture.modes[state.selectedMode.clamp(0, fixture.modes.length - 1)];
    return Column(
      children: [
        ExplanationCallout(
          title: '${mode.name} DMX table',
          body:
              'These are the ${mode.channelIds.length} controls used by the mode you selected. “Values” are the 0–255 zones that make each control do different things.',
          icon: Icons.tune_outlined,
        ),
        const SizedBox(height: 14),
        for (var position = 0; position < mode.channelIds.length; position++)
          _ChannelRow(
            fixture: fixture,
            state: state,
            channelId: mode.channelIds[position],
            position: position,
          ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.fixture,
    required this.state,
    required this.channelId,
    required this.position,
  });

  final FixtureProject fixture;
  final DmxtractState state;
  final String channelId;
  final int position;

  @override
  Widget build(BuildContext context) {
    final channelIndex = fixture.channels.indexWhere(
      (channel) => channel.id == channelId,
    );
    final channel = fixture.channels[channelIndex];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DmxColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(
              '${position + 1}'.padLeft(3, '0'),
              style: const TextStyle(
                fontFamily: 'DSEG7',
                fontSize: 20,
                color: DmxColors.amber,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              channel.name,
              style: const TextStyle(
                color: DmxColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _ranges(channel),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ConfidenceMarker(score: channel.confidence),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Edit channel ${position + 1}',
            onPressed: () => showChannelEditor(
              context,
              state,
              channelIndex,
              displayNumber: position + 1,
            ),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  String _ranges(DmxChannel channel) => channel.ranges
      .map((range) => '${range.start}–${range.end} ${range.name}')
      .join(' · ');
}
