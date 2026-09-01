import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/audio_service.dart';
import '../services/session_service.dart';

class RemoteScreen extends StatefulWidget {
  final String peerId;
  final String hostname;
  final String sessionId;
  final String serverUrl;
  const RemoteScreen({super.key, required this.peerId, required this.hostname, required this.sessionId, required this.serverUrl});
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  bool _fullscreen = false;
  bool _micOn = false;
  bool _uiVisible = false;
  bool _mouseActive = true;
  bool _keyboardActive = true;
  Uint8List? _currentFrame;
  final AudioService _audio = AudioService();
  final SessionService _session = SessionService();

  Offset _lastPos = Offset.zero;
  int _lastButton = 1;
  int _quality = 60;
  final GlobalKey _imageAreaKey = GlobalKey();
  final FocusNode _keyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _audio.onMicChanged = (enabled) {
      if (mounted) setState(() => _micOn = enabled);
    };
    _audio.onLog = (msg) => context.read<AppState>().log(msg);
    _audio.startCall(widget.serverUrl, widget.sessionId).then((_) {
      _audio.toggleMic();
    }).catchError((e) {
      if (mounted) {
        context.read<AppState>().log('Error de audio: $e');
      }
    });

    _session.onLog = (msg) => context.read<AppState>().log(msg);
    _session.onFrame = (frame) {
      if (mounted) setState(() => _currentFrame = frame);
    };
    _session.onInputEvent = (event) {};
    _session.onDone = () {
      context.read<AppState>().log('Sesión remota finalizada');
      if (mounted) Navigator.pop(context);
    };
    _session.connect(widget.serverUrl, widget.sessionId).catchError((e) {
      if (mounted) {
        context.read<AppState>().log('Error de sesión remota: $e');
      }
    });
    _keyFocus.requestFocus();

