import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/device_info.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Configuracion',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _sectionTitle('Servidor'),
          const SizedBox(height: 12),
          _card([
            Row(
              children: [
                const Icon(Icons.dns, color: Colors.white24, size: 18),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.serverHost,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('WebSocket:  ws://host:7980',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                    Text('REST API:   http://host:7981',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('Conectar al servidor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: state.connectionStatus == ConnectionStatus.connected
                  ? null
                  : () => state.connectToServer('Desktop', 'Windows', '1.0.0', 7890),
              ),
            ),
          ]),
          const SizedBox(height: 32),
          _sectionTitle('Puerto Local (P2P)'),
          const SizedBox(height: 12),
          _card([
            Text(
              'Puerto para recibir conexiones directas de otros dispositivos.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.router, color: Colors.white24, size: 18),
                const SizedBox(width: 8),
                Text('TCP 7890',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ]),
          const SizedBox(height: 32),
          _sectionTitle('Conexion'),
          const SizedBox(height: 12),
          _card([
            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.connectionStatus == ConnectionStatus.connected
                        ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.connectionStatus == ConnectionStatus.connected
                      ? 'Conectado al servidor'
                      : 'Desconectado',
                  style: const TextStyle(color: Colors.white70),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => state.disconnectFromServer(),
                  child: const Text('Desconectar',
                    style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
            if (state.onlinePeers.isNotEmpty) ...[
              const Divider(color: Color(0xFF30363D)),
              Text('${state.onlinePeers.length} dispositivo(s) en linea',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(title,
    style: const TextStyle(
      color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600));

  Widget _card(List<Widget> children) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF30363D)),
    ),
    child: Column(children: children),
  );
}
