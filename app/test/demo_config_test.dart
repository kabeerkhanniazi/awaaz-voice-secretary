import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awaaz_app/core/demo_config.dart';
import 'package:awaaz_app/services/storage_service.dart';

// Run as a demo build too:
//   flutter test test/demo_config_test.dart --dart-define=AWAAZ_DEMO_GATEWAY=wss://demo.example.app
void main() {
  test('a normal build has no demo line and uses the live gateway', () async {
    if (DemoConfig.enabled) return; // covered by the demo-build test below
    SharedPreferences.setMockInitialValues({});
    await DemoConfig.load(await SharedPreferences.getInstance());
    expect(DemoConfig.line, isEmpty);
    expect(StorageService.defaultGatewayUrl, 'wss://aivs.up.railway.app');
  });

  test('a demo build gets one lasting line code and a link that rings it', () async {
    if (!DemoConfig.enabled) return; // only meaningful with --dart-define=AWAAZ_DEMO_GATEWAY=...
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DemoConfig.load(prefs);
    final first = DemoConfig.line;
    // Same shape the gateway accepts, and no easily confused characters
    expect(first, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));

    // Relaunching keeps the same line, so a copied link keeps working
    await DemoConfig.load(prefs);
    expect(DemoConfig.line, first);

    expect(DemoConfig.callLink, 'https://demo.example.app/?line=$first');
    expect(StorageService.defaultGatewayUrl, 'wss://demo.example.app');
  });
}
