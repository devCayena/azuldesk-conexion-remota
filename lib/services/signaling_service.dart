import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device_info.dart';

class SignalingService {
  WebSocketChannel? _channel;
  bool _connected = false;

  final String serverUrl;
  final void Function(List<OnlinePeer> peers) onPeerList;
  final void Function(DeviceInfo from, String sessionId) onConnectionRequested;
  final void Function(String sessionId, String? ip, int? port) onConnectionAccepted;

  SignalingService({
    required this.serverUrl,
    required this.onPeerList,
    required this.onConnectionRequested,
    required this.onConnectionAccepted,
  });

  bool get isConnected => _connected;

  Future<void> connect(String hostname, String os, String version, int listenPort) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      await _channel!.ready;

      _channel!.stream.listen(
        (data) {
          final msg = json.decode(data as String);
          _handleMessage(msg);
        },
        onError: (e) {
          _connected = false;
        },
        onDone: () {
          _connected = false;
        },
      );

      // Register (peer_id will be assigned by server)
      send({
        'Register': {
          'device': {
            'peer_id': '${DateTime.now().millisecondsSinceEpoch}',
            'hostname': hostname,
            'os': os,
            'version': version,
            'public_ip': null,
          },
          'listen_port': listenPort,
        }
      });

      _connected = true;
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('PeerList')) {
      final peers = (msg['PeerList']['peers'] as List)
          .map((e) => OnlinePeer.fromJson(e))
          .toList();
      onPeerList(peers);
    } else if (msg.containsKey('ConnectRequested')) {
      final req = msg['ConnectRequested'];
      final from = DeviceInfo.fromJson(req['from']);
      onConnectionRequested(from, req['session_id']);
    } else if (msg.containsKey('ConnectResponse')) {
      final resp = msg['ConnectResponse'];
      if (resp['accepted'] == true) {
        onConnectionAccepted(
          resp['session_id'],
          resp['target_ip'],
          resp['target_port']?.toInt(),
        );
      }
    }
  }

  void requestConnection(String targetPeerId, {String? masterKey}) {
    send({
      'ConnectRequest': {
        'target_id': targetPeerId,
        if (masterKey != null)
          'auth': {'MasterKey': masterKey}
        else
          'auth': 'AutoApprove',
      }
    });
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(json.encode(msg));
  }

  void disconnect() {
    send({'Disconnect': {'reason': 'client closed'}});
    _channel?.sink.close();
    _connected = false;
  }
}
