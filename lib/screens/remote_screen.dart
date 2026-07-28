import 'package:flutter/material.dart';

class RemoteScreen extends StatelessWidget {
  final String peerId;
  final String hostname;

  const RemoteScreen({
    super.key,
    required this.peerId,
    required this.hostname,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text('$hostname - $peerId',
          style: const TextStyle(color: Colors.white, fontSize: 14)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white54),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white54),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Remote desktop view
          Center(
            child: Container(
              color: Colors.black,
              child: const Center(
                child: Text('Remote Screen Stream',
                  style: TextStyle(color: Colors.white24, fontSize: 16)),
              ),
            ),
          ),
          // Bottom toolbar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: const Color(0xD0161B22),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolbarButton(Icons.keyboard, 'Teclado'),
                  const SizedBox(width: 16),
                  _ToolbarButton(Icons.mouse, 'Mouse'),
                  const SizedBox(width: 16),
                  _ToolbarButton(Icons.content_copy, 'Clipboard'),
                  const SizedBox(width: 16),
                  _ToolbarButton(Icons.file_download, 'Archivos'),
                  const SizedBox(width: 16),
                  _ToolbarButton(Icons.speed, 'Calidad'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ToolbarButton(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}
