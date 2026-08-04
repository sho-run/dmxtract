import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'bridge_client.dart';
import 'extraction_rules.dart';
import 'gdtf_lookup.dart';
import 'manual_extractor.dart';
import 'model.dart';
import 'project_store.dart';

class ManualPhoto {
  const ManualPhoto({
    required this.bytes,
    required this.name,
    required this.mime,
  });

  final Uint8List bytes;
  final String name;
  final String mime;
}

class _ManualPageSource {
  const _ManualPageSource(this.bytes, this.mime, this.page);
  final Uint8List bytes;
  final String mime;
  final int page;
}

class DmxtractState extends ChangeNotifier {
  DmxtractState({GdtfLookupClient? lookupClient})
    : _lookupClient = lookupClient ?? GdtfLookupClient() {
    _restore();
  }
  final bridge = BridgeClient();
  final GdtfLookupClient _lookupClient;
  FixtureProject? fixture;
  int step = 0;
  int selectedMode = 0;
  int startAddress = 1;
  int testChannel = 0;
  int testValue = 0;
  String? lastObservation;
  bool busy = false;
  bool needsRegion = false;
  bool bridgeAvailable = false;
  bool bridgeChecking = false;
  bool outputActive = false;
  bool riskyUnlocked = false;
  String outputLabel = '';
  String status = '';
  String? error;
  String? manualName;
  int pageCount = 0;
  List<String> thumbnails = [];
  List<String> questions = [];
  List<GdtfProfileMatch> gdtfMatches = [];
  final List<ManualPhoto> photos = [];
  bool gdtfLookupEnabled = false;
  final List<String> _undo = [];
  final List<String> _redo = [];
  Timer? _heartbeat;
  Uint8List? _manualBytes;
  String? _manualMime;
  String _manualText = '';
  List<_ManualPageSource> _pageSources = [];

  FixtureMode? get mode => fixture == null || fixture!.modes.isEmpty
      ? null
      : fixture!.modes[selectedMode.clamp(0, fixture!.modes.length - 1)];
  DmxChannel? get channel {
    final current = mode;
    if (current == null || current.channelIds.isEmpty) return null;
    final id =
        current.channelIds[testChannel.clamp(0, current.channelIds.length - 1)];
    return fixture!.channels.where((item) => item.id == id).firstOrNull;
  }

