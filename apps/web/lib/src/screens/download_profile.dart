import 'package:flutter/material.dart';
import '../components.dart';
import '../core_export.dart';
import '../download.dart';
import '../export_service.dart';
import '../model.dart';
import '../theme.dart';

class DownloadProfileScreen extends StatelessWidget {
  const DownloadProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final fixture = state.fixture!;
    final base = '${slug(fixture.manufacturer)}-${slug(fixture.model)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Download profile',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose where you want to use it. You do not need to configure any schema or geometry settings.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DmxColors.green.withValues(alpha: .09),
            border: Border.all(color: DmxColors.green.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: DmxColors.green,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ready to use',
                      style: TextStyle(
                        color: DmxColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    Text(
                      '${fixture.modes.length} ${fixture.modes.length == 1 ? 'mode' : 'modes'} · up to ${fixture.maxModeChannelCount} channels · ${fixture.wheels.where((wheel) => wheel['kind'] == 'color').length} color wheel · ${fixture.wheels.where((wheel) => wheel['kind'] == 'gobo').length} gobo wheel',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const ExplanationCallout(
          title: 'Basic fixture shape',
          body:
              'No 3D model was provided, so the GDTF uses a simple body and beam. All extracted controls are still included.',
          icon: Icons.view_in_ar_outlined,
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _FormatCard(
                icon: Icons.data_object_outlined,
                title: 'OFL profile',
                body:
                    'Best for open-source lighting programs and sharing fixture data.',
                action: 'Download OFL',
                onPressed: () async => downloadBytes(
                  '$base.json',
                  'application/json',
                  await exportOflShared(fixture),
                ),
              ),
              _FormatCard(
                icon: Icons.inventory_2_outlined,
                title: 'GDTF profile',
                body:
                    'Best for newer consoles, visualizers, and apps that support GDTF.',
                action: 'Download GDTF',
                onPressed: () async => downloadBytes(
                  '$base.gdtf',
                  'application/zip',
                  await exportGdtfShared(fixture),
                ),
              ),
            ];
            return constraints.maxWidth < 720
                ? Column(
                    children: [
                      for (final card in cards)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: card,
                        ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 16),
                      Expanded(child: cards[1]),
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.edit_document, color: DmxColors.amber),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save editable project',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: DmxColors.text,
                        ),
                      ),
                      Text(
                        'Keep your corrections, source notes, and uncertainty as a .dmxtract.json file.',
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => downloadBytes(
                    '$base.dmxtract.json',
                    'application/json',
                    exportProject(fixture),
                  ),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Save project'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final Future<void> Function() onPressed;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: DmxColors.rust.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: DmxColors.amber),
          ),
          const SizedBox(height: 15),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(body),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onPressed(),
              icon: const Icon(Icons.download_outlined),
              label: Text(action),
            ),
          ),
        ],
      ),
    ),
  );
}
