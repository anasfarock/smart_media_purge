import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'features/faces/privacy_vault.dart';
import 'features/home/home_screen.dart';

class SmartMediaPurgeApp extends StatefulWidget {
  const SmartMediaPurgeApp({super.key});

  @override
  State<SmartMediaPurgeApp> createState() => _SmartMediaPurgeAppState();
}

class _SmartMediaPurgeAppState extends State<SmartMediaPurgeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-lock the private-people vault whenever the app leaves the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<PrivacyVault>().lock();
    }
  }

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0E7C7B),
        brightness: b,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Media Purge',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}
