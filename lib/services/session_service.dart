import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

class SessionService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  void Function(Uint8List frame)? onFrame;
  void Function(Map<String, dynamic> event)? onInputEvent;
  void Function(String)? onLog;
  void Function()? onDone;

  bool get isConnected => _channel != null;

  void _log(String msg) {
    onLog?.call('[Session] $msg');
  }

  Future<void> connect(String serverUrl, String sessionId) async {
    var base = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://')
        .replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/session/$sessionId');
    _log('Connecting session relay: $uri');

    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    _log('Session relay connected ($sessionId)');

    _subscription = _channel!.stream.listen(
      (data) {
        if (data is List<int>) {
          onFrame?.call(Uint8List.fromList(data));
        } else if (data is String) {
          try {
            final event = json.decode(data) as Map<String, dynamic>;
            onInputEvent?.call(event);
          } catch (_) {}
        }
      },
      onDone: () {
        _log('Session relay closed');
        _subscription?.cancel();
        _channel = null;
        onDone?.call();
      },
      onError: (e) {
        _log('Session relay error: $e');
        disconnect();
      },
    );
  }

  void sendFrame(Uint8List jpegData) {
    _channel?.sink.add(jpegData);
  }

  void sendInputEvent(Map<String, dynamic> event) {
    _channel?.sink.add(json.encode(event));
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    onDone?.call();
  }
}
