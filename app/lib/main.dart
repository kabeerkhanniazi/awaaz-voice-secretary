import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/demo_config.dart';
import 'core/theme/app_theme.dart';
import 'providers/storage_provider.dart';
import 'screens/dashboard_screen.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await StorageService(prefs).removeLegacySampleData();
  await StorageService.loadSecrets(prefs);
  await DemoConfig.load(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const AwaazApp(),
    ),
  );
}

class AwaazApp extends StatelessWidget {
  const AwaazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Awaaz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const DashboardScreen(),
    );
  }
}
