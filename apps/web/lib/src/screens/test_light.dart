import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../app_state.dart';
import '../bridge_client.dart';
import '../channel_editor.dart';
import '../components.dart';
import '../core_export.dart';
import '../download.dart';
import '../model.dart';
import '../test_output.dart';
import '../theme.dart';
import '../webserial_dmx.dart';
import '../webserial_frame.dart' show WidgetMode;

/// Which card the user picked behind "How is your light connected?". Null
/// (in [_TestLightScreenState._selected]) means the chooser itself is shown.
enum TestConnectionOption {
  /// Card 1: in-page Web Serial transport, straight from this browser tab.
  usbSerial,

  /// Card 2: the existing Bridge helper app (Art-Net / sACN).
  networkNode,

  /// Card 3: bring-your-own console/software. No transport is ever attached
  /// for this option — [DmxtractState.output] stays null throughout, so the
  /// browser sends zero DMX; the user sets every value themselves in their
  /// own software following on-screen instructions.
  manualConsoleTest,

  /// Card 4: browser-local virtual output, no hardware.
  virtual,
}

class TestLightScreen extends StatefulWidget {
  const TestLightScreen({super.key});
  @override
  State<TestLightScreen> createState() => _TestLightScreenState();
}

class _TestLightScreenState extends State<TestLightScreen> {
  TestConnectionOption? _selected;
  DmxtractState? _scopedState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scopedState = DmxScope.of(context);
  }

  @override
  void dispose() {
    // Blackout on navigation away: this fires whenever the Test step's
    // widget subtree is torn down (step indicator, header logo, "Download
    // profile", or leaving the page entirely) regardless of which
    // connection card was live. Fire-and-forget — dispose() cannot await,
    // and DmxtractState.stopOutput() clears its active-output state
    // synchronously so the light still gets zeroed even after this widget
    // is gone.
    // Gate on `output != null`, not `outputActive`: a Web Serial session
    // that dropped to TestOutputStatus.disconnected (cable unplugged) still
    // holds a live port/listeners that only `end()` releases, even though
    // `outputActive` is already false by then.
    final state = _scopedState;
    if (state != null && state.output != null) {
      unawaited(state.stopOutputForDispose());
    }
    super.dispose();
  }

  Future<void> _changeConnection(DmxtractState state) async {
    if (state.output != null) await state.stopOutput();
    if (!mounted) return;
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(
          state: state,
          onChangeConnection: selected == null
              ? null
              : () => _changeConnection(state),
        ),
        const SizedBox(height: 22),
        if (selected == null)
          _ConnectionChooser(
            onSelect: (option) => setState(() => _selected = option),
          )
        else ...[
          if (selected != TestConnectionOption.manualConsoleTest) ...[
            _ChecklistCard(
              state: state,
              hardware: selected != TestConnectionOption.virtual,
            ),
            const SizedBox(height: 18),
          ],
          switch (selected) {
            TestConnectionOption.usbSerial => const _UsbSerialConnect(),
            TestConnectionOption.networkNode => const _NetworkNodeConnect(),
            TestConnectionOption.manualConsoleTest =>
              const _ManualConsoleConnect(),
            TestConnectionOption.virtual => const _VirtualConnect(),
          },
          if (selected != TestConnectionOption.manualConsoleTest) ...[
            const SizedBox(height: 18),
            _GuidedTesterPanel(state: state),
          ],
        ],
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () async {
              if (state.output != null) await state.stopOutput();
              state.goTo(3);
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Download profile'),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onChangeConnection});
  final DmxtractState state;
  final VoidCallback? onChangeConnection;
  @override
  Widget build(BuildContext context) => Row(
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
      if (onChangeConnection != null && !state.outputActive)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: OutlinedButton.icon(
            onPressed: onChangeConnection,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Change connection'),
          ),
        ),
      if (state.outputActive)
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: DmxColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: state.stopOutput,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop output'),
          ),
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Card 0: the "How is your light connected?" chooser.
// ---------------------------------------------------------------------------

class _ConnectionChooser extends StatefulWidget {
  const _ConnectionChooser({required this.onSelect});
  final ValueChanged<TestConnectionOption> onSelect;

  @override
  State<_ConnectionChooser> createState() => _ConnectionChooserState();
}

class _ConnectionChooserState extends State<_ConnectionChooser> {
  bool _cableReady = false;

  @override
  void initState() {
    super.initState();
    if (isWebSerialSupported) unawaited(_checkGrantedPort());
  }

  Future<void> _checkGrantedPort() async {
    final ready = await WebSerialDmxTransport.hasGrantedPort();
    if (mounted && ready) setState(() => _cableReady = true);
  }

  @override
  Widget build(BuildContext context) {
    final serialSupported = isWebSerialSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'How is your light connected?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const BetaPill(),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Light testing is new and still being proven against real rigs — '
          'if something misbehaves, please open a GitHub issue. What DMXtract '
          'never asks for: an account, notifications, or anything installed '
          'for USB testing.',
          style: TextStyle(color: DmxColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 280,
              child: _ConnectionCard(
                icon: Icons.usb_outlined,
                title: 'USB DMX cable or dongle',
                subtitle: 'Test straight from this browser tab.',
                badge: serialSupported && _cableReady
                    ? 'Your cable from last time is ready'
                    : null,
                enabled: serialSupported,
                disabledReason: serialSupported
                    ? null
                    : 'needs Chrome or Edge on a computer — or use another option below',
                onTap: () => widget.onSelect(TestConnectionOption.usbSerial),
              ),
            ),
            SizedBox(
              width: 280,
              child: _ConnectionCard(
                icon: Icons.lan_outlined,
                title: 'Network node (Art-Net / sACN)',
                subtitle: 'Send DMX to a node on your network.',
                enabled: true,
                onTap: () => widget.onSelect(TestConnectionOption.networkNode),
              ),
            ),
            SizedBox(
              width: 280,
              child: _ConnectionCard(
                icon: Icons.terminal_outlined,
                title: 'My own lighting software or console',
                subtitle: 'Drive the test from QLC+, a console, or similar.',
                enabled: true,
                onTap: () =>
                    widget.onSelect(TestConnectionOption.manualConsoleTest),
              ),
            ),
            SizedBox(
              width: 280,
              child: _ConnectionCard(
                icon: Icons.visibility_outlined,
                title: 'Just checking the numbers',
                subtitle: 'No hardware — preview channel values only.',
                enabled: true,
                onTap: () => widget.onSelect(TestConnectionOption.virtual),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
    this.disabledReason,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  final String? disabledReason;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: DmxColors.amber, size: 28),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  enabled ? subtitle : (disabledReason ?? subtitle),
                  style: const TextStyle(color: DmxColors.muted, fontSize: 13),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: DmxColors.green.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: DmxColors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return enabled ? card : Tooltip(message: disabledReason ?? '', child: card);
  }
}

// ---------------------------------------------------------------------------
// Card 1: USB DMX cable/dongle via Web Serial.
// ---------------------------------------------------------------------------

class _UsbSerialConnect extends StatefulWidget {
  const _UsbSerialConnect();
  @override
  State<_UsbSerialConnect> createState() => _UsbSerialConnectState();
}

class _UsbSerialConnectState extends State<_UsbSerialConnect> {
  final WebSerialDmxTransport _transport = WebSerialDmxTransport();
  bool _hasPort = false;
  bool _fromFastPath = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_tryFastPath());
  }

  Future<void> _tryFastPath() async {
    final ready = await _transport.useGrantedPort();
    if (mounted && ready) {
      setState(() {
        _hasPort = true;
        _fromFastPath = true;
      });
    }
  }

  Future<void> _requestPort({bool anyDevice = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = anyDevice
          ? await _transport.requestAnyPort()
          : await _transport.requestPort();
      if (!mounted) return;
      setState(() {
        _hasPort = ok;
        _fromFastPath = false;
        _busy = false;
        if (!ok && !anyDevice) {
          _error = 'No matching USB-DMX device — try "Show all devices".';
        }
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = exception.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _start(DmxtractState state) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.beginOutput(_transport);
    } catch (exception) {
      if (mounted) {
        setState(
          () => _error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(DmxtractState state) async {
    if (state.output != null) await state.stopOutput();
    await _transport.revokeAccess();
    if (mounted) {
      setState(() {
        _hasPort = false;
        _fromFastPath = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final live = state.output == _transport && state.outputActive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect your USB DMX cable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            const Text(
              'Runs from this browser tab. Nothing is installed.',
              style: TextStyle(color: DmxColors.muted),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              ExplanationCallout(
                warning: true,
                title: 'Could not connect',
                body: _error!,
                icon: Icons.error_outline,
              ),
              const SizedBox(height: 14),
            ],
            if (!live) ...[
              if (_hasPort) ...[
                if (_fromFastPath)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Your cable from last time is ready.',
                      style: TextStyle(
                        color: DmxColors.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _start(state),
                  icon: const Icon(Icons.usb_outlined),
                  label: Text(_busy ? 'Starting…' : 'Start at zero'),
                ),
              ] else ...[
                const _ChromePickerPrimingPanel(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _requestPort(),
                      icon: const Icon(Icons.usb_outlined),
                      label: Text(_busy ? 'Choosing…' : 'Choose USB cable'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _requestPort(anyDevice: true),
                      child: const Text('Not listed? Show all devices'),
                    ),
                  ],
                ),
              ],
            ] else
              _WebSerialTransparencyPanel(
                transport: _transport,
                state: state,
                onRevoke: () => _revoke(state),
              ),
          ],
        ),
      ),
    );
  }
}

/// Priming note shown immediately above the button that calls
/// `requestPort()`, so the Chrome device-picker popup that click triggers is
/// never the user's first hint that a system dialog is coming. Collapsed by
/// default to match the compact expandable idiom used elsewhere on this
/// screen (see [_DipCalculator]).
class _ChromePickerPrimingPanel extends StatelessWidget {
  const _ChromePickerPrimingPanel();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'What will Chrome ask?',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chrome opens its own device-picker popup. The cable will not '
              'be called "DMX" — look for something like "FT232R USB UART", '
              '"USB-SERIAL CH340", or "CP2102 USB to UART Bridge". Your '
              'choice is remembered for next time, and you can revoke it '
              'here anytime.',
              style: TextStyle(color: DmxColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const _PrivacyLinkButton(),
          ],
        ),
      ),
    ],
  );
}

