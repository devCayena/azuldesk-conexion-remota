import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/device_info.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Configuración', style: TextStyle(color: Colors.white)),
      ),
      body: Consumer<AppState>(
        builder: (_, state, __) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section('Servidor', [
              _row('URL', state.serverHost),
              _editField(context, 'Host del servidor', state.serverHost, (v) => state.setServerHost(v)),
              _btn('Conectar al servidor', () {
                state.connectToServer('Desktop', 'Windows', 7890);
              }),
            ]),
            const SizedBox(height: 16),
            _section('Mi Dispositivo', [
              _row('ID', state.deviceId.isNotEmpty ? state.deviceId : '—'),
              _row('Nombre', state.deviceName),
              _editField(context, 'Puerto P2P', '7890', (_) {}),
            ]),
            const SizedBox(height: 16),
            _section('Clave Maestra', [
              _editField(context, 'Master Key', state.masterKey ?? '', (v) => state.setMasterKey(v.isEmpty ? null : v)),
              _row('Estado', state.masterKey != null ? 'Configurada' : 'No configurada'),
            ]),
            const SizedBox(height: 16),
            _section('Cuenta', [
              _row('Usuario', state.userName),
              _row('Admin', state.isAdmin ? 'Sí' : 'No'),
              _btn('Cerrar sesión', () => state.logout()),
            ]),
            const SizedBox(height: 16),
            _section('Conexión', [
              _row('Estado', state.connectionStatus == ConnectionStatus.connected ? 'Conectado' : 'Desconectado'),
              _row('Pares en línea', '${state.onlinePeers.length}'),
              _btn('Desconectar', () => state.disconnectFromServer()),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Column(children: children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList()),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }

  Widget _editField(BuildContext context, String label, String initial, void Function(String) onSave) {
    final ctrl = TextEditingController(text: initial);
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onSubmitted: onSave,
    );
  }

  Widget _btn(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Color(0xFF30363D))),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
