import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'app_state.dart';
import 'deployment_theme.dart';
import 'theme.dart';

class DmxScope extends InheritedNotifier<DmxtractState> {
  const DmxScope({
    super.key,
    required DmxtractState state,
    required super.child,
  }) : super(notifier: state);
  static DmxtractState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DmxScope>()!.notifier!;
}

class BeginnerPageShell extends StatefulWidget {
  const BeginnerPageShell({super.key, required this.child});
  final Widget child;

  @override
  State<BeginnerPageShell> createState() => _BeginnerPageShellState();
}

class _BeginnerPageShellState extends State<BeginnerPageShell> {
  bool _manualHovering = false;

  void _setManualHovering(bool value) {
    if (_manualHovering == value || !mounted) return;
    setState(() => _manualHovering = value);
  }

  Future<void> _ingestDrop(DropDoneDetails details, DmxtractState state) async {
    _setManualHovering(false);
    if (state.busy || state.step != 0 || details.files.isEmpty) return;

    final droppedPhotos = <ManualPhoto>[];
    for (final file in details.files) {
      final mime = file.mimeType ?? _manualMime(file.name);
      if (!mime.startsWith('image/')) continue;
      droppedPhotos.add(
        ManualPhoto(
          bytes: await file.readAsBytes(),
          name: file.name,
          mime: mime,
        ),
      );
    }
    if (droppedPhotos.length > 1 || state.photos.isNotEmpty) {
      state.addPhotos(droppedPhotos);
      return;
    }

    final file = details.files.first;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await state.ingest(
      bytes,
      file.name,
      file.mimeType ?? _manualMime(file.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final canDropManual = state.step == 0 && !state.busy;
    if (!canDropManual && _manualHovering) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setManualHovering(false);
      });
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final animationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return DropTarget(
      enable: canDropManual,
      onDragEntered: (_) => _setManualHovering(true),
      onDragExited: (_) => _setManualHovering(false),
      onDragDone: (details) => _ingestDrop(details, state),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: DmxColors.canvas,
              image: DeploymentTheme.background,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff2b2520),
                  DmxColors.canvas,
                  Color(0xff1a1714),
                ],
                stops: [0, .48, 1],
              ),
            ),
            child: ColoredBox(
              color: compact ? const Color(0x660d0806) : Colors.transparent,
              child: Scaffold(
                body: SafeArea(
                  child: SelectionArea(
                    child: Column(
                      children: [
                        _Header(state: state, compact: compact),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 16 : 24,
                              compact ? 10 : 18,
                              compact ? 16 : 24,
                              compact ? 28 : 48,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1080),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  StepIndicator(
                                    step: state.step,
                                    onSelected: state.goTo,
                                  ),
                                  SizedBox(height: compact ? 20 : 32),
                                  widget.child,
                                ],
                              ),
                            ),
                          ),
                        ),
                        _Footer(compact: compact),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: ExcludeSemantics(
              excluding: !_manualHovering,
              child: AnimatedOpacity(
                opacity: _manualHovering ? 1 : 0,
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _manualHovering ? 1 : .985,
                  duration: animationDuration,
                  curve: Curves.easeOutCubic,
                  child: const _ManualDropReadyOverlay(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _manualMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

class _ManualDropReadyOverlay extends StatelessWidget {
  const _ManualDropReadyOverlay();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Drop to read this manual',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: DmxColors.canvas.withValues(alpha: .82),
        border: Border.all(color: DmxColors.amber, width: 3),
        boxShadow: [
          BoxShadow(
            color: DmxColors.amber.withValues(alpha: .2),
            blurRadius: 36,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(28),
          padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 34),
          decoration: BoxDecoration(
            color: DmxColors.ironRaised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DmxColors.rust, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0xcc000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DeploymentManualDropMark(large: true),
              const SizedBox(height: 20),
              Text(
                'Drop to read this manual',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'PDF, screenshot, phone photo, or editable project',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, color: DmxColors.muted),
              ),
              const SizedBox(height: 20),
              const PrivacyPill(compact: true),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.compact});
  final DmxtractState state;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: DeploymentTheme.enabled
          ? Colors.transparent
          : const Color(0xf2252321),
      border: const Border(
        bottom: BorderSide(color: DmxColors.rust, width: 1.5),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0xaa000000),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: DeploymentIronSurface(
      borderRadius: BorderRadius.zero,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 28,
          vertical: compact ? 10 : 18,
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => state.goTo(0),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(
                        text: 'dmx',
                        style: TextStyle(color: DmxColors.teal),
                      ),
                      TextSpan(
                        text: 'tract',
                        style: TextStyle(color: DmxColors.amber),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontFamily: 'Comfortaa',
                    fontSize: compact ? 22 : 25,
                    fontWeight: FontWeight.w700,
                    color: DmxColors.text,
                  ),
                ),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 18),
              const Expanded(
                child: Text(
                  'Build a fixture profile from the manual you already have.',
                  style: TextStyle(color: DmxColors.muted),
                ),
              ),
            ] else
              const Spacer(),
            IconButton(
              onPressed: state.canUndo ? state.undo : null,
              tooltip: 'Undo last edit',
              icon: const Icon(Icons.undo_outlined),
            ),
            IconButton(
              onPressed: state.canRedo ? state.redo : null,
              tooltip: 'Redo edit',
              icon: const Icon(Icons.redo_outlined),
            ),
          ],
        ),
      ),
    ),
  );
}

