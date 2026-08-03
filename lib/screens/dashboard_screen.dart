import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/device_info.dart';
import 'remote_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Auto-connect to signaling server on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().connectToServer(
        _hostname(),
        _os(),
        7890,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Consumer<AppState>(
          builder: (_, state, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AzulDesk - Conexión Remota',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
              Text('v${state.appVersion}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        actions: [
          Consumer<AppState>(
            builder: (_, state, _) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: state.connectionStatus == ConnectionStatus.connected
                          ? Colors.green
                          : state.connectionStatus == ConnectionStatus.connecting
                              ? Colors.amber
                              : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.connectionStatus == ConnectionStatus.connected
                        ? 'Conectado'
                        : state.connectionStatus == ConnectionStatus.connecting
                            ? 'Conectando...'
                            : 'Desconectado',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _DeviceIdBanner(),
          _StatusBanner(),
          Expanded(
              child: Row(
                children: [
                  _Sidebar(
                    searchQuery: _searchController.text,
                    onSearchChanged: (q) => setState(() {}),
                    controller: _searchController,
                  ),
                  Expanded(child: _MainContent()),
                ],
              ),
          ),
        ],
      ),
    );
  }

  String _hostname() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'unknown';
    }
  }

  String _os() {
    return Platform.operatingSystem;
  }
}

class _DeviceIdBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: const Color(0xFF1F2937),
        child: Row(
          children: [
            const Icon(Icons.vpn_key, size: 16, color: Color(0xFF58A6FF)),
            const SizedBox(width: 8),
            const Text('Tu ID:', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(width: 8),
            SelectableText(
              state.deviceId.isNotEmpty ? state.deviceId : 'Conectando...',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 1),
            ),
            if (state.deviceId.isNotEmpty) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  // Copy to clipboard
                },
                child: const Icon(Icons.copy, size: 14, color: Color(0xFF58A6FF)),
              ),
            ],
            const Spacer(),
            Text(state.userName, style: const TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (_) => _LogViewerDialog(
                  logs: context.read<AppState>().connectionLogs,
                ),
              ),
              child: const Icon(Icons.receipt_long, size: 18, color: Colors.white38),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () => context.read<AppState>().logout(),
              child: const Icon(Icons.logout, size: 18, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      color: const Color(0xFF161B22),
      child: Consumer<AppState>(
        builder: (_, state, _) => Row(
          children: [
            Icon(Icons.circle, size: 8,
              color: state.connectionStatus == ConnectionStatus.connected
                  ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${state.onlinePeers.length} dispositivo(s) en linea',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const Spacer(),
            Consumer<AppState>(
              builder: (_, state, __) => Text('v${state.appVersion}',
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final TextEditingController controller;
  const _Sidebar({required this.searchQuery, required this.onSearchChanged, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: const Color(0xFF161B22),
      child: Column(
        children: [
          _SearchBar(
            value: searchQuery,
            onChanged: onSearchChanged,
            controller: controller,
          ),
          const SizedBox(height: 8),
          Expanded(child: _PeerList(query: searchQuery)),
          _ReconnectButton(),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  const _SearchBar({required this.value, required this.onChanged, this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o ID...',
          hintStyle: const TextStyle(color: Colors.white30),
          prefixIcon: const Icon(Icons.search, color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF0D1117),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _PeerList extends StatelessWidget {
  final String query;
  const _PeerList({required this.query});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, _) {
        if (state.connectionStatus == ConnectionStatus.connecting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.blueGrey),
          );
        }
        final q = query.trim().toLowerCase();
        final peers = q.isEmpty
            ? state.onlinePeers
            : state.onlinePeers.where((p) =>
                p.hostname.toLowerCase().contains(q) ||
                p.connectionId.toLowerCase().contains(q) ||
                p.peerId.toLowerCase().contains(q)).toList();
        if (peers.isEmpty) {
          return const Center(
            child: Text('No hay dispositivos en linea',
              style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView.builder(
          itemCount: peers.length,
          itemBuilder: (_, i) => _PeerTile(peer: peers[i]),
        );
      },
    );
  }
}

class _PeerTile extends StatelessWidget {
  final OnlinePeer peer;
  const _PeerTile({required this.peer});

  @override
  Widget build(BuildContext context) {
    final isWin = peer.os.toLowerCase().contains('win');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF21262D),
        child: Icon(
          isWin ? Icons.desktop_windows : Icons.computer,
          color: Colors.white54, size: 20,
        ),
      ),
      title: Text(peer.hostname,
        style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${peer.publicIp}:${peer.listenPort}',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
          Text(peer.connectionId,
            style: const TextStyle(
              color: Color(0xFF58A6FF),
              fontSize: 11,
              letterSpacing: 1,
            )),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF238636).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Conectar',
          style: TextStyle(color: Color(0xFF238636), fontSize: 11)),
      ),
      onTap: () async {
        final state = context.read<AppState>();
        state.requestConnection(peer.peerId);
        final sessionId = state.sessionId;
        if (sessionId == null) {
          final wait = state.sessionIdCompleter;
          await wait?.future;
        }
        if (!context.mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RemoteScreen(
            peerId: peer.peerId,
            hostname: peer.hostname,
            sessionId: context.read<AppState>().sessionId!,
            serverUrl: context.read<AppState>().audioUrl,
          ),
        ));
      },
    );
  }
}

class _ReconnectButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, _) {
        if (state.connectionStatus == ConnectionStatus.disconnected ||
            state.connectionStatus == ConnectionStatus.error) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reconectar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF30363D)),
                ),
                onPressed: () {
                  final host = Platform.localHostname;
                  state.connectToServer(host, Platform.operatingSystem, 7890);
                },
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _MainContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.computer, size: 80, color: Color(0xFF30363D)),
            SizedBox(height: 24),
            Text('Selecciona un dispositivo',
              style: TextStyle(color: Colors.white54, fontSize: 18)),
            SizedBox(height: 8),
            Text('Haz clic en un equipo para conectarte remotamente',
              style: TextStyle(color: Colors.white30, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _LogViewerDialog extends StatelessWidget {
  final List<String> logs;
  const _LogViewerDialog({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161B22),
      child: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('Registro de conexión',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Color(0xFF30363D)),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copiados al portapapeles')),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF30363D), height: 1),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('Sin logs',
                      style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                        child: SelectableText(logs[i],
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
