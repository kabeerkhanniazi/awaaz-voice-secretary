import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/demo_config.dart';
import '../models/availability.dart';
import '../models/call_record_model.dart';
import '../models/secretary_task_model.dart';
import '../models/contact_model.dart';

class StorageService {
  static const String _keyCallLogs = 'awaaz_call_logs';
  static const String _keyTasks = 'awaaz_tasks';
  static const String _keyContacts = 'awaaz_contacts';
  static const String _keyApiKey = 'awaaz_assemblyai_api_key';
  static const String _keyMasterName = 'awaaz_master_name';
  static const String _keyGatewayUrl = 'awaaz_gateway_url';
  static const String _keyGatewaySecret = 'awaaz_gateway_secret';

  static const String _liveGatewayUrl = 'wss://aivs.up.railway.app';
  // The demo build points at the demo gateway instead of Kabeer's real line
  static String get defaultGatewayUrl => DemoConfig.enabled ? DemoConfig.gateway : _liveGatewayUrl;

  static const String _keySampleDataRemoved = 'awaaz_sample_data_removed';
  static const String _keyAvailability = 'awaaz_availability';
  static const String _keyBlockedCallers = 'awaaz_blocked_callers';
  static const String _keyCountryCode = 'awaaz_country_code';
  static const String _keyAutoVoice = 'awaaz_auto_voice';

  final SharedPreferences prefs;

  StorageService(this.prefs);

  // The gateway secret lives in the platform keystore (encrypted), read once at
  // startup so the rest of the app can use it synchronously.
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static String _secretCache = '';
  static bool _secureAvailable = true;

  /// Loads the gateway secret, moving it out of plain preferences if an older
  /// build stored it there. Call before the app starts.
  static Future<void> loadSecrets(SharedPreferences prefs) async {
    try {
      final legacy = prefs.getString(_keyGatewaySecret);
      if (legacy != null && legacy.isNotEmpty) {
        await _secure.write(key: _keyGatewaySecret, value: legacy);
        await prefs.remove(_keyGatewaySecret);
      }
      _secretCache = await _secure.read(key: _keyGatewaySecret) ?? '';
    } catch (e) {
      // No keystore here (tests, unsupported platform): keep using preferences
      debugPrint('StorageService: secure storage unavailable, using preferences ($e)');
      _secureAvailable = false;
      _secretCache = prefs.getString(_keyGatewaySecret) ?? '';
    }
  }

  /// Earlier builds seeded demo calls, tasks and contacts (and a fake
  /// "phonebook import"). Removes exactly those entries, once.
  Future<void> removeLegacySampleData() async {
    if (prefs.getBool(_keySampleDataRemoved) ?? false) return;
    const sampleCallIds = {'1', '2', '3'};
    const sampleTaskIds = {'101', '102', '103'};
    const sampleContactIds = {'c1', 'c2', 'c3', 'c4', 'c5'};
    const fakeImports = {
      'Kabeer Khan (Device Owner)': '+92 300 1234567',
      'Dr. Aris Thorne': '+1 (555) 678-9012',
      'Elena Rostova': '+1 (555) 890-1234',
    };

    await saveCallLogs(getCallLogs().where((c) => !sampleCallIds.contains(c.id)).toList());
    await saveTasks(getTasks().where((t) => !sampleTaskIds.contains(t.id)).toList());
    await saveContacts(getContacts()
        .where((c) => !sampleContactIds.contains(c.id) && fakeImports[c.name] != c.phoneNumber)
        .toList());
    await prefs.setBool(_keySampleDataRemoved, true);
  }

  // Call Logs
  List<CallRecordModel> getCallLogs() {
    final rawJson = prefs.getString(_keyCallLogs);
    if (rawJson == null) return [];
    try {
      final List decoded = jsonDecode(rawJson);
      return decoded.map((e) => CallRecordModel.fromJson(e)).toList();
    } catch (e) {
      final preview = rawJson.length > 200 ? rawJson.substring(0, 200) : rawJson;
      debugPrint('StorageService deserialization error for key "$_keyCallLogs": $e\nOffending payload (first 200 chars): $preview');
      return [];
    }
  }

  Future<void> saveCallLogs(List<CallRecordModel> logs) async {
    final rawJson = jsonEncode(logs.map((e) => e.toJson()).toList());
    await prefs.setString(_keyCallLogs, rawJson);
  }

