import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/app_state.dart';
import 'screens/home_screen.dart';
import 'services/file_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await FileLogger.instance.init();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = WindowOptions(
    size: const Size(1200, 800),
    minimumSize: const Size(900, 600),
    center: true,
    title: 'AzulRemote',
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // La X cierra la app, minimizar la manda al fondo
  await windowManager.setPreventClose(false);
  await windowManager.setHasShadow(true);

  // Intentar cargar logo como icono de ventana
  try {
    final f = File('logo.png');
    if (f.existsSync()) {
      await windowManager.setIcon(f.path);
    }
  } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const SpywareApp(),
    ),
  );
}

class SpywareApp extends StatelessWidget {
  const SpywareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AzulRemote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF58A6FF),
          surface: const Color(0xFF0D1117),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
