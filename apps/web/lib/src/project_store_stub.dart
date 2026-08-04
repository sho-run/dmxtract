import 'package:shared_preferences/shared_preferences.dart';

const _autosaveKey = 'dmxtract.autosave.v1';

Future<void> saveProject(String value) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_autosaveKey, value);
}

Future<String?> loadProject() async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getString(_autosaveKey);
}
