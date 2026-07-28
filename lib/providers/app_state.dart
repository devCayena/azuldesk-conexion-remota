import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/device_info.dart';
import '../services/signaling_service.dart';

class AppState extends ChangeNotifier {
  List<OnlinePeer> _onlinePeers = [];
  RemoteSession? _activeSession;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String? _masterKey;
  String _serverHost = dotenv.get('SERVER_HOST', fallback: '127.0.0.1');
  SignalingService? _signaling;

  List<OnlinePeer> get onlinePeers => _onlinePeers;
  RemoteSession? get activeSession => _activeSession;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String? get masterKey => _masterKey;
  String get serverHost => _serverHost;
  String get serverUrl => 'ws://$_serverHost:7980';
  String get httpUrl => 'http://$_serverHost:7981';

  void setServerHost(String host) {
    _serverHost = host.replaceAll(RegExp(r'^wss?://|^https?://|:\d+$'), '');
    notifyListeners();
  }

  void setMasterKey(String? key) {
    _masterKey = key;
    notifyListeners();
  }

  void setConnectionStatus(ConnectionStatus status) {
    _connectionStatus = status;
    notifyListeners();
  }

  void setActiveSession(RemoteSession? session) {
    _activeSession = session;
    notifyListeners();
  }

  Future<void> connectToServer(String hostname, String os, String version, int listenPort) async {
    _connectionStatus = ConnectionStatus.connecting;
    notifyListeners();

    try {
      _signaling = SignalingService(
        serverUrl: serverUrl,
        onPeerList: (peers) {
          _onlinePeers = peers;
          notifyListeners();
        },
        onConnectionRequested: (from, sessionId) {
          // TODO: show notification
        },
        onConnectionAccepted: (sessionId, ip, port) {
          // TODO: initiate P2P connection
        },
      );

      await _signaling!.connect(hostname, os, version, listenPort);
      _connectionStatus = ConnectionStatus.connected;
    } catch (e) {
      _connectionStatus = ConnectionStatus.error;
    }
    notifyListeners();
  }

  void requestConnection(String targetPeerId) {
    _signaling?.requestConnection(targetPeerId, masterKey: _masterKey);
  }

  void disconnectFromServer() {
    _signaling?.disconnect();
    _signaling = null;
    _onlinePeers = [];
    _connectionStatus = ConnectionStatus.disconnected;
    notifyListeners();
  }
}
