import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../components.dart';
import '../theme.dart';

class AddManualScreen extends StatefulWidget {
  const AddManualScreen({super.key});

  @override
  State<AddManualScreen> createState() => _AddManualScreenState();
}

class _AddManualScreenState extends State<AddManualScreen> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add your light’s manual',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 10),
              Text(
                'We’ll look for the DMX table and turn it into something you can check, test, and download.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        DropTarget(
          onDragEntered: (_) {
            if (!state.busy) setState(() => _dragging = true);
          },
          onDragExited: (_) {
            if (_dragging) setState(() => _dragging = false);
          },
          onDragDone: (details) async {
            if (_dragging) setState(() => _dragging = false);
            if (state.busy) return;
            if (details.files.isEmpty) return;
            final file = details.files.first;
            final Uint8List bytes = await file.readAsBytes();
            await state.ingest(
              bytes,
              file.name,
              file.mimeType ?? _mime(file.name),
            );
          },
          child: InkWell(
            onTap: state.busy ? null : state.pickManual,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 320),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _dragging
                    ? DmxColors.amber.withValues(alpha: .13)
                    : DmxColors.panel.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _dragging
                      ? DmxColors.amber
                      : state.error == null
                      ? DmxColors.rust
                      : DmxColors.red,
                  width: _dragging ? 3 : 2,
                ),
                boxShadow: _dragging
                    ? [
                        BoxShadow(
                          color: DmxColors.amber.withValues(alpha: .18),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: state.busy
                  ? _Progress(state: state)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: DmxColors.rust.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.file_download_outlined,
                            size: 38,
                            color: DmxColors.amber,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _dragging
                              ? 'Let go to add this file'
                              : 'Drop your light’s manual here',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'PDF, screenshot, or phone photo',
                          style: TextStyle(
                            fontSize: 17,
                            color: DmxColors.muted,
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'You can also reopen a .dmxtract.json project.',
                          style: TextStyle(color: DmxColors.muted),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: state.pickManual,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('Choose manual'),
                        ),
                        const SizedBox(height: 18),
                        const PrivacyPill(),
                      ],
                    ),
            ),
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ExplanationCallout(
              title: 'That did not work',
              body: state.error!,
              icon: Icons.error_outline,
              warning: true,
            ),
          ),
        if (state.needsRegion)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.status,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'If this fixture does use DMX, take a close screenshot of its channel table and choose it here.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    OutlinedButton.icon(
                      onPressed: () async {
                        if (state.thumbnails.isEmpty) {
                          await state.pickManual();
                          return;
                        }
                        final selection = await _selectTableRegion(
                          context,
                          state.thumbnails,
                        );
                        if (selection == null) return;
                        await state.readSelectedRegion(
                          selection.page,
                          selection.rect.left,
                          selection.rect.top,
                          selection.rect.width,
                          selection.rect.height,
                        );
                      },
                      icon: const Icon(Icons.crop_outlined),
                      label: const Text('Draw a box around it'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _mime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

Future<({int page, Rect rect})?> _selectTableRegion(
  BuildContext context,
  List<String> thumbnails,
) {
  var page = 0;
  Offset? start;
  Offset? end;
  var imageSize = Size.zero;
  return showDialog<({int page, Rect rect})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Draw a box around the DMX table'),
        content: SizedBox(
          width: 620,
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: page == 0
                        ? null
                        : () => setState(() {
                            page--;
                            start = end = null;
                          }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      'Page ${page + 1} of ${thumbnails.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'JetBrains Mono'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: page == thumbnails.length - 1
                        ? null
                        : () => setState(() {
                            page++;
                            start = end = null;
                          }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Drag from one corner of the channel rows to the opposite corner.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    imageSize = size;
                    Offset bounded(Offset value) => Offset(
                      value.dx.clamp(0, size.width),
                      value.dy.clamp(0, size.height),
                    );
                    final box = start == null || end == null
                        ? null
                        : Rect.fromPoints(start!, end!);
                    return GestureDetector(
                      onPanStart: (details) => setState(() {
                        start = bounded(details.localPosition);
                        end = start;
                      }),
                      onPanUpdate: (details) =>
                          setState(() => end = bounded(details.localPosition)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: DmxColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.network(
                                thumbnails[page],
                                fit: BoxFit.fill,
                              ),
                            ),
                          ),
                          if (box != null)
                            Positioned.fromRect(
                              rect: box,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: DmxColors.amber.withValues(alpha: .14),
                                  border: Border.all(
                                    color: DmxColors.amber,
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: start == null || end == null
                ? null
                : () {
                    final raw = Rect.fromPoints(start!, end!);
                    if (raw.width < 12 ||
                        raw.height < 12 ||
                        imageSize.isEmpty) {
                      return;
                    }
                    Navigator.pop(context, (
                      page: page + 1,
                      rect: Rect.fromLTWH(
                        (raw.left / imageSize.width).clamp(0, 1),
                        (raw.top / imageSize.height).clamp(0, 1),
                        (raw.width / imageSize.width).clamp(0, 1),
                        (raw.height / imageSize.height).clamp(0, 1),
                      ),
                    ));
                  },
            child: const Text('Read this area'),
          ),
        ],
      ),
    ),
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});
  final DmxtractState state;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(
        width: 56,
        height: 56,
        child: CircularProgressIndicator(
          strokeWidth: 5,
          color: DmxColors.amber,
        ),
      ),
      const SizedBox(height: 22),
      Text(state.status, style: Theme.of(context).textTheme.titleLarge),
      if (state.manualName != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            state.manualName!,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              color: DmxColors.muted,
            ),
          ),
        ),
      const SizedBox(height: 18),
      const Wrap(
        spacing: 18,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _Stage('Reading the manual'),
          _Stage('Looking for DMX tables'),
          _Stage('Building your fixture'),
          _Stage('Checking for mistakes'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'Scanned manuals take longer because every page is read locally.',
        style: TextStyle(color: DmxColors.muted),
      ),
    ],
  );
}

class _Stage extends StatelessWidget {
  const _Stage(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.circle, size: 7, color: DmxColors.amber),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: DmxColors.muted)),
    ],
  );
}
