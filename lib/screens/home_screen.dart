import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/device_info.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import 'admin_panel_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (state.connectionStatus == ConnectionStatus.disconnected) {
        final host = Platform.localHostname;
        state.connectToServer(host, Platform.operatingSystem, 7890);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, __) {
        return Scaffold(
          backgroundColor: const Color(0xFF0D1117),
          appBar: state.authenticated
            ? _buildAuthAppBar(state)
            : _buildGuestAppBar(state),
          body: state.authenticated
            ? _buildAuthBody(state)
            : _buildGuestBody(state),
          bottomNavigationBar: state.authenticated ? _buildNavBar(state) : null,
        );
      },
    );
  }

  AppBar _buildGuestAppBar(AppState state) {
    return AppBar(
      backgroundColor: const Color(0xFF161B22),
      title: Row(
        children: [
          Icon(Icons.desktop_windows, color: Color(0xFF58A6FF), size: 18),
          SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AzulRemote', style: TextStyle(fontSize: 14, color: Colors.white54)),
              Text('v${state.appVersion}', style: TextStyle(fontSize: 10, color: Colors.white24)),
            ],
          ),
          Spacer(),
          _DeviceIdBadge(deviceId: state.deviceId),
          SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.person_outline, size: 18, color: Color(0xFF58A6FF)),
            tooltip: 'Iniciar sesión',
            onPressed: () => _showLoginDialog(context),
          ),
        ],
      ),
    );
  }

  AppBar _buildAuthAppBar(AppState state) {
    return AppBar(
      backgroundColor: const Color(0xFF161B22),
      title: Row(
        children: [
          Icon(Icons.desktop_windows, color: Color(0xFF58A6FF), size: 18),
          SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AzulRemote', style: TextStyle(fontSize: 14, color: Colors.white54)),
              Text('v${state.appVersion}', style: TextStyle(fontSize: 10, color: Colors.white24)),
            ],
          ),
          Spacer(),
          _DeviceIdBadge(deviceId: state.deviceId),
          SizedBox(width: 8),
          Text(state.userName, style: TextStyle(color: Colors.white54, fontSize: 12)),
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: state.isAdmin ? Color(0xFF238636).withValues(alpha: 0.2) : Color(0xFF1F6FEB).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(state.userRole.toUpperCase(),
              style: TextStyle(fontSize: 10, color: state.isAdmin ? Color(0xFF238636) : Color(0xFF1F6FEB))),
          ),
          SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.logout, size: 16, color: Colors.redAccent),
            tooltip: 'Cerrar sesión',
            onPressed: () => state.logout(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavBar(AppState state) {
    final items = <NavigationDestination>[];
    if (state.isAdmin) {
      items.addAll([
        NavigationDestination(
          icon: Icon(Icons.desktop_windows_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.desktop_windows, color: Color(0xFF58A6FF)),
          label: 'Dispositivos',
        ),
        NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.admin_panel_settings, color: Color(0xFF58A6FF)),
          label: 'Admin',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.settings, color: Color(0xFF58A6FF)),
          label: 'Config',
        ),
      ]);
    } else {
      items.addAll([
        NavigationDestination(
          icon: Icon(Icons.search, color: Colors.white54),
          selectedIcon: Icon(Icons.search, color: Color(0xFF58A6FF)),
          label: 'Conectar',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined, color: Colors.white54),
          selectedIcon: Icon(Icons.settings, color: Color(0xFF58A6FF)),
          label: 'Config',
        ),
      ]);
    }
    return NavigationBar(
      backgroundColor: const Color(0xFF161B22),
      indicatorColor: const Color(0xFF1F2937),
      selectedIndex: _selectedTab.clamp(0, items.length - 1),
      onDestinationSelected: (i) => setState(() => _selectedTab = i),
      destinations: items,
    );
  }

  Widget _buildAuthBody(AppState state) {
    if (state.isAdmin) {
      switch (_selectedTab) {
        case 0: return const DashboardScreen();
        case 1: return const AdminPanelScreen();
        case 2: return const SettingsScreen();
        default: return const DashboardScreen();
      }
    } else {
      switch (_selectedTab) {
        case 0: return _SearchScreen(state: state);
        case 1: return const SettingsScreen();
        default: return _SearchScreen(state: state);
      }
    }
  }

  Widget _buildGuestBody(AppState state) {
    String statusText;
    Color statusColor;

    switch (state.connectionStatus) {
      case ConnectionStatus.connecting:
        statusText = 'Conectando...';
        statusColor = Colors.yellowAccent;
        break;
      case ConnectionStatus.error:
        statusText = 'Error de conexión';
        statusColor = Colors.redAccent;
        break;
      case ConnectionStatus.disconnected:
        statusText = 'Desconectado';
        statusColor = Colors.white38;
        break;
      case ConnectionStatus.connected:
        statusText = '';
        statusColor = Colors.white38;
        break;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.vpn_key, size: 32, color: Colors.white24),
          SizedBox(height: 16),
          Text('MI ID DE CONEXIÓN',
            style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 4)),
          SizedBox(height: 8),
          SelectableText(
            state.deviceId.isNotEmpty ? state.deviceId : statusText,
            style: TextStyle(
              color: state.deviceId.isNotEmpty ? Colors.white : statusColor,
              fontSize: state.deviceId.isNotEmpty ? 36 : 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
          SizedBox(height: 8),
          if (state.deviceId.isNotEmpty)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: state.deviceId));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ID copiado'), duration: Duration(seconds: 1)),
                );
              },
              child: Text('Toca para copiar',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          SizedBox(height: 24),
          if (state.connectionLogs.isNotEmpty)
            _ConnectionLog(logs: state.connectionLogs),
        ],
      ),
    );
  }

  void _showLoginDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const Dialog(
        backgroundColor: Color(0xFF161B22),
        child: SizedBox(width: 380, child: LoginScreen()),
      ),
    );
  }
}

// ─── Device ID Badge ─────────────────────────────────

class _DeviceIdBadge extends StatelessWidget {
  final String deviceId;
  const _DeviceIdBadge({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    if (deviceId.isEmpty) return const SizedBox();
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: deviceId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID copiado'), duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.vpn_key, size: 10, color: Color(0xFF58A6FF)),
            SizedBox(width: 4),
            Text(deviceId, style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1)),
            SizedBox(width: 4),
            Icon(Icons.copy, size: 10, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// ─── Connection Log Dropdown ────────────────────────

class _ConnectionLog extends StatelessWidget {
  final List<String> logs;
  const _ConnectionLog({required this.logs});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.symmetric(horizontal: 40),
      title: Row(
        children: [
          Text('${logs.length} eventos',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.copy, size: 14, color: Colors.white38),
            tooltip: 'Copiar logs',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copiados al portapapeles')),
              );
            },
          ),
        ],
      ),
      children: [
        Container(
          constraints: BoxConstraints(maxHeight: 150, maxWidth: 500),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: logs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Text(logs[i],
                style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Search Screen (Support Role) ─────────────────────

class _SearchScreen extends StatelessWidget {
  final AppState state;
  const _SearchScreen({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Icon(Icons.search, size: 40, color: Colors.white24),
          const SizedBox(height: 16),
          Text('Conectar por ID de dispositivo',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 16),
          SizedBox(
            width: 400,
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ingresa el ID del equipo (ej: AB-1A2B-3C)',
                prefixIcon: Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: const Color(0xFF30363D)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  state.requestConnection(value.trim());
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Text('Presiona Enter para conectarte',
            style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }
}
