import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';
import '../app_state.dart';
import '../components.dart';
import '../deployment_theme.dart';
import '../phone_link.dart';
import '../theme.dart';

class AddManualScreen extends StatelessWidget {
  const AddManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
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
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: compact ? 30 : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We’ll look for the DMX table and turn it into something you can check, test, and download.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontSize: compact ? 16 : null),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 18 : 26),
        InkWell(
          onTap: state.busy || state.photos.isNotEmpty
              ? null
              : state.pickManual,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: double.infinity,
            constraints: BoxConstraints(minHeight: compact ? 280 : 320),
            decoration: BoxDecoration(
              color: DeploymentTheme.enabled
                  ? Colors.transparent
                  : DmxColors.panel.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: state.error == null ? DmxColors.rust : DmxColors.red,
                width: 2,
              ),
            ),
            child: DeploymentIronSurface(
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(compact ? 20 : 32),
                child: state.busy
                    ? _Progress(state: state)
                    : state.photos.isNotEmpty
                    ? _PhotoTray(state: state, compact: compact)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DeploymentManualDropMark(compact: compact),
                          SizedBox(height: compact ? 14 : 20),
                          Text(
                            compact
                                ? 'Add photos or a manual'
                                : 'Drop your light’s manual here',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontSize: compact ? 24 : null),
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
                          SizedBox(height: compact ? 16 : 20),
                          if (compact) ...[
                            FilledButton.icon(
                              onPressed: state.pickPhotos,
                              icon: const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Take or add photos'),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: state.pickManual,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Choose PDF or project'),
                            ),
                            if (state.phoneLinkAvailable) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () => _showPhoneLinkDialog(context),
                                icon: const Icon(Icons.qr_code_2_outlined),
                                label: const Text('Send from phone'),
                              ),
                            ],
                          ] else
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: state.pickManual,
                                  icon: const Icon(Icons.folder_open_outlined),
                                  label: const Text('Choose manual'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: state.pickPhotos,
                                  icon: const Icon(Icons.add_a_photo_outlined),
                                  label: const Text('Add several photos'),
                                ),
                                if (state.phoneLinkAvailable)
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _showPhoneLinkDialog(context),
                                    icon: const Icon(Icons.qr_code_2_outlined),
                                    label: const Text('Send from phone'),
                                  ),
                              ],
                            ),
                          SizedBox(height: compact ? 14 : 18),
                          PrivacyPill(compact: compact),
                        ],
                      ),
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
}

class _PhotoTray extends StatelessWidget {
  const _PhotoTray({required this.state, required this.compact});
  final DmxtractState state;
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        '${state.photos.length} ${state.photos.length == 1 ? 'photo' : 'photos'} ready',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontSize: compact ? 24 : null),
      ),
      const SizedBox(height: 6),
      const Text(
        'Put the channel-table pages in the order you want them read.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var index = 0; index < state.photos.length; index++)
            _PhotoTile(
              photo: state.photos[index],
              number: index + 1,
              onRemove: () => state.removePhoto(index),
              onEarlier: index == 0 ? null : () => state.movePhoto(index, -1),
              onLater: index == state.photos.length - 1
                  ? null
                  : () => state.movePhoto(index, 1),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: state.pickPhotos,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add more'),
          ),
          FilledButton.icon(
            onPressed: state.readPhotos,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: Text(
              'Read ${state.photos.length} ${state.photos.length == 1 ? 'photo' : 'photos'}',
            ),
          ),
        ],
      ),
      TextButton(onPressed: state.clearPhotos, child: const Text('Start over')),
      PrivacyPill(compact: compact),
    ],
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.number,
    required this.onRemove,
    required this.onEarlier,
    required this.onLater,
  });
  final ManualPhoto photo;
  final int number;
  final VoidCallback onRemove;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Photo $number: ${photo.name}',
    child: SizedBox(
      width: 92,
      child: Column(
        children: [
          SizedBox(
            width: 92,
            height: 96,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(photo.bytes, fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: DmxColors.amber,
                    foregroundColor: DmxColors.inset,
                    child: Text(
                      '$number',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton.filled(
                    tooltip: 'Remove photo $number',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close, size: 17),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(34, 34),
                      backgroundColor: const Color(0xcc151310),
                      foregroundColor: DmxColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Move photo $number earlier',
                onPressed: onEarlier,
                icon: const Icon(Icons.arrow_back, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Move photo $number later',
                onPressed: onLater,
                icon: const Icon(Icons.arrow_forward, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    ),
  );
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

void _showPhoneLinkDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const _PhoneLinkDialog(),
);

/// Shows the QR code that starts a phone hand-off, and tracks it through to
/// completion. The session (and the RTCPeerConnection it drives in
/// web/phone_link.js) is torn down in [dispose], whether the user closes
/// this dialog, cancels, or the whole hand-off already finished.
class _PhoneLinkDialog extends StatefulWidget {
  const _PhoneLinkDialog();
  @override
  State<_PhoneLinkDialog> createState() => _PhoneLinkDialogState();
}

class _PhoneLinkDialogState extends State<_PhoneLinkDialog> {
  DmxtractState? _state;
  StreamSubscription<PhoneLinkEvent>? _subscription;
  String _statusText = 'Preparing a private link…';
  String? _error;
  bool _connected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state != null) return;
    final state = DmxScope.of(context);
    _state = state;
    state.beginPhoneLink();
    _subscription = state.phoneLinkEvents?.listen(_handleEvent);
  }

  void _handleEvent(PhoneLinkEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case 'waiting':
          _statusText = 'Waiting for your phone to scan…';
        case 'phoneJoined':
          _statusText = 'Connecting…';
        case 'connected':
          _connected = true;
          _statusText = 'Connected — take or choose photos on your phone.';
        case 'closed':
          if (_error == null) _statusText = 'Your phone closed the connection.';
        case 'error':
          _error =
              event.message ?? 'Couldn’t connect the two devices — try again.';
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _state?.endPhoneLink();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final url = state.phoneLinkUrl;
    final photoCount = state.photos.length;
    return AlertDialog(
      title: const Text('Send photos from your phone'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (url != null)
              _QrCode(data: url, size: 208)
            else
              const SizedBox(
                width: 208,
                height: 208,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 16),
            const Text(
              'Scan with your phone’s camera. Photos travel straight to this browser tab and never touch a server.',
              textAlign: TextAlign.center,
              style: TextStyle(color: DmxColors.muted),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DmxColors.red,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: _connected
                        ? const Icon(
                            Icons.check_circle,
                            color: DmxColors.green,
                            size: 16,
                          )
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_statusText)),
                ],
              ),
            if (photoCount > 0) ...[
              const SizedBox(height: 10),
              Text(
                '$photoCount ${photoCount == 1 ? 'photo' : 'photos'} received',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: DmxColors.green,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(photoCount == 0 ? 'Cancel' : 'Done'),
        ),
      ],
    );
  }
}

/// Renders a QR code for [data] with a white quiet zone, using the pure-Dart
/// `qr` encoder — no image assets, no network fetch for the code itself.
class _QrCode extends StatelessWidget {
  const _QrCode({required this.data, required this.size});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final qrCode = QrCode(payload: QrPayload.fromString(data));
    final image = QrImage(qrCode);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final moduleSize = size.width / image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            col * moduleSize,
            row * moduleSize,
            moduleSize,
            moduleSize,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.image.moduleCount != image.moduleCount ||
      !identical(oldDelegate.image, image);
}
