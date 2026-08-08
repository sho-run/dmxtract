import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'bridge_client.dart';
import 'extraction_rules.dart';
import 'gdtf_lookup.dart';
import 'manual_extractor.dart';
import 'model.dart';
import 'phone_link.dart';
import 'project_store.dart';
import 'test_output.dart';

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
  const _ManualPageSource(
    this.bytes,
    this.mime,
    this.page, [
    this.rotation = 0,
  ]);
  final Uint8List bytes;
  final String mime;
  final int page;

  /// The rotation [extractManual] applied to this page before OCR (see
  /// [ExtractedManual.rotations]) — always 0 for PDFs. Kept alongside the
  /// raw bytes so a region re-read renders its source in the same frame as
  /// the thumbnail the user drew the box on.
  final int rotation;
}

class DmxtractState extends ChangeNotifier {
  DmxtractState({GdtfLookupClient? lookupClient, http.Client? httpClient})
    : _lookupClient = lookupClient ?? GdtfLookupClient(),
      _httpClient = httpClient ?? http.Client() {
    _restore();
    unawaited(_checkPhoneLinkAvailability());
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

  /// The live DMX transport backing the current Test-step session — a
  /// [BridgeTestOutput], `WebSerialDmxTransport`, or [VirtualTestOutput],
  /// chosen behind the "How is your light connected?" chooser in
  /// screens/test_light.dart. Null when no session is active.
  TestOutput? output;
  StreamSubscription<TestOutputStatus>? _outputStatusSub;

  /// Fallback risky-unlock acknowledgement for [TestConnectionOption.
  /// manualConsoleTest], where [output] deliberately stays null (see
  /// screens/test_light.dart) so there is no transport to hold
  /// `TestOutput.riskyUnlocked` for us. Ignored whenever [output] is
  /// non-null — see [riskyUnlocked].
  bool _riskyAcknowledged = false;
  String status = '';
  String? error;
  String? manualName;
  int pageCount = 0;
  List<String> thumbnails = [];
  List<String> questions = [];
  List<GdtfProfileMatch> gdtfMatches = [];
  final List<ManualPhoto> photos = [];
  bool gdtfLookupEnabled = false;
  bool phoneLinkAvailable = false;
  String? phoneLinkUrl;
  final List<String> _undo = [];
  final List<String> _redo = [];
  Uint8List? _manualBytes;
  String? _manualMime;
  String _manualText = '';
  List<_ManualPageSource> _pageSources = [];
  final http.Client _httpClient;
  PhoneLinkSession? _phoneLinkSession;
  StreamSubscription<ReceivedPhoto>? _phoneLinkPhotoSub;

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

  /// True once [beginOutput] has resolved on the current [output] and
  /// [stopOutput] has not yet been called. Mirrors `TestOutput.isActive`
  /// (also true while a Web Serial session is [TestOutputStatus.blockedHidden]).
  bool get outputActive => output?.isActive ?? false;

  /// True once [unlockRisky] has been called for the current [output]
  /// session — or, when no transport is attached (the manual-console
  /// flow), once it has been called at all for this app session; see
  /// [_riskyAcknowledged].
  bool get riskyUnlocked => output?.riskyUnlocked ?? _riskyAcknowledged;

  /// Human-readable description of the connected device/output, once
  /// [beginOutput] has resolved. Empty when no session is active.
  String get outputLabel => output?.device?.label ?? '';

  /// Live connectivity state of [output]. [TestOutputStatus.disconnected]
  /// when no session is active.
  TestOutputStatus get outputStatus =>
      output?.status ?? TestOutputStatus.disconnected;

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
          final rotation = page < manual.rotations.length
              ? manual.rotations[page]
              : 0;
          sources.add(
            _ManualPageSource(photo.bytes, photo.mime, page, rotation),
          );
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
          _ManualPageSource(
            bytes,
            mime,
            page,
            page < manual.rotations.length ? manual.rotations[page] : 0,
          ),
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
        source?.rotation ?? 0,
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
    if (outputActive) await output!.setChannel(outputChannel, 0);
    testChannel = (testChannel + delta).clamp(0, count - 1);
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> setChannel(int index) async {
    if (outputActive) await output!.setChannel(outputChannel, 0);
    testChannel = index;
    testValue = 0;
    lastObservation = null;
    notifyListeners();
  }

  Future<void> setStartAddress(int value) async {
    final next = value.clamp(1, maxStartAddress);
    if (next == startAddress) return;
    if (outputActive) await output!.blackout();
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
    final activeOutput = output;
    if (current == null || activeOutput == null || !activeOutput.isActive) {
      return;
    }
    final risky = current.isRisky(value);
    if (risky && !activeOutput.riskyUnlocked) {
      // Fail loud rather than silently dropping the write: the UI already
      // gates risky values behind an unlock dialog using the same
      // DmxChannel.isRisky check, so reaching this branch means a caller
      // bypassed that gate — surface it instead of leaving the readout
      // showing a value that was never actually sent.
      error = 'That value is in a risky range and has not been unlocked.';
      notifyListeners();
      return;
    }
    try {
      await activeOutput.setChannel(outputChannel, value, risky: risky);
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

  /// Starts a live test session on [newOutput] — any [TestOutput]
  /// implementation (Bridge, Web Serial, or the browser-local virtual
  /// output) chosen behind the connection chooser in screens/test_light.dart.
  /// Ends whatever session was previously active first, so switching
  /// connection types never leaves two transports live at once. Rethrows on
  /// failure; [output] is left null so [outputActive] stays false.
  Future<void> beginOutput(TestOutput newOutput) async {
    if (output != null) await stopOutput();
    output = newOutput;
    unawaited(_outputStatusSub?.cancel());
    _outputStatusSub = newOutput.statusChanges.listen((_) => notifyListeners());
    testValue = 0;
    notifyListeners();
    try {
      await newOutput.begin();
    } catch (exception) {
      unawaited(_outputStatusSub?.cancel());
      _outputStatusSub = null;
      output = null;
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> unlockRisky() async {
    await output?.unlock();
    _riskyAcknowledged = true;
    notifyListeners();
  }

  /// Zeros every channel and releases the current transport (see
  /// `TestOutput.end`). Safe to call even when no session is active, and
  /// safe to call from a widget's `dispose()` without awaiting — [output] is
  /// cleared synchronously so the UI reflects "not active" immediately,
  /// while the actual blackout still runs to completion in the background.
  ///
  /// Callable regardless of [outputActive]: a Web Serial session that has
  /// gone [TestOutputStatus.disconnected] still holds a live port, document
  /// listeners, and a reconnect listener that only `TestOutput.end` releases
  /// — callers must not gate this on `outputActive`, only on `output`.
  Future<void> stopOutput() async {
    final activeOutput = output;
    output = null;
    unawaited(_outputStatusSub?.cancel());
    _outputStatusSub = null;
    testValue = 0;
    _riskyAcknowledged = false;
    notifyListeners();
    if (activeOutput == null) return;
    try {
      await activeOutput.end();
    } catch (_) {}
  }

  /// Same as [stopOutput], for use from a widget's `dispose()`. Flutter's
  /// `BuildOwner.finalizeTree` runs `dispose()` with the build lock held;
  /// calling [notifyListeners] synchronously in that window makes
  /// `InheritedNotifier` (see `DmxScope`) call `markNeedsBuild()` on a
  /// locked tree, which throws. Deferring the notification to a microtask
  /// avoids that — by the time it runs, the lock is guaranteed to have been
  /// released, since `finalizeTree`/`buildScope` never yield to the
  /// microtask queue mid-lock.
  Future<void> stopOutputForDispose() async {
    final activeOutput = output;
    output = null;
    unawaited(_outputStatusSub?.cancel());
    _outputStatusSub = null;
    testValue = 0;
    _riskyAcknowledged = false;
    scheduleMicrotask(notifyListeners);
    if (activeOutput == null) return;
    try {
      await activeOutput.end();
    } catch (_) {}
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

  /// Updates the fixture's manufacturer/model, e.g. from the pencil
  /// affordance on the Check step's fixture-name header card. Blank fields
  /// leave the corresponding value untouched (the editor prefills known
  /// names and only leaves a field blank for an "Unknown…" placeholder, so a
  /// blank submission just means the user didn't fill it in). Clears the
  /// matching "could not find the maker/model name" help item once the
  /// value no longer starts with "Unknown", same as [editChannel] clearing
  /// its own channel question.
  void editFixtureName(String manufacturer, String model) {
    final project = fixture;
    if (project == null) return;
    final trimmedManufacturer = manufacturer.trim();
    final trimmedModel = model.trim();
    if (trimmedManufacturer.isEmpty && trimmedModel.isEmpty) return;
    _record();
    if (trimmedManufacturer.isNotEmpty) {
      project.manufacturer = trimmedManufacturer;
    }
    if (trimmedModel.isNotEmpty) project.model = trimmedModel;
    if (!project.manufacturer.startsWith('Unknown')) {
      questions.removeWhere(
        (item) => item == 'We could not find the maker name.',
      );
    }
    if (!project.model.startsWith('Unknown')) {
      questions.removeWhere(
        (item) => item == 'We could not find the model name.',
      );
    }
    _save();
    notifyListeners();
  }

  void markObservation(String observation) {
    lastObservation = observation;
    notifyListeners();
  }

  Future<void> retestChannel() async {
    if (outputActive) await output!.setChannel(outputChannel, 0);
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

  /// Status updates for an in-progress phone hand-off, or null when no
  /// session is active. See [beginPhoneLink].
  Stream<PhoneLinkEvent>? get phoneLinkEvents => _phoneLinkSession?.events;

  Future<void> _checkPhoneLinkAvailability() async {
    if (!phoneLinkBrowserSupported()) return;
    try {
      final response = await _httpClient
          .get(Uri.base.resolve('/api/phone-link-signal'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return;
      final body = jsonDecode(response.body) as Map<String, Object?>;
      phoneLinkAvailable = body['available'] == true;
      notifyListeners();
    } catch (_) {
      // Offline, self-hosted without the signaling function, or blocked by
      // a network policy: the QR affordance simply stays hidden.
    }
  }

  /// Generates a fresh session id and AES-GCM key (never sent anywhere but
  /// embedded in [phoneLinkUrl]'s fragment) and starts listening for a phone
  /// to connect. Received photos flow through [receivePhoneLinkPhoto], the
  /// same path as photos picked with the file picker.
  void beginPhoneLink() {
    if (!phoneLinkAvailable || _phoneLinkSession != null) return;
    final sessionId = randomBase64UrlToken(12);
    final key = randomBase64UrlToken(16);
    // Trailing slash matters: the stricter phone-page Content-Security-Policy
    // in web/_headers and netlify.toml is scoped to "/phone/*", and the
    // static page's own relative asset references (phone.js, ../favicon.png)
    // assume "/phone/" is the current directory. A bare "/phone" would get
    // neither right.
    phoneLinkUrl = '${Uri.base.origin}/phone/#$sessionId.$key';
    final session = startPhoneLinkSession(
      sessionId: sessionId,
      keyBase64Url: key,
    );
    _phoneLinkSession = session;
    _phoneLinkPhotoSub = session.photos.listen(receivePhoneLinkPhoto);
    notifyListeners();
  }

  /// Called for every photo the phone sends over the WebRTC data channel.
  /// This funnels into the same [addPhotos] the "Add several photos" file
  /// picker uses, so dedup, ordering, and the review tray behave identically
  /// regardless of where a photo came from.
  void receivePhoneLinkPhoto(ReceivedPhoto photo) {
    addPhotos([
      ManualPhoto(bytes: photo.bytes, name: photo.name, mime: photo.mime),
    ]);
  }

  void endPhoneLink() {
    unawaited(_phoneLinkPhotoSub?.cancel());
    _phoneLinkPhotoSub = null;
    _phoneLinkSession?.stop();
    _phoneLinkSession = null;
    phoneLinkUrl = null;
    notifyListeners();
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
