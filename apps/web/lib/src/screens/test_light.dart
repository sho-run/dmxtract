import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../app_state.dart';
import '../bridge_client.dart';
import '../channel_editor.dart';
import '../components.dart';
import '../model.dart';
import '../theme.dart';

class TestLightScreen extends StatelessWidget {
  const TestLightScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final channel = state.channel;
    final mode = state.mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test your light',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Go one control at a time. Start with the light pointed somewhere safe.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            if (state.outputActive)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: DmxColors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: state.stopOutput,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop output'),
              ),
          ],
        ),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before you connect',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 14),
                const _Check(number: 1, text: 'Plug in your DMX interface.'),
                const _Check(number: 2, text: 'Turn on the light.'),
                _Check(
                  number: 3,
                  text:
                      'Set the light to ${mode?.shortName.isNotEmpty == true ? mode!.shortName : mode?.name ?? 'the selected mode'}.',
                ),
                _Check(
                  number: 4,
                  text:
                      'Set its DMX address to ${state.startAddress.toString().padLeft(3, '0')}.',
                ),
                const SizedBox(height: 12),
                _StartAddressField(state: state),
                const SizedBox(height: 5),
                _DipCalculator(address: state.startAddress),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connect your DMX output',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          BridgeConnectionStatus(
                            available: state.bridgeAvailable,
                            active: state.outputActive,
                            label: state.outputLabel,
                          ),
                          if (state.bridgeAvailable) ...[
                            const SizedBox(height: 4),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _openBridgeControls(state),
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('View bridge controls'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!state.outputActive)
                      FilledButton.icon(
                        onPressed: state.bridgeChecking
                            ? null
                            : state.bridgeAvailable
                            ? () => _connect(context, state)
                            : state.refreshBridgeAvailability,
                        icon: Icon(
                          state.bridgeAvailable
                              ? Icons.cable_outlined
                              : Icons.search_outlined,
                        ),
                        label: Text(
                          state.bridgeChecking
                              ? 'Looking…'
                              : state.bridgeAvailable
                              ? 'Connect'
                              : 'Find bridge',
                        ),
                      ),
                  ],
                ),
                if (!state.bridgeAvailable)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: ExplanationCallout(
                      title: 'Open the helper app first',
                      body:
                          'Open DMXtract Bridge on this computer, then choose Find bridge. Chrome or Edge may ask to allow local network access; this only reaches the helper on this computer.',
                      icon: Icons.download_outlined,
                    ),
                  ),
                if (state.bridgeAvailable && !state.outputActive)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: ExplanationCallout(
                      title: 'Bridge found on this Mac',
                      body:
                          'The bridge runs only on this computer. Its controls show which site is requesting access and whether DMX output is active.',
                      icon: Icons.visibility_outlined,
                    ),
                  ),
                if (state.outputActive)
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: ExplanationCallout(
                      title: 'Output starts at zero',
                      body:
                          'If this page, the bridge, or your connection disappears, the bridge sends a zero frame.',
                      icon: Icons.shield_outlined,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (channel != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  DmxReadout(
                    channel: state.outputChannel,
                    value: state.testValue,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    channel.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _rangeLabel(channel, state.testValue),
                    style: const TextStyle(
                      color: DmxColors.amber,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: DmxColors.rust.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DmxColors.rust),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'You should expect',
                          style: TextStyle(
                            color: DmxColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _expectation(channel, state.testValue),
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: state.testChannel > 0
                            ? () => state.nextChannel(-1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      Expanded(
                        child: Semantics(
                          label: 'DMX value from zero to 255',
                          value: '${state.testValue}',
                          child: Slider(
                            value: state.testValue.toDouble(),
                            min: 0,
                            max: 255,
                            divisions: 255,
                            onChanged: (value) =>
                                _changeValue(context, state, value.round()),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            state.testChannel + 1 <
                                (mode?.channelIds.length ?? 0)
                            ? () => state.nextChannel(1)
                            : null,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                  if (channel.ranges.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final range in channel.ranges)
                            OutlinedButton(
                              onPressed: () =>
                                  _changeValue(context, state, range.start),
                              child: Text('${range.start} · ${range.name}'),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text(
                    'What do you see?',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: DmxColors.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final observation in const [
                        'Brightness',
                        'Color',
                        'Movement',
                        'Gobo',
                        'Flash',
                        'Nothing',
                        'Something else',
                      ])
                        ChoiceChip(
                          label: Text(observation),
                          selected: state.lastObservation == observation,
                          onSelected: (selected) {
                            if (selected) {
                              _observe(context, state, observation);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 18),
        AdvancedDisclosurePanel(
          title: 'Advanced test · all raw channels',
          child: Column(
            children: [
              for (
                var index = 0;
                index < (mode?.channelIds.length ?? 0);
                index++
              )
                Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${state.startAddress + index}',
                        style: const TextStyle(fontFamily: 'JetBrains Mono'),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        state.fixture!.channels
                            .firstWhere(
                              (item) => item.id == mode!.channelIds[index],
                            )
                            .name,
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: Slider(
                        value: index == state.testChannel
                            ? state.testValue.toDouble()
                            : 0,
                        min: 0,
                        max: 255,
                        onChanged: (value) async {
                          await state.setChannel(index);
                          if (!context.mounted) return;
                          await _changeValue(context, state, value.round());
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () async {
              if (state.outputActive) await state.stopOutput();
              state.goTo(3);
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Download profile'),
          ),
        ),
      ],
    );
  }

  static String _rangeLabel(DmxChannel channel, int value) =>
      channel.ranges
          .where((range) => range.contains(value))
          .firstOrNull
          ?.name ??
      'Value $value';

  static String _expectation(DmxChannel channel, int value) {
    final name = channel.name.toLowerCase();
    final range = _rangeLabel(channel, value);
    final rangeIsUseful =
        !range.startsWith('Value ') && !range.toLowerCase().contains('unknown');
    for (final color in const [
      'red',
      'green',
      'blue',
      'white',
      'amber',
      'uv',
      'cyan',
      'magenta',
      'yellow',
    ]) {
      if (name.contains(color) || range.toLowerCase().contains(color)) {
        return value == 0 ? 'No $color light' : '$color light';
      }
    }
    if (rangeIsUseful) return range;
    if (name.contains('pan')) return 'Horizontal movement';
    if (name.contains('tilt')) return 'Vertical movement';
    if (name.contains('dimmer') || name.contains('intensity')) {
      return value == 0 ? 'The light goes dark' : 'Brightness changes';
    }
    if (name.contains('strobe') || name.contains('shutter')) return 'Flashing';
    if (name.contains('gobo')) return 'A gobo pattern changes';
    return channel.name;
  }

  static String _expectedObservation(DmxChannel channel, int value) {
    final text = '${channel.name} ${_rangeLabel(channel, value)}'.toLowerCase();
    if (value == 0) return 'Nothing';
    if (text.contains('dimmer') ||
        text.contains('intensity') ||
        text.contains('master')) {
      return 'Brightness';
    }
    if (text.contains('red') ||
        text.contains('green') ||
        text.contains('blue') ||
        text.contains('white') ||
        text.contains('amber') ||
        text.contains('color') ||
        text.contains('colour') ||
        text.contains('cyan') ||
        text.contains('magenta') ||
        text.contains('yellow') ||
        text.contains('uv')) {
      return 'Color';
    }
    if (text.contains('pan') ||
        text.contains('tilt') ||
        text.contains('move')) {
      return 'Movement';
    }
    if (text.contains('gobo') || text.contains('pattern')) return 'Gobo';
    if (text.contains('strobe') ||
        text.contains('shutter') ||
        text.contains('flash')) {
      return 'Flash';
    }
    return channel.name;
  }

  static Future<void> _observe(
    BuildContext context,
    DmxtractState state,
    String observation,
  ) async {
    final channel = state.channel;
    if (channel == null) return;
    state.markObservation(observation);
    final expected = _expectedObservation(channel, state.testValue);
    if (observation == expected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Great — that matches $expected.')),
      );
      return;
    }
    final index = state.fixture!.channels.indexOf(channel);
    await showChannelEditor(
      context,
      state,
      index,
      retest: true,
      displayNumber: state.testChannel + 1,
    );
  }

  static Future<void> _changeValue(
    BuildContext context,
    DmxtractState state,
    int value,
  ) async {
    final range = state.channel?.ranges
        .where((item) => item.contains(value))
        .firstOrNull;
    if (range != null && range.safety != 'normal' && !state.riskyUnlocked) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(
            Icons.warning_amber_outlined,
            color: DmxColors.red,
            size: 40,
          ),
          title: Text('${range.name} can be disruptive'),
          content: const Text(
            'Strobe, lamp, reset, and maintenance commands stay locked. Make sure nobody is looking into the light and the fixture is safely positioned.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep locked'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: DmxColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unlock risky output'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      await state.unlockRisky();
    }
    await state.setTestValue(value);
  }

  static Future<void> _connect(
    BuildContext context,
    DmxtractState state,
  ) async {
    try {
      if (state.bridge.token == null) {
        _openBridgeControls(state);
        final requestId = await state.requestPair();
        if (!context.mounted) return;
        final approved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              _BridgeApprovalDialog(state: state, requestId: requestId),
        );
        if (approved != true) return;
      }
      if (!context.mounted) return;
      List<ArtNetNode> nodes = const [];
      try {
        nodes = await state.bridge.discoverArtNet();
      } catch (_) {}
      if (!context.mounted) return;
      final config = await _outputDialog(context, nodes);
      if (config != null) await state.beginOutput(config);
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(exception.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  static void _openBridgeControls(DmxtractState state) {
    web.window.open(
      state.bridge.controlsUrl,
      'dmxtract-bridge-controls',
      'noopener,noreferrer',
    );
  }

  static Future<Map<String, Object?>?> _outputDialog(
    BuildContext context,
    List<ArtNetNode> nodes,
  ) async {
    var kind = 'artNet';
    final detail = TextEditingController(
      text: nodes.isEmpty ? '2.255.255.255' : nodes.first.host,
    );
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('How is your light connected?'),
          content: SizedBox(
            width: 500,
            child: RadioGroup<String>(
              groupValue: kind,
              onChanged: (value) => setState(() {
                if (value == null) return;
                kind = value;
                detail.text = switch (value) {
                  'openDmx' => '/dev/cu.usbserial',
                  'artNet' => '2.255.255.255',
                  _ => '',
                };
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile(
                    value: 'openDmx',
                    title: const Text('USB DMX cable'),
                    subtitle: const Text('Open DMX · FTDI'),
                  ),
                  RadioListTile(
                    value: 'artNet',
                    title: const Text('Network DMX'),
                    subtitle: const Text('Art-Net'),
                  ),
                  RadioListTile(
                    value: 'sacn',
                    title: const Text('Network DMX'),
                    subtitle: const Text('sACN · multicast'),
                  ),
                  RadioListTile(
                    value: 'preview',
                    title: const Text('Choose manually'),
                    subtitle: const Text('Preview only · no real output'),
                  ),
                  if (kind == 'artNet' && nodes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${nodes.length} Art-Net ${nodes.length == 1 ? 'device' : 'devices'} found automatically',
                        style: const TextStyle(
                          color: DmxColors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final node in nodes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          detail.text == node.host
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: detail.text == node.host
                              ? DmxColors.amber
                              : DmxColors.muted,
                        ),
                        title: Text(
                          node.name.isEmpty ? 'Art-Net device' : node.name,
                        ),
                        subtitle: Text(
                          '${node.host} · ${node.portCount} ${node.portCount == 1 ? 'output' : 'outputs'}',
                        ),
                        onTap: () => setState(() => detail.text = node.host),
                      ),
                  ],
                  if (kind != 'preview')
                    TextField(
                      controller: detail,
                      decoration: InputDecoration(
                        labelText: kind == 'openDmx'
                            ? 'USB device path'
                            : kind == 'artNet'
                            ? nodes.isEmpty
                                  ? 'Node or broadcast IP address'
                                  : 'IP address · advanced fallback'
                            : 'Optional unicast IP address',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, switch (kind) {
                'openDmx' => {'kind': 'openDmx', 'path': detail.text},
                'artNet' => {
                  'kind': 'artNet',
                  'host': detail.text,
                  'port': 6454,
                },
                'sacn' => {
                  'kind': 'sacn',
                  'host': detail.text.isEmpty ? null : detail.text,
                  'port': 5568,
                  'priority': 100,
                },
                _ => {'kind': 'preview'},
              }),
              child: const Text('Start at zero'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BridgeApprovalDialog extends StatefulWidget {
  const _BridgeApprovalDialog({required this.state, required this.requestId});
  final DmxtractState state;
  final String requestId;

  @override
  State<_BridgeApprovalDialog> createState() => _BridgeApprovalDialogState();
}

class _BridgeApprovalDialogState extends State<_BridgeApprovalDialog> {
  Timer? _poller;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => _checkApproval(),
    );
    unawaited(_checkApproval());
  }

  Future<void> _checkApproval() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final status = await widget.state.checkPairApproval(widget.requestId);
      if (!mounted) return;
      if (status == PairApprovalStatus.approved) {
        Navigator.pop(context, true);
      } else if (status == PairApprovalStatus.denied) {
        _poller?.cancel();
        setState(() => _error = 'Access was denied in the Bridge controls.');
      }
    } catch (exception) {
      if (mounted) {
        setState(
          () => _error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Approve in Bridge controls'),
    content: SizedBox(
      width: 470,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A local Bridge controls page opened. Check the requesting site, then choose Allow this site. DMXtract will continue automatically.',
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: DmxColors.red)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: () => TestLightScreen._openBridgeControls(widget.state),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open bridge controls'),
      ),
    ],
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.number, required this.text});
  final int number;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: DmxColors.inset,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              color: DmxColors.amber,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(color: DmxColors.text)),
        ),
      ],
    ),
  );
}

class _StartAddressField extends StatefulWidget {
  const _StartAddressField({required this.state});
  final DmxtractState state;

  @override
  State<_StartAddressField> createState() => _StartAddressFieldState();
}

class _StartAddressFieldState extends State<_StartAddressField> {
  late final TextEditingController controller = TextEditingController(
    text: '${widget.state.startAddress}',
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 310),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Where your light listens — DMX address',
        helperText: 'Choose 1–${widget.state.maxStartAddress}',
      ),
      onChanged: (value) {
        final address = int.tryParse(value);
        if (address != null) widget.state.setStartAddress(address);
      },
    ),
  );
}

class _DipCalculator extends StatelessWidget {
  const _DipCalculator({required this.address});
  final int address;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'My light uses little switches',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 12,
          children: [
            Text(
              'For address ${address.toString().padLeft(3, '0')}, turn on:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (var index = 0; index < 9; index++)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: address & (1 << index) != 0,
                    onChanged: null,
                    activeThumbColor: DmxColors.amber,
                  ),
                  Text(
                    '${index + 1}',
                    style: const TextStyle(fontFamily: 'JetBrains Mono'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
