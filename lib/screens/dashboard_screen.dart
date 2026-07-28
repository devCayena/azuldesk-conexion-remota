import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
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
  @override
  void initState() {
    super.initState();
    // Auto-connect to signaling server on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().connectToServer(
        _hostname(),
        _os(),
        '1.0.0',
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
        title: const Text('AzulDesk - Conexión Remota',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
          _StatusBanner(),
          Expanded(
            child: Row(
              children: [
                _Sidebar(),
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
      return _runInShell('hostname').trim();
    } catch (_) {
      return 'unknown';
    }
  }

  String _os() {
    try {
      return _runInShell('ver').trim();
    } catch (_) {
      return 'Windows';
    }
  }

  String _runInShell(String cmd) {
    // Simplified - in real app use dart:io
    return 'Desktop';
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
            Text('v1.0.0', style: const TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      color: const Color(0xFF161B22),
      child: Column(
        children: [
          _SearchBar(),
          const SizedBox(height: 8),
          const Expanded(child: _PeerList()),
          _ReconnectButton(),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Buscar dispositivo...',
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
      ),
    );
  }
}

class _PeerList extends StatelessWidget {
  const _PeerList();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, _) {
        if (state.connectionStatus == ConnectionStatus.connecting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.blueGrey),
          );
        }
        if (state.onlinePeers.isEmpty) {
          return const Center(
            child: Text('No hay dispositivos en linea',
              style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView.builder(
          itemCount: state.onlinePeers.length,
          itemBuilder: (_, i) => _PeerTile(peer: state.onlinePeers[i]),
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
      subtitle: Text('${peer.publicIp}:${peer.listenPort}',
        style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF238636).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Conectar',
          style: TextStyle(color: Color(0xFF238636), fontSize: 11)),
      ),
      onTap: () {
        context.read<AppState>().requestConnection(peer.peerId);
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RemoteScreen(
            peerId: peer.peerId,
            hostname: peer.hostname,
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
                  state.connectToServer('Desktop', 'Windows', '1.0.0', 7890);
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