  int get maxStartAddress =>
      (513 - (mode?.channelIds.length ?? 1)).clamp(1, 512);
  int get outputChannel => (startAddress + testChannel).clamp(1, 512);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> pickManual() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'json'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    await ingest(file.bytes!, file.name, _mime(file.extension));
  }

  Future<void> pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    addPhotos([
      for (final file in result.files)
        if (file.bytes != null)
          ManualPhoto(
            bytes: file.bytes!,
            name: file.name,
            mime: _mime(file.extension),
          ),
    ]);
  }

  void addPhotos(Iterable<ManualPhoto> additions) {
    for (final photo in additions) {
      final duplicate = photos.any(
        (item) =>
            item.name == photo.name && item.bytes.length == photo.bytes.length,
      );
      if (!duplicate) photos.add(photo);
    }
    error = null;
    notifyListeners();
  }

  void removePhoto(int index) {
    if (index < 0 || index >= photos.length) return;
    photos.removeAt(index);
    notifyListeners();
  }

  void movePhoto(int index, int delta) {
    final target = index + delta;
    if (index < 0 ||
        index >= photos.length ||
        target < 0 ||
        target >= photos.length) {
      return;
    }
    final photo = photos.removeAt(index);
    photos.insert(target, photo);
    notifyListeners();
  }

  void clearPhotos() {
    photos.clear();
    notifyListeners();
  }

  Future<void> readPhotos() async {
    if (photos.isEmpty || busy) return;
    busy = true;
    error = null;
    needsRegion = false;
    status =
        'Reading ${photos.length} ${photos.length == 1 ? 'photo' : 'photos'}';
    notifyListeners();
    try {
      final text = <String>[];
      final previewImages = <String>[];
      final sources = <_ManualPageSource>[];
      for (var index = 0; index < photos.length; index++) {
        final photo = photos[index];
        status = 'Reading photo ${index + 1} of ${photos.length}';
        notifyListeners();
        final manual = await extractManual(photo.bytes, photo.mime);
        text.add('=== PHOTO ${index + 1}: ${photo.name} ===\n${manual.text}');
        previewImages.addAll(manual.thumbnails);
        for (var page = 0; page < manual.pageCount; page++) {
          sources.add(_ManualPageSource(photo.bytes, photo.mime, page));
        }
      }
      _manualText = text.join('\n\n');
      manualName = photos.length == 1
          ? photos.first.name
          : '${photos.first.name} and ${photos.length - 1} more photos';
      pageCount = sources.length;
      thumbnails = previewImages;
      _pageSources = sources;
      status = 'Building your fixture';
      notifyListeners();
      final result = fixtureFromManualText(_manualText, manualName!);
      fixture = result.fixture;
      questions = result.questions;
      needsRegion = result.fixture.channels.isEmpty;
      status = needsRegion && result.questions.isNotEmpty
          ? result.questions.first
          : needsRegion
          ? 'We could not find the table'
          : 'Checking for mistakes';
      if (!needsRegion) step = 1;
      photos.clear();
      await _save();
      if (!needsRegion) _queueFixtureLookup();
    } catch (exception) {
      error =
          'We could not read those photos. ${exception.toString().replaceFirst('Exception: ', '')}';
      needsRegion = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> ingest(Uint8List bytes, String name, String mime) async {
    busy = true;
    error = null;
    needsRegion = false;
    manualName = name;
    _manualBytes = bytes;
    _manualMime = mime;
    status = 'Reading the manual';
    notifyListeners();
    try {
      if (name.toLowerCase().endsWith('.dmxtract.json')) {
        fixture = FixtureProject.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
        );
        questions = const [];
        pageCount = 0;
        thumbnails = const [];
        needsRegion = false;
        step = 1;
        status = 'Opened your editable project';
        await _save();
        _queueFixtureLookup();
        return;
      }
      final manual = await extractManual(bytes, mime);
      _manualText = manual.text;
      pageCount = manual.pageCount;
      thumbnails = manual.thumbnails;
      _pageSources = [
        for (var page = 0; page < manual.pageCount; page++)
          _ManualPageSource(bytes, mime, page),
      ];
      status = 'Building your fixture';
      notifyListeners();
      final result = fixtureFromManualText(manual.text, name);
      fixture = result.fixture;
      questions = result.questions;
      needsRegion = result.fixture.channels.isEmpty;
      status = needsRegion && result.questions.isNotEmpty
          ? result.questions.first
          : needsRegion
          ? 'We could not find the table'
          : 'Checking for mistakes';
      if (!needsRegion) step = 1;
      await _save();
      if (!needsRegion) _queueFixtureLookup();
    } catch (exception) {
      error =
          'We could not read that file. ${exception.toString().replaceFirst('Exception: ', '')}';
      needsRegion = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> readSelectedRegion(
    int page,
    double left,
    double top,
    double width,
    double height,
  ) async {
    final source = page >= 0 && page < _pageSources.length
        ? _pageSources[page]
        : null;
    final bytes = source?.bytes ?? _manualBytes;
    final mime = source?.mime ?? _manualMime;
    if (bytes == null || mime == null || manualName == null) return;
    busy = true;
    error = null;
    status = 'Reading the selected table';
    notifyListeners();
    try {
      final regionText = await extractManualRegion(
        bytes,
        mime,
        source?.page ?? page,
        left,
        top,
        width,
        height,
      );
      final result = fixtureFromManualText(
        '$_manualText\n\nChannel value table\n$regionText',
        manualName!,
      );
      fixture = result.fixture;
      questions = result.questions;
      needsRegion = result.fixture.channels.isEmpty;
      if (needsRegion) {
        error =
            'That area did not contain a readable channel table. Try a tighter box around the channel rows.';
      } else {
        step = 1;
        status = 'Checking for mistakes';
        await _save();
        _queueFixtureLookup();
      }
    } catch (exception) {
      error =
          'We could not read that area. ${exception.toString().replaceFirst('Exception: ', '')}';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void goTo(int value) {
    if (value < 0 || value > 3 || value > 0 && fixture == null) return;
    step = value;
    notifyListeners();
  }

  void selectMode(int index) {
    selectedMode = index;
    startAddress = startAddress.clamp(1, maxStartAddress);
    testChannel = 0;
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> nextChannel(int delta) async {
    final count = mode?.channelIds.length ?? 0;
    if (count == 0) return;
    if (outputActive) await bridge.setChannel(outputChannel, 0);
    testChannel = (testChannel + delta).clamp(0, count - 1);
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> setChannel(int index) async {
    if (outputActive) await bridge.setChannel(outputChannel, 0);
    testChannel = index;
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> setStartAddress(int value) async {
    final next = value.clamp(1, maxStartAddress);
    if (next == startAddress) return;
    if (outputActive) await bridge.blackout();
    startAddress = next;
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> setTestValue(int value) async {
    testValue = value.clamp(0, 255);
    notifyListeners();
    if (outputActive) await sendValue(testValue);
  }

  Future<void> sendValue(int value) async {
    final current = channel;
    if (current == null || !outputActive) return;
    final risky = current.ranges
        .where((range) => range.contains(value))
        .any((range) => range.safety != 'normal');
    if (risky && !riskyUnlocked) return;
    try {
      await bridge.setChannel(outputChannel, value, risky: risky);
    } catch (exception) {
      error = '$exception';
      await stopOutput();
    }
  }

  Future<String> requestPair() => bridge.requestPair(Uri.base.origin);

  Future<void> refreshBridgeAvailability() async {
    if (bridgeChecking) return;
    bridgeChecking = true;
    notifyListeners();
    bridgeAvailable = await bridge.isAvailable();
    bridgeChecking = false;
    notifyListeners();
  }

  Future<void> confirmPair(String requestId, String code) =>
      bridge.confirmPair(requestId, code);
  Future<PairApprovalStatus> checkPairApproval(String requestId) =>
      bridge.checkPairApproval(requestId);
  Future<void> beginOutput(Map<String, Object?> config) async {
    outputLabel = await bridge.begin(Uri.base.origin, config);
    outputActive = true;
    riskyUnlocked = false;
    testValue = 0;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => bridge.heartbeat().catchError((_) => stopOutput()),
    );
    notifyListeners();
  }

  Future<void> unlockRisky() async {
    await bridge.unlock();
    riskyUnlocked = true;
    notifyListeners();
  }

  Future<void> stopOutput() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      await bridge.blackout();
      await bridge.end();
    } catch (_) {}
    outputActive = false;
    riskyUnlocked = false;
    testValue = 0;
    notifyListeners();
  }

  void editChannel(
    int index,
    String name,
    String gdtfAttribute,
    String gdtfFeature,
    String kind,
    List<DmxRange> ranges,
  ) {
    final project = fixture;
    if (project == null || index < 0 || index >= project.channels.length) {
      return;
    }
    _record();
    project.channels[index].name = name.trim().isEmpty
        ? project.channels[index].name
        : name.trim();
    project.channels[index].ranges = ranges;
    project.channels[index].gdtfAttribute = gdtfAttribute;
    project.channels[index].gdtfFeature = gdtfFeature;
    project.channels[index].kind = kind;
    project.channels[index].confidence = 1;
    questions.removeWhere((item) => item.contains('channel ${index + 1}'));
    _save();
    notifyListeners();
  }

  void markObservation(String observation) {
    lastObservation = observation;
    notifyListeners();
  }

  Future<void> retestChannel() async {
    if (outputActive) await bridge.setChannel(outputChannel, 0);
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty || fixture == null) return;
    _redo.add(fixture!.encode());
    fixture = FixtureProject.fromJson(
      jsonDecode(_undo.removeLast()) as Map<String, Object?>,
    );
    _save();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty || fixture == null) return;
    _undo.add(fixture!.encode());
    fixture = FixtureProject.fromJson(
      jsonDecode(_redo.removeLast()) as Map<String, Object?>,
    );
    _save();
    notifyListeners();
  }

  void _record() {
    if (fixture != null) {
      _undo.add(fixture!.encode());
      if (_undo.length > 30) _undo.removeAt(0);
      _redo.clear();
    }
  }

  Future<void> _save() async {
    if (fixture == null) return;
    await saveProject(fixture!.encode());
  }

  Future<void> _restore() async {
    final value = await loadProject();
    if (value == null) return;
    try {
      fixture = FixtureProject.fromJson(
        jsonDecode(value) as Map<String, Object?>,
      );
      manualName = fixture!.sourceName;
      status = 'Restored your last local project';
      step = 1;
      _queueFixtureLookup();
      notifyListeners();
    } catch (_) {}
  }

  void _queueFixtureLookup() {
    final project = fixture;
    if (project == null) return;
    final fixtureId = project.id;
    gdtfMatches = const [];
    gdtfLookupEnabled = false;
    unawaited(
      _lookupClient.search(project).then((result) {
        if (fixture?.id != fixtureId) return;
        gdtfMatches = result.matches;
        gdtfLookupEnabled = result.enabled;
        notifyListeners();
      }),
    );
  }

  String _mime(String? extension) => extension?.toLowerCase() == 'pdf'
      ? 'application/pdf'
      : extension?.toLowerCase() == 'json'
      ? 'application/json'
      : extension?.toLowerCase() == 'png'
      ? 'image/png'
      : extension?.toLowerCase() == 'webp'
      ? 'image/webp'
      : 'image/jpeg';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