class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.step,
    required this.onSelected,
  });
  final int step;
  final ValueChanged<int> onSelected;
  static const labels = ['Add manual', 'Check', 'Test', 'Download'];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 660;
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Step ${step + 1} of ${labels.length}',
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                    color: DmxColors.amber,
                  ),
                ),
                const Spacer(),
                Text(
                  labels[step],
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (step + 1) / labels.length,
                minHeight: 5,
              ),
            ),
          ],
        );
      }
      return Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Expanded(
              child: Semantics(
                selected: index == step,
                button: index <= step,
                label: 'Step ${index + 1}: ${labels[index]}',
                child: InkWell(
                  onTap: index <= step ? () => onSelected(index) : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: compact
                        ? _StepDot(
                            index: index,
                            selected: index == step,
                            done: index < step,
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _StepDot(
                                index: index,
                                selected: index == step,
                                done: index < step,
                              ),
                              const SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  labels[index],
                                  style: TextStyle(
                                    color: index == step
                                        ? DmxColors.text
                                        : DmxColors.muted,
                                    fontWeight: index == step
                                        ? FontWeight.w800
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (index < labels.length - 1)
              Container(
                width: compact ? 10 : 28,
                height: 1,
                color: index < step ? DmxColors.amber : DmxColors.border,
              ),
          ],
        ],
      );
    },
  );
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.selected,
    required this.done,
  });
  final int index;
  final bool selected;
  final bool done;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected || done ? DmxColors.amber : DmxColors.inset,
      border: Border.all(
        color: selected || done ? DmxColors.bezel : DmxColors.border,
        width: 2,
      ),
    ),
    child: done
        ? const Icon(Icons.check, size: 18, color: DmxColors.inset)
        : Text(
            '${index + 1}',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? DmxColors.inset : DmxColors.muted,
            ),
          ),
  );
}

