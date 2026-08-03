import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device_info.dart';
import 'file_logger.dart';

class SignalingService {
  WebSocketChannel? _channel;
  bool _connected = false;

  final String serverUrl;
  final void Function(List<OnlinePeer> peers) onPeerList;
  final void Function(DeviceInfo from, String sessionId) onConnectionRequested;
  final void Function(String sessionId, String? ip, int? port) onConnectionAccepted;
  final void Function(String peerId) onRegistered;
  final void Function(String log)? onLog;

  SignalingService({
    required this.serverUrl,
    required this.onPeerList,
    required this.onConnectionRequested,
    required this.onConnectionAccepted,
    required this.onRegistered,
    this.onCertificate,
    this.onError,
    this.onLog,
  });

  bool get isConnected => _connected;

  void _log(String msg) {
    if (onLog != null) {
      onLog!(msg);
    } else {
      print('[Signaling] $msg');
      FileLogger.instance.log('[Signaling] $msg');
    }
  }

  Future<void> connect(String hostname, String os, String version, int listenPort, {String? serialNumber, String? certificate}) async {
    _log('Connecting to $serverUrl');
    try {
      final uri = Uri.parse(serverUrl);
      _log('Parsed URI: $uri');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
      _log('WebSocket connected');

      _channel!.stream.listen(
        (data) {
          final msg = json.decode(data as String);
          _log('Received: ${msg.keys.first}');
          _handleMessage(msg);
        },
        onError: (e) {
          _log('Stream error: $e');
          _connected = false;
        },
        onDone: () {
          _log('Stream closed');
          _connected = false;
        },
      );

      send({
        'Register': {
          'device': {
            'peer_id': '00000000-0000-0000-0000-000000000000',
            'hostname': hostname,
            'os': os,
            'version': version,
            'public_ip': null,
            'mac_address': serialNumber ?? 'unknown',
          },
          'listen_port': listenPort,
          if (certificate != null && certificate.isNotEmpty) 'certificate': certificate,
        }
      });
      _log('Register sent');

      _connected = true;
      _log('Connection established');
    } catch (e) {
      _log('Connection failed: $e');
      _connected = false;
      rethrow;
    }
  }

  void Function(String certPem, String serialNumber)? onCertificate;
  void Function(int code, String message)? onError;

  void _handleMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('Registered')) {
      final peerId = msg['Registered']['peer_id'] as String;
      _log('Registered as $peerId');
      onRegistered(peerId);
    } else if (msg.containsKey('Certificate')) {
      final cert = msg['Certificate'];
      final certPem = cert['cert_pem'] as String;
      final serialNumber = cert['serial_number'] as String;
      _log('Certificate received for $serialNumber');
      onCertificate?.call(certPem, serialNumber);
    } else if (msg.containsKey('PeerList')) {
      final peers = (msg['PeerList']['peers'] as List)
          .map((e) => OnlinePeer.fromJson(e))
          .toList();
      _log('PeerList: ${peers.length} peers');
      onPeerList(peers);
    } else if (msg.containsKey('ConnectRequested')) {
      final req = msg['ConnectRequested'];
      final from = DeviceInfo.fromJson(req['from']);
      final sessionId = req['session_id'] as String;
      _log('Connection requested from ${from.peerId}');
      onConnectionRequested(from, sessionId);
    } else if (msg.containsKey('ConnectResponse')) {
      final resp = msg['ConnectResponse'];
      final sessionId = resp['session_id'] as String;
      final accepted = resp['accepted'] == true;
      _log('ConnectResponse: ${accepted ? "accepted" : "rejected"} session=$sessionId');
      if (accepted) {
        onConnectionAccepted(sessionId, resp['target_ip'], resp['target_port']?.toInt());
      }
    } else if (msg.containsKey('Error')) {
      final err = msg['Error'];
      final code = err['code'] as int;
      final message = err['message'] as String;
      _log('Error $code: $message');
      onError?.call(code, message);
    } else {
      _log('Unknown message: ${msg.keys.first}');
    }
  }

  void requestConnection(String targetPeerId, {String? masterKey}) {
    _log('Requesting connection to $targetPeerId');
    send({
      'ConnectRequest': {
        'target_id': targetPeerId,
        if (masterKey != null) 'auth': {'MasterKey': masterKey}
        else 'auth': 'AutoApprove',
      }
    });
  }

  void respondToConnection(String sessionId, {required bool accepted, String? targetIp, int? targetPort, String? reason}) {
    _log('Responding to $sessionId: ${accepted ? "accepted" : "rejected"}');
    send({
      'ConnectResponse': {
        'accepted': accepted,
        'session_id': sessionId,
        'target_ip': targetIp,
        'target_port': targetPort,
        'reason': reason,
      }
    });
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(json.encode(msg));
  }

  void disconnect() {
    _log('Disconnecting');
    send({'Disconnect': {'reason': 'client closed'}});
    _channel?.sink.close();
    _connected = false;
  }
}