    // Enviar dimension de la ventana al host
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final size = context.size;
      if (size != null) {
        final dim = size.shortestSide.round();
        _session.sendInputEvent({'type': 'resolution', 'dim': dim});
      }
    });
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _toggleMic() => _audio.toggleMic();
  void _toggleMouse() => setState(() => _mouseActive = !_mouseActive);
  void _toggleKeyboard() => setState(() => _keyboardActive = !_keyboardActive);

  void _sendMousePos(Offset localPos) {
    if (!_mouseActive || _currentFrame == null) return;
    final box = _imageAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final x = (localPos.dx / box.size.width).clamp(0.0, 1.0);
    final y = (localPos.dy / box.size.height).clamp(0.0, 1.0);
    _session.sendInputEvent({'type': 'mouse_pos', 'x': x, 'y': y});
  }

  void _sendMouseDown(int button) {
    if (!_mouseActive) return;
    _session.sendInputEvent({'type': 'mouse_down', 'button': button});
  }

  void _sendMouseUp(int button) {
    if (!_mouseActive) return;
    _session.sendInputEvent({'type': 'mouse_up', 'button': button});
  }

  void _sendKeyEvent(String type, int key) {
    if (!_keyboardActive) return;
    _session.sendInputEvent({'type': type, 'key': key});
  }

  @override
  void dispose() {
    _session.onFrame = null;
    _session.onDone = null;
    _session.onLog = null;
    _session.onInputEvent = null;
    _audio.onMicChanged = null;
    _audio.onLog = null;
    _session.disconnect();
    _audio.dispose();
    _keyFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyFocus,
      onKeyEvent: (node, event) {
        if (!_keyboardActive) return KeyEventResult.ignored;
        if (event is KeyDownEvent) {
          _sendKeyEvent('key_down', event.logicalKey.keyId);
        } else if (event is KeyUpEvent) {
          _sendKeyEvent('key_up', event.logicalKey.keyId);
        }
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: Stack(
                key: _imageAreaKey,
                children: [
                  _currentFrame != null
                      ? InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 3.0,
                        child: Image.memory(
                          _currentFrame!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Color(0xFF58A6FF)),
                              SizedBox(height: 16),
                              Text('Esperando pantalla remota...',
                                  style: TextStyle(color: Colors.white38, fontSize: 14)),
                            ],
                          ),
                        ),
                  // Listener transparente encima para capturar mouse
                  if (_currentFrame != null)
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerHover: (e) => _sendMousePos(e.localPosition),
                        onPointerMove: (e) => _sendMousePos(e.localPosition),
                    onPointerDown: (e) {
                      _lastButton = e.buttons & 2 != 0 ? 2 : 1;
                      _sendMousePos(e.localPosition);
                      _sendMouseDown(_lastButton);
                    },
                    onPointerUp: (e) => _sendMouseUp(_lastButton),
                      ),
                    ),
                ],
              ),
            ),

            // Boton flotante para mostrar/ocultar UI
            Positioned(
              right: 4,
              top: 4,
              child: Material(
                color: const Color(0xAA000000),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _uiVisible = !_uiVisible),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _uiVisible ? Icons.arrow_forward_ios : Icons.arrow_back_ios_new,
                      color: const Color(0xFF58A6FF), size: 20,
                    ),
                  ),
                ),
              ),
            ),

            if (_uiVisible) ...[
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  padding: EdgeInsets.only(top: _fullscreen ? 16 : 8, left: 8, right: 8),
                  color: const Color(0x80000000),
                  child: Row(
                    children: [
                      _FloatingBtn(icon: Icons.call_end, tooltip: 'Finalizar conexion', color: Colors.redAccent, onTap: () {
                        _session.disconnect();
                        Navigator.pop(context);
                      }),
                      const SizedBox(width: 4),
                      _FloatingBtn(icon: Icons.arrow_drop_down, tooltip: 'Ocultar panel', onTap: () => setState(() => _uiVisible = false)),
                      const Spacer(),
                      Text(widget.hostname, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      _FloatingBtn(icon: _micOn ? Icons.mic : Icons.mic_off, tooltip: 'Microfono', color: _micOn ? Colors.green : null, onTap: _toggleMic),
                      const SizedBox(width: 4),
                      _FloatingBtn(icon: Icons.fullscreen, tooltip: 'Pantalla completa', onTap: _toggleFullscreen),
                      const SizedBox(width: 4),
                      _FloatingBtn(icon: Icons.close, tooltip: 'Cerrar', color: Colors.redAccent, onTap: () => Navigator.pop(context)),
                    ],
                  ),
                ),
              ),

              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  color: const Color(0x80000000),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ToggleBtn(Icons.keyboard, 'Teclado', active: _keyboardActive, onTap: _toggleKeyboard),
                      const SizedBox(width: 20),
                      _ToggleBtn(Icons.mouse, 'Mouse', active: _mouseActive, onTap: _toggleMouse),
                      const SizedBox(width: 20),
                      _ToolBtn(Icons.content_copy, 'Clipboard', tooltip: 'Copiar/pegar texto', onTap: () {
                        Clipboard.getData('text/plain').then((data) {
                          if (data?.text != null && data!.text!.isNotEmpty) {
                            _session.sendInputEvent({'type': 'clipboard', 'text': data.text});
                          }
                        });
                      }),
                      const SizedBox(width: 20),
                      _ToolBtn(Icons.file_download, 'Archivos', tooltip: 'Transferencia de archivos'),
                      const SizedBox(width: 20),
                      _ToolBtn(Icons.speed, 'Calidad', tooltip: 'Calidad: $_quality%', onTap: () {
                        final qualities = [40, 55, 75, 90];
                        final idx = qualities.indexOf(_quality);
                        setState(() => _quality = qualities[(idx + 1) % qualities.length]);
                        _session.sendInputEvent({'type': 'quality', 'value': _quality});
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn(this.icon, this.label, {required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$label ${active ? "activado" : "desactivado"}',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? Colors.green : Colors.white54, size: 20),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: active ? Colors.greenAccent : Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;
  const _FloatingBtn({required this.icon, required this.tooltip, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color ?? Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;
  const _ToolBtn(this.icon, this.label, {this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: onTap != null ? Colors.white70 : Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
    if (onTap != null) {
      return Tooltip(
        message: tooltip ?? label,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(4), child: child),
        ),
      );
    }
    return child;
  }
}