class PrivacyPill extends StatelessWidget {
  const PrivacyPill({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0x261fd4c4),
      borderRadius: BorderRadius.all(Radius.circular(99)),
      border: Border.fromBorderSide(BorderSide(color: Color(0x661fd4c4))),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 7,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, color: DmxColors.teal, size: 17),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              compact ? 'Private on this phone' : 'Stays on this device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DmxColors.teal,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class BetaPill extends StatelessWidget {
  const BetaPill({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Color(0x26e8a33d),
      borderRadius: BorderRadius.all(Radius.circular(99)),
      border: Border.fromBorderSide(BorderSide(color: Color(0x66e8a33d))),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Text(
        'Beta',
        style: TextStyle(
          color: DmxColors.amber,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class ExplanationCallout extends StatelessWidget {
  const ExplanationCallout({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.lightbulb_outline,
    this.warning = false,
    this.trailing,
  });
  final String title;
  final String body;
  final IconData icon;
  final bool warning;

  /// Optional action shown at the end of the row (e.g. a `TextButton` to
  /// revisit a choice this callout is explaining the consequence of).
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final color = warning ? DmxColors.amber : DmxColors.bezel;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: DmxColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(body),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class ConfidenceMarker extends StatelessWidget {
  const ConfidenceMarker({super.key, required this.score});
  final double score;
  @override
  Widget build(BuildContext context) {
    final uncertain = score < .65;
    return Tooltip(
      message: uncertain ? 'Please check this' : 'Found clearly in the manual',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: (uncertain ? DmxColors.amber : DmxColors.green).withValues(
            alpha: .13,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          uncertain ? 'Check' : 'Found',
          style: TextStyle(
            color: uncertain ? DmxColors.amber : DmxColors.green,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class FixtureSummaryCard extends StatelessWidget {
  const FixtureSummaryCard({
    super.key,
    required this.manufacturer,
    required this.model,
    required this.modes,
    required this.controls,
  });
  final String manufacturer;
  final String model;
  final int modes;
  final int controls;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: DmxColors.rust.withValues(alpha: .22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DmxColors.rustDark),
            ),
            child: const Icon(
              Icons.moving_outlined,
              color: DmxColors.amber,
              size: 29,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$manufacturer $model',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '$modes ${modes == 1 ? 'mode' : 'modes'} · $controls controls',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class DmxReadout extends StatelessWidget {
  const DmxReadout({super.key, required this.channel, required this.value});
  final int channel;
  final int value;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _Readout(label: 'CHANNEL', value: channel.toString().padLeft(3, '0')),
      const SizedBox(width: 18),
      _Readout(label: 'VALUE', value: value.toString().padLeft(3, '0')),
    ],
  );
}

class _Readout extends StatelessWidget {
  const _Readout({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    width: 142,
    padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
    decoration: BoxDecoration(
      color: DmxColors.inset,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xff5f4919)),
      boxShadow: const [BoxShadow(color: Color(0x33ffab00), blurRadius: 14)],
    ),
    child: Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 10,
            letterSpacing: 1.5,
            color: DmxColors.muted,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'DSEG7',
            fontSize: 38,
            color: DmxColors.amber,
            height: 1.1,
          ),
        ),
      ],
    ),
  );
}

class BridgeConnectionStatus extends StatelessWidget {
  const BridgeConnectionStatus({
    super.key,
    required this.available,
    this.active = false,
    this.label = '',
  });
  final bool available;
  final bool active;
  final String label;
  @override
  Widget build(BuildContext context) {
    final color = active
        ? DmxColors.green
        : available
        ? DmxColors.amber
        : DmxColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          active ? Icons.usb_outlined : Icons.circle,
          size: active ? 19 : 10,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          active
              ? label
              : available
              ? 'Bridge found on this Mac'
              : 'Bridge not running',
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class AdvancedDisclosurePanel extends StatelessWidget {
  const AdvancedDisclosurePanel({
    super.key,
    required this.title,
    required this.child,
  });
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      children: [child],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.compact});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 28,
      vertical: compact ? 6 : 16,
    ),
    decoration: const BoxDecoration(
      color: Color(0xf2252321),
      border: Border(top: BorderSide(color: DmxColors.rustDark, width: 1.5)),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: compact ? 8 : 18,
      runSpacing: compact ? 0 : 8,
      children: [
        _FooterLink(
          label: 'GitHub',
          url: 'https://github.com/sho-run/dmxtract',
          compact: compact,
        ),
        _FooterLink(label: 'Privacy', url: '/privacy/', compact: compact),
        _FooterLink(label: 'About', url: '/about/', compact: compact),
        if (!compact)
          const Text(
            'Open source by',
            style: TextStyle(color: DmxColors.muted),
          ),
        _ShoRunFooterLink(compact: compact),
      ],
    ),
  );
}

class _ShoRunFooterLink extends StatelessWidget {
  const _ShoRunFooterLink({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: compact ? 'Open source by sho.run' : 'sho.run',
    link: true,
    child: TextButton(
      onPressed: () =>
          web.window.open('https://sho.run/', '_blank', 'noopener,noreferrer'),
      style: TextButton.styleFrom(
        minimumSize: Size(44, compact ? 36 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: [
              if (compact)
                const TextSpan(
                  text: 'By ',
                  style: TextStyle(color: DmxColors.muted),
                ),
              const TextSpan(
                text: 'sho',
                style: TextStyle(color: Color(0xffffab00)),
              ),
              const TextSpan(
                text: '.',
                style: TextStyle(color: Color(0xffffc94a)),
              ),
              const TextSpan(
                text: 'run',
                style: TextStyle(color: Color(0xff1fd4c4)),
              ),
            ],
          ),
          style: const TextStyle(
            fontFamily: 'Comfortaa',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.url,
    required this.compact,
  });
  final String label;
  final String url;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    link: true,
    child: TextButton(
      onPressed: () => web.window.open(url, '_blank', 'noopener,noreferrer'),
      style: TextButton.styleFrom(
        foregroundColor: DmxColors.muted,
        minimumSize: Size(44, compact ? 36 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      child: ExcludeSemantics(
        child: Text(label, style: const TextStyle(color: DmxColors.muted)),
      ),
    ),
  );
}
