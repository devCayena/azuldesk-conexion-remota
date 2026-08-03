import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isAdmin) {
      return const SizedBox();
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Panel de Administración',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _Card(
                  icon: Icons.history,
                  title: 'Registro de Auditoría',
                  subtitle: 'Ver conexiones y actividad de todos los usuarios',
                  onTap: () => _showAuditLog(context, state),
                ),
                SizedBox(height: 12),
                _Card(
                  icon: Icons.person_add,
                  title: 'Gestión de Usuarios',
                  subtitle: 'Crear, bloquear o cambiar roles de usuarios',
                  onTap: () => _showUserManagement(context, state),
                ),
                SizedBox(height: 12),
                _Card(
                  icon: Icons.devices,
                  title: 'Dispositivos Registrados',
                  subtitle: 'Ver todos los dispositivos y sus certificados',
                  onTap: () {},
                ),
                SizedBox(height: 12),
                _Card(
                  icon: Icons.key,
                  title: 'Claves Maestras',
                  subtitle: 'Rotar y gestionar claves maestras',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAuditLog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF161B22),
        child: SizedBox(
          width: 700,
          height: 500,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Registro de Auditoría',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Text('Próximamente: lista completa de conexiones, usuarios y dispositivos',
                      style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUserManagement(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF161B22),
        child: SizedBox(
          width: 500,
          height: 400,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Gestión de Usuarios',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: Text('Próximamente: crear y gestionar usuarios',
                      style: TextStyle(color: Colors.white38)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Card({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF161B22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF30363D)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF58A6FF), size: 28),
        title: Text(title, style: TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
