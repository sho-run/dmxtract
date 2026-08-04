import 'package:idb_shim/idb_browser.dart';

const _databaseName = 'dmxtract';
const _storeName = 'projects';
const _autosaveKey = 'autosave-v1';

Future<Database> _open() => idbFactoryBrowser.open(
  _databaseName,
  version: 1,
  onUpgradeNeeded: (event) {
    if (!event.database.objectStoreNames.contains(_storeName)) {
      event.database.createObjectStore(_storeName);
    }
  },
);

Future<void> saveProject(String value) async {
  final database = await _open();
  final transaction = database.transaction(_storeName, idbModeReadWrite);
  await transaction.objectStore(_storeName).put(value, _autosaveKey);
  await transaction.completed;
  database.close();
}

Future<String?> loadProject() async {
  final database = await _open();
  final transaction = database.transaction(_storeName, idbModeReadOnly);
  final value = await transaction
      .objectStore(_storeName)
      .getObject(_autosaveKey);
  await transaction.completed;
  database.close();
  return value as String?;
}
