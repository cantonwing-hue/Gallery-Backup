import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'core/auto_backup.dart';
import 'core/vault_controller.dart';
import 'ui/vault_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(photoVaultDispatcher);
  runApp(const CloudPhotoVaultApp());
}

class CloudPhotoVaultApp extends StatefulWidget {
  const CloudPhotoVaultApp({super.key});

  @override
  State<CloudPhotoVaultApp> createState() => _CloudPhotoVaultAppState();
}

class _CloudPhotoVaultAppState extends State<CloudPhotoVaultApp> {
  final VaultController controller = VaultController();

  @override
  void initState() {
    super.initState();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ColorScheme.fromSeed(
      seedColor: const Color(0xFF206A64),
      brightness: Brightness.light,
      surface: const Color(0xFFF6F8F6),
    );
    return MaterialApp(
      title: 'Cloud Photo Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: palette,
        scaffoldBackgroundColor: const Color(0xFFF6F8F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8F6),
          centerTitle: false,
          titleTextStyle: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: Color(0xFF153E3A)),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      home: VaultHome(controller: controller),
    );
  }
}
