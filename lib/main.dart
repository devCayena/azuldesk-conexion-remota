import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
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

  // Prevenir cierre real => minimizar a bandeja
  windowManager.setPreventClose(true);
  windowManager.setHasShadow(true);

  _initSystemTray();

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

Future<void> _initSystemTray() async {
  final logoPath = File('logo.png').existsSync() ? File('logo.png').absolute.path : '';
  final tray = SystemTray();
  await tray.initSystemTray(iconPath: logoPath);

  final menu = Menu();
  menu.buildFrom([
    MenuItemLabel(label: 'Mostrar', onClicked: (_) => windowManager.show()),
    MenuItemLabel(label: 'Salir', onClicked: (_) async {
      await windowManager.destroy();
      exit(0);
    }),
  ]);
  await tray.setContextMenu(menu);
  await tray.setToolTip('AzulRemote - Conexion Remota');

  tray.registerSystemTrayEventHandler((eventName) {
    if (eventName == 'leftMouseDown' || eventName == 'doubleClick') {
      windowManager.show();
    }
  });

  windowManager.setPreventClose(true);
  windowManager.addListener(_TrayWindowListener());
}

class _TrayWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }
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