/// Compact "Read the privacy page" link, opened the same way every other
/// in-app link to a static page is (see `_FooterLink` in components.dart):
/// a new tab, `noopener,noreferrer`.
class _PrivacyLinkButton extends StatelessWidget {
  const _PrivacyLinkButton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: TextButton(
      onPressed: () =>
          web.window.open('/privacy/', '_blank', 'noopener,noreferrer'),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Read the privacy page'),
    ),
  );
}

class _WebSerialTransparencyPanel extends StatelessWidget {
  const _WebSerialTransparencyPanel({
    required this.transport,
    required this.state,
    required this.onRevoke,
  });
  final WebSerialDmxTransport transport;
  final DmxtractState state;
  final Future<void> Function() onRevoke;

  @override
  Widget build(BuildContext context) {
    final device = transport.device;
    final frame = transport.currentFrame;
    final start = state.startAddress;
    final count = state.mode?.channelIds.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.usb, color: DmxColors.green, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device?.label ?? 'USB cable',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          transport.widgetMode == WidgetMode.buffered
              ? 'Buffered widget protocol (Enttec-compatible)'
              : 'Direct/Open DMX cable — this tab times the signal itself',
          style: const TextStyle(color: DmxColors.muted, fontSize: 13),
        ),
        if (transport.status == TestOutputStatus.blockedHidden) ...[
          const SizedBox(height: 12),
          const ExplanationCallout(
            warning: true,
            title: 'Paused — this tab is hidden',
            body:
                'Output was zeroed and the send loop is paused while this tab is in the background. Come back to this tab to resume.',
            icon: Icons.visibility_off_outlined,
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Live frame · what is being sent right now',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (count == 0)
          const Text('No channels to show yet.')
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var index = 0; index < count; index++)
                _ChannelChip(
                  channel: start + index,
                  value: frame[(start + index - 1).clamp(0, 511)],
                  highlighted: index == state.testChannel,
                ),
            ],
          ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 16, color: DmxColors.muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Nothing was installed — this talks to the USB cable directly from this browser tab.',
                style: TextStyle(color: DmxColors.muted, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRevoke,
          icon: const Icon(Icons.link_off),
          label: const Text('Revoke access'),
        ),
      ],
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.channel,
    required this.value,
    required this.highlighted,
  });
  final int channel;
  final int value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: highlighted ? DmxColors.rustDark : DmxColors.inset,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: highlighted ? DmxColors.amber : DmxColors.border,
      ),
    ),
    child: Text(
      'CH${channel.toString().padLeft(3, '0')}: ${value.toString().padLeft(3, '0')}',
      style: const TextStyle(fontFamily: 'JetBrains Mono', fontSize: 12),
    ),
  );
}