  Future<void> addCallLog(CallRecordModel log) async {
    final current = getCallLogs();
    current.insert(0, log);
    await saveCallLogs(current);
  }

  // Secretary Tasks
  List<SecretaryTaskModel> getTasks() {
    final rawJson = prefs.getString(_keyTasks);
    if (rawJson == null) return [];
    try {
      final List decoded = jsonDecode(rawJson);
      return decoded.map((e) => SecretaryTaskModel.fromJson(e)).toList();
    } catch (e) {
      final preview = rawJson.length > 200 ? rawJson.substring(0, 200) : rawJson;
      debugPrint('StorageService deserialization error for key "$_keyTasks": $e\nOffending payload (first 200 chars): $preview');
      return [];
    }
  }

  Future<void> saveTasks(List<SecretaryTaskModel> tasks) async {
    final rawJson = jsonEncode(tasks.map((e) => e.toJson()).toList());
    await prefs.setString(_keyTasks, rawJson);
  }

  Future<void> addTask(SecretaryTaskModel task) async {
    final current = getTasks();
    current.insert(0, task);
    await saveTasks(current);
  }

  // Contacts
  List<ContactModel> getContacts() {
    final rawJson = prefs.getString(_keyContacts);
    if (rawJson == null) return [];
    try {
      final List decoded = jsonDecode(rawJson);
      return decoded.map((e) => ContactModel.fromJson(e)).toList();
    } catch (e) {
      final preview = rawJson.length > 200 ? rawJson.substring(0, 200) : rawJson;
      debugPrint('StorageService deserialization error for key "$_keyContacts": $e\nOffending payload (first 200 chars): $preview');
      return [];
    }
  }

  Future<void> saveContacts(List<ContactModel> contacts) async {
    final rawJson = jsonEncode(contacts.map((e) => e.toJson()).toList());
    await prefs.setString(_keyContacts, rawJson);
  }

  // Settings
  String? getApiKey() => prefs.getString(_keyApiKey);
  Future<void> setApiKey(String key) => prefs.setString(_keyApiKey, key);

  String getMasterName() => prefs.getString(_keyMasterName) ?? 'Kabeer';
  Future<void> setMasterName(String name) => prefs.setString(_keyMasterName, name);

  String getGatewayUrl() => prefs.getString(_keyGatewayUrl) ?? defaultGatewayUrl;
  Future<void> setGatewayUrl(String url) => prefs.setString(_keyGatewayUrl, url);

  // Must match GATEWAY_AUTH_SECRET on the server
  String getGatewaySecret() => _secretCache.isNotEmpty ? _secretCache : (prefs.getString(_keyGatewaySecret) ?? '');

  Future<void> setGatewaySecret(String secret) async {
    _secretCache = secret;
    if (_secureAvailable) {
      try {
        await _secure.write(key: _keyGatewaySecret, value: secret);
        return;
      } catch (e) {
        debugPrint('StorageService: secure write failed, using preferences ($e)');
        _secureAvailable = false;
      }
    }
    await prefs.setString(_keyGatewaySecret, secret);
  }

  /// Whether the secretary joins Kabeer on the phone as soon as a call arrives.
  /// Off: he starts it from the call screen (saves AssemblyAI minutes).
  bool getAutoVoice() => prefs.getBool(_keyAutoVoice) ?? true;
  Future<void> setAutoVoice(bool enabled) => prefs.setBool(_keyAutoVoice, enabled);

  /// Available, busy (until a time) or do-not-disturb.
  Availability getAvailability() {
    final raw = prefs.getString(_keyAvailability);
    if (raw == null) return const Availability();
    try {
      return Availability.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Availability();
    }
  }

  Future<void> setAvailability(Availability availability) =>
      prefs.setString(_keyAvailability, jsonEncode(availability.toJson()));

  /// Browsers Kabeer blocked (spam or impostor): device id -> {reason, name, at}.
  Map<String, Map<String, dynamic>> getBlockedCallers() {
    final raw = prefs.getString(_keyBlockedCallers);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  Future<void> setBlockedCallers(Map<String, Map<String, dynamic>> blocked) =>
      prefs.setString(_keyBlockedCallers, jsonEncode(blocked));

  /// Country code for turning local numbers into WhatsApp numbers ("92" for Pakistan).
  String getCountryCode() => prefs.getString(_keyCountryCode) ?? '92';
  Future<void> setCountryCode(String code) => prefs.setString(_keyCountryCode, code.replaceAll(RegExp(r'\D'), ''));
}