// ---------------------------------------------------------------------------
// Card 2: Network node (Art-Net / sACN) — the existing Bridge flow.
// ---------------------------------------------------------------------------

class _NetworkNodeConnect extends StatelessWidget {
  const _NetworkNodeConnect();

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    return Card(
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
                      const Text(
                        'Uses the DMXtract Bridge helper app, which runs only on this computer.',
                        style: TextStyle(color: DmxColors.muted),
                      ),
                      const SizedBox(height: 6),
                      BridgeConnectionStatus(
                        available: state.bridgeAvailable,
                        active: state.outputActive,
                        label: state.outputLabel,
                      ),
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
            if (!state.bridgeAvailable) ...[
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: ExplanationCallout(
                  title: 'Open the helper app first',
                  body:
                      'Open DMXtract Bridge on this computer, then choose Find bridge. Chrome or Edge may ask to allow local network access; this only reaches the helper on this computer.',
                  icon: Icons.download_outlined,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: _BridgeOsPrimingPanel(),
              ),
            ],
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
    );
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
      if (config == null) return;
      await state.beginOutput(
        BridgeTestOutput(
          state.bridge,
          origin: Uri.base.origin,
          outputConfig: config,
        ),
      );
    } catch (exception) {
      // A 401 from a dead/expired token clears BridgeClient.token (see
      // bridge_client.dart `_post`) — re-check availability so a stale
      // "Connect" button (bridge process gone) falls back to "Find bridge",
      // and a live-but-forgotten-session bridge falls back to re-pairing on
      // the next attempt instead of retrying the same dead token forever.
      if (state.bridge.token == null) {
        unawaited(state.refreshBridgeAvailability());
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(exception.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
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
          title: const Text('Which network protocol?'),
          content: SizedBox(
            width: 500,
            child: RadioGroup<String>(
              groupValue: kind,
              onChanged: (value) => setState(() {
                if (value == null) return;
                kind = value;
                detail.text = value == 'artNet' ? '2.255.255.255' : '';
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile(
                    value: 'artNet',
                    title: Text('Art-Net'),
                    subtitle: Text('Broadcast on the local network'),
                  ),
                  const RadioListTile(
                    value: 'sacn',
                    title: Text('sACN'),
                    subtitle: Text('Multicast, with priority'),
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
                  TextField(
                    controller: detail,
                    decoration: InputDecoration(
                      labelText: kind == 'artNet'
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
                'artNet' => {
                  'kind': 'artNet',
                  'host': detail.text,
                  'port': 6454,
                },
                _ => {
                  'kind': 'sacn',
                  'host': detail.text.isEmpty ? null : detail.text,
                  'port': 5568,
                  'priority': 100,
                },
              }),
              child: const Text('Start at zero'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Priming note for the two OS-level dialogs the Bridge flow can trigger:
/// the OS's own "downloaded from the internet" warning on first run, then
/// the bridge's own pairing approval. Same collapsed-by-default idiom as
/// [_ChromePickerPrimingPanel].
class _BridgeOsPrimingPanel extends StatelessWidget {
  const _BridgeOsPrimingPanel();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text(
      'What will my computer ask?',
      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "First run: your computer may warn that the app came from "
              "the internet — Gatekeeper on macOS, SmartScreen on Windows. "
              "That's your operating system asking whether to trust it, not "
              "DMXtract. Once the bridge is running, it shows its own "
              "pairing approval on this computer with the requesting "
              "site's address — only approve it if that matches where "
              "you're testing from.",
              style: TextStyle(color: DmxColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const _PrivacyLinkButton(),
          ],
        ),
      ),
    ],
  );
}

void _openBridgeControls(DmxtractState state) {
  web.window.open(
    state.bridge.controlsUrl,
    'dmxtract-bridge-controls',
    'noopener,noreferrer',
  );
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
      } else if (status == PairApprovalStatus.expired) {
        _poller?.cancel();
        setState(() => _error = 'That pairing request expired. Ask again.');
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
        onPressed: () => _openBridgeControls(widget.state),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open bridge controls'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Card 3: bring-your-own console/software — placeholder.
// ---------------------------------------------------------------------------

/// Which sub-step of the manual console flow is showing behind card 3.
enum _ManualConsoleStep {
  /// Prompt to download the fixture profile now, since it has to be loaded
  /// into the user's own software before they can patch and test it — the
  /// normal Download step (screens/download_profile.dart) only comes after
  /// Test in the overall flow.
  download,

  /// Short, neutral pick of which software the user is driving from. Only
  /// changes the wording of the instructions in [_ManualConsoleStep.testing]
  /// — every step past this point is manual regardless of the answer.
  software,

  /// The shared checklist + guided tester, in instruction-driven wording.
  /// No [TestOutput] is ever attached for this option, so the browser sends
  /// zero DMX no matter how far the user gets here.
  testing,
}

class _ManualConsoleConnect extends StatefulWidget {
  const _ManualConsoleConnect();
  @override
  State<_ManualConsoleConnect> createState() => _ManualConsoleConnectState();
}

class _ManualConsoleConnectState extends State<_ManualConsoleConnect> {
  _ManualConsoleStep _step = _ManualConsoleStep.download;
  String? _software;

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    return switch (_step) {
      _ManualConsoleStep.download => _ManualDownloadStep(
        onContinue: () => setState(() => _step = _ManualConsoleStep.software),
      ),
      _ManualConsoleStep.software => _ManualSoftwareStep(
        onBack: () => setState(() => _step = _ManualConsoleStep.download),
        onSelect: (software) => setState(() {
          _software = software;
          _step = _ManualConsoleStep.testing;
        }),
      ),
      _ManualConsoleStep.testing => Column(
        children: [
          _ChecklistCard(state: state, hardware: true, manual: true),
          const SizedBox(height: 18),
          ExplanationCallout(
            title: 'Nothing is sent from this browser',
            body:
                'Every value below is something you dial in yourself, in '
                '${_software ?? 'your software'} — this tab never talks to '
                'the light.',
            icon: Icons.wifi_off_outlined,
            trailing: TextButton(
              onPressed: () =>
                  setState(() => _step = _ManualConsoleStep.software),
              child: const Text('Change software'),
            ),
          ),
          const SizedBox(height: 18),
          _GuidedTesterPanel(state: state, softwareLabel: _software),
        ],
      ),
    };
  }
}

class _ManualDownloadStep extends StatelessWidget {
  const _ManualDownloadStep({required this.onContinue});
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final fixture = state.fixture!;
    final base = '${slug(fixture.manufacturer)}-${slug(fixture.model)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.terminal_outlined,
                  color: DmxColors.amber,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'My own lighting software or console',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Load this fixture into your software before testing, so you '
              'can patch its address and dial in values yourself. Download '
              'whichever format it uses.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () async => downloadBytes(
                    '$base.json',
                    'application/json',
                    await exportOflShared(fixture),
                  ),
                  icon: const Icon(Icons.data_object_outlined),
                  label: const Text('Download OFL'),
                ),
                OutlinedButton.icon(
                  onPressed: () async => downloadBytes(
                    '$base.gdtf',
                    'application/zip',
                    await exportGdtfShared(fixture),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Download GDTF'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onContinue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text("I've loaded it — continue"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualSoftwareStep extends StatelessWidget {
  const _ManualSoftwareStep({required this.onSelect, required this.onBack});
  final ValueChanged<String> onSelect;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Which software or console are you using?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'This only changes the wording of the steps below — every value '
            'is still something you set yourself.',
            style: TextStyle(color: DmxColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final option in const ['QLC+', 'Console or other software'])
                OutlinedButton(
                  onPressed: () => onSelect(option),
                  child: Text(option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Back'),
          ),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Card 4: virtual output — no hardware.
// ---------------------------------------------------------------------------

class _VirtualConnect extends StatefulWidget {
  const _VirtualConnect();
  @override
  State<_VirtualConnect> createState() => _VirtualConnectState();
}

class _VirtualConnectState extends State<_VirtualConnect> {
  bool _starting = false;
  String? _error;

  Future<void> _start(DmxtractState state) async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await state.beginOutput(VirtualTestOutput());
    } catch (exception) {
      if (mounted) {
        setState(
          () => _error = exception.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final live = state.outputActive;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Just checking the numbers',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            const Text(
              'No hardware needed. See the channel values and what to expect, without sending real DMX.',
              style: TextStyle(color: DmxColors.muted),
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              ExplanationCallout(
                warning: true,
                title: 'Could not start',
                body: _error!,
                icon: Icons.error_outline,
              ),
              const SizedBox(height: 14),
            ],
            if (!live)
              FilledButton.icon(
                onPressed: _starting ? null : () => _start(state),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(_starting ? 'Starting…' : 'Preview channel values'),
              )
            else
              const ExplanationCallout(
                title: 'Previewing only',
                body:
                    'Nothing is sent to real hardware. Use the slider below to sanity-check what each channel should do.',
                icon: Icons.visibility_outlined,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared: the "before you connect" checklist + guided tester panel. Works
// identically on top of any connected TestOutput (Bridge, Web Serial, or
// virtual) since it only ever talks to DmxtractState.
// ---------------------------------------------------------------------------

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.state,
    required this.hardware,
    this.manual = false,
  });
  final DmxtractState state;
  final bool hardware;

  /// True for card 3 (bring-your-own console/software), where no
  /// [TestOutput] is ever attached and DMXtract cannot enforce a zero-start
  /// on the user's own console the way it does for every transport-backed
  /// path — the checklist has to ask for it explicitly instead.
  final bool manual;

  @override
  Widget build(BuildContext context) {
    final mode = state.mode;
    return Card(
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
            if (hardware && manual) ...[
              const _Check(
                number: 1,
                text:
                    'Bring every fader — and your grand master, if you have one — down to zero before you patch.',
              ),
              const _Check(
                number: 2,
                text: 'Plug in your interface or console.',
              ),
              const _Check(number: 3, text: 'Turn on the light.'),
              _Check(
                number: 4,
                text:
                    'Set the light to ${mode?.shortName.isNotEmpty == true ? mode!.shortName : mode?.name ?? 'the selected mode'}.',
              ),
              _Check(
                number: 5,
                text:
                    'Set its DMX address to ${state.startAddress.toString().padLeft(3, '0')}.',
              ),
            ] else if (hardware) ...[
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
            ] else
              const _Check(
                number: 1,
                text: 'Nothing to plug in — this preview needs no hardware.',
              ),
            const SizedBox(height: 12),
            _StartAddressField(state: state),
            const SizedBox(height: 5),
            _DipCalculator(address: state.startAddress),
          ],
        ),
      ),
    );
  }
}

class _GuidedTesterPanel extends StatelessWidget {
  const _GuidedTesterPanel({required this.state, this.softwareLabel});
  final DmxtractState state;

  /// Non-null only for the manual-console flow (card 3): no [TestOutput] is
  /// attached there, so this reframes the "you should expect" box as an
  /// instruction to dial the channel/value readout above into
  /// [softwareLabel] and asks what was observed, instead of describing a
  /// value this tab already sent.
  final String? softwareLabel;

  @override
  Widget build(BuildContext context) {
    final channel = state.channel;
    final mode = state.mode;
    return Column(
      children: [
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
                        Text(
                          softwareLabel == null
                              ? 'You should expect'
                              : 'Set this in $softwareLabel — did you see:',
                          style: const TextStyle(
                            color: DmxColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                          textAlign: TextAlign.center,
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
      ],
    );
  }
}

String _rangeLabel(DmxChannel channel, int value) =>
    channel.ranges.where((range) => range.contains(value)).firstOrNull?.name ??
    'Value $value';

String _expectation(DmxChannel channel, int value) {
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

String _expectedObservation(DmxChannel channel, int value) {
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
  if (text.contains('pan') || text.contains('tilt') || text.contains('move')) {
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

Future<void> _observe(
  BuildContext context,
  DmxtractState state,
  String observation,
) async {
  final channel = state.channel;
  if (channel == null) return;
  state.markObservation(observation);
  final expected = _expectedObservation(channel, state.testValue);
  if (observation == expected) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Great — that matches $expected.')));
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

Future<void> _changeValue(
  BuildContext context,
  DmxtractState state,
  int value,
) async {
  // Same predicate DmxtractState.sendValue uses (DmxChannel.riskyRangeFor)
  // so the unlock dialog and the send-path gate can never disagree about
  // whether a given value is risky, even with overlapping ranges.
  final range = state.channel?.riskyRangeFor(value);
  if (range != null && !state.riskyUnlocked) {
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
