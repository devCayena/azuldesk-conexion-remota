import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/device_info.dart';
import '../services/signaling_service.dart';
import '../services/device_identity.dart';
import '../services/audio_service.dart';
import '../services/file_logger.dart';
import '../services/session_service.dart';
import '../services/screen_capture_service.dart';
import '../services/input_service.dart';

class AppState extends ChangeNotifier {
  static const String _defineServerHost = String.fromEnvironment('SERVER_HOST');

  static String get _defaultServerHost {
    if (_defineServerHost.isNotEmpty) return _defineServerHost;
    return dotenv.get('SERVER_HOST', fallback: 'http://127.0.0.1:7981');
  }

  List<OnlinePeer> _onlinePeers = [];
  RemoteSession? _activeSession;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String? _masterKey;
  String _serverHost = _defaultServerHost;
  SignalingService? _signaling;

  // Auth
  bool _authenticated = false;
  int _userId = 0;
  String _userName = '';
  String _userRole = '';

  // Device
  String _deviceId = '';
  String _deviceName = '';
  String _version = '';

  // Remote session
  String? _sessionId;
  Completer<void>? _sessionReady;
  AudioService? _hostAudio;
  SessionService? _hostSession;
  int _captureQuality = 85;

  // Connection logs
  List<String> _connectionLogs = [];

  List<OnlinePeer> get onlinePeers => _onlinePeers;
  RemoteSession? get activeSession => _activeSession;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String? get masterKey => _masterKey;
  String get serverHost => _serverHost;
  String get serverUrl => _serverHost.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://') + '/ws/';
  String get httpUrl => _serverHost + '/api/';
  bool get authenticated => _authenticated;
  int get userId => _userId;
  String get userName => _userName;
  bool get isAdmin => _userRole == 'admin';
  bool get isSupport => _userRole == 'support';
  String get userRole => _userRole;
  String get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get appVersion => _version;
  String? get sessionId => _sessionId;
  List<String> get connectionLogs => _connectionLogs;
  Completer<void>? get sessionIdCompleter {
    _sessionReady ??= Completer<void>();
    return _sessionReady;
  }

  void setServerHost(String host) {
    _serverHost = host.replaceAll(RegExp(r'/$'), '');
    notifyListeners();
  }

  void setMasterKey(String? key) { _masterKey = key; notifyListeners(); }

  String get audioUrl => _serverHost;

  Future<void> login(int userId, String name, String role) async {
    _userId = userId;
    _userName = name;
    _userRole = role;
    _authenticated = true;
    notifyListeners();
  }

  void logout() {
    disconnectFromServer();
    _hostAudio?.dispose();
    _hostAudio = null;
    _authenticated = false;
    _userId = 0;
    _userName = '';
    _userRole = '';
    _deviceId = '';
    notifyListeners();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toString().substring(11, 19);
    _connectionLogs.insert(0, '[$time] $msg');
    if (_connectionLogs.length > 50) _connectionLogs.removeLast();
    debugPrint('[Signaling] $msg');
    FileLogger.instance.log(msg);
  }

  /// Expone el registro para que servicios (audio, etc.) agreguen logs
  /// visibles y copiables desde la app.
  void log(String msg) => _addLog(msg);

  Future<void> connectToServer(String hostname, String os, int listenPort) async {
    if (_connectionStatus == ConnectionStatus.connecting ||
        _connectionStatus == ConnectionStatus.connected) {
      _addLog('Ya hay una conexión activa, omitiendo duplicado');
      return;
    }
    _connectionLogs = [];
    _connectionStatus = ConnectionStatus.connecting;

    // Cargar versión de la app
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
    } catch (_) {
      _version = '1.0.0';
    }
    final version = _version;
    _addLog('Iniciando conexión a $serverUrl (v$version)');
    notifyListeners();

    try {
      // 1. Cargar o crear serial persistente del equipo
      await DeviceIdentity.load();
      await DeviceIdentity.ensureSerial();
      final serial = DeviceIdentity.serialNumber!;
      _addLog('Serial del equipo: $serial');
      _addLog(DeviceIdentity.hasCertificate ? 'Certificado local presente' : 'Primera vez: sin certificado');

      _signaling = SignalingService(
        serverUrl: serverUrl,
        onPeerList: (peers) {
          _onlinePeers = peers;
          _addLog('${peers.length} peers en línea');
          notifyListeners();
        },
        onCertificate: (certPem, serialNumber) {
          DeviceIdentity.saveCertificate(certPem);
          _addLog('Certificado emitido por el servidor y guardado');
        },
        onConnectionRequested: (from, sessionId) {
          if (from.peerId == _deviceId) {
            _addLog('Ignorando solicitud propia (eco del servidor)');
            return;
          }
          _addLog('Solicitud de conexión de ${from.peerId}');
          final me = _onlinePeers.where((p) => p.peerId == _deviceId).firstOrNull;
          _signaling?.respondToConnection(
            sessionId,
            accepted: true,
            targetIp: me?.publicIp,
            targetPort: 7890,
          );
          _addLog('Conexión aceptada: $sessionId');
          _sessionId = sessionId;
          _sessionReady?.complete();
          _sessionReady = null;
          // Host se une al relay de audio
          _hostAudio ??= AudioService();
          _hostAudio!.onLog = (msg) => _addLog('Audio: $msg');
          _hostAudio!.startCall(audioUrl, sessionId).catchError((e) {
            _addLog('Error de audio (host): $e');
          });
          // Host inicia relay de sesión (pantalla + input)
          _startHostSession(sessionId);
          notifyListeners();
        },
        onConnectionAccepted: (sessionId, ip, port) {
          _sessionId = sessionId;
          _addLog('Conexión aceptada: $sessionId');
          _sessionReady?.complete();
          _sessionReady = null;
          notifyListeners();
        },
        onRegistered: (peerId) {
          _deviceId = peerId;
          _addLog('ID de conexión asignado: $peerId');
          notifyListeners();
        },
        onError: (code, message) {
          _addLog('Servidor rechazó: $message');
          if (code == 403) {
            _connectionStatus = ConnectionStatus.error;
            notifyListeners();
          }
        },
        onLog: (msg) => _addLog(msg),
      );

      // 2. Conectar y registrar (servidor revisa serial + certificado)
      await _signaling!.connect(hostname, os, version, listenPort,
          serialNumber: serial, certificate: DeviceIdentity.certificatePem);
      _connectionStatus = ConnectionStatus.connected;
      _addLog('Conectado al servidor');
    } catch (e) {
      _connectionStatus = ConnectionStatus.error;
      _addLog('Error: $e');
    }
    notifyListeners();
  }

  void requestConnection(String targetPeerId) {
    if (!_authenticated) return;
    _sessionId = null;
    _sessionReady = Completer<void>();
    _addLog('Solicitando conexión a $targetPeerId');
    _signaling?.requestConnection(targetPeerId, masterKey: _masterKey);
  }

  void _startHostSession(String sessionId) {
    _hostSession?.disconnect();
    _hostSession = SessionService();
    _hostSession!.onLog = (msg) => _addLog(msg);
    _hostSession!.onInputEvent = (event) {
      final type = event['type'] as String?;
      if (type == null) return;
      switch (type) {
        case 'mouse_move':
          InputService.mouseMove(
            (event['dx'] as num?)?.toInt() ?? 0,
            (event['dy'] as num?)?.toInt() ?? 0,
          );
          break;
        case 'mouse_down':
          InputService.mouseDown((event['button'] as num?)?.toInt() ?? 1);
          break;
        case 'mouse_up':
          InputService.mouseUp((event['button'] as num?)?.toInt() ?? 1);
          break;
        case 'mouse_wheel':
          InputService.mouseWheel((event['delta'] as num?)?.toInt() ?? 0);
          break;
        case 'key_down':
          InputService.keyDown((event['key'] as num?)?.toInt() ?? 0);
          break;
        case 'key_up':
          InputService.keyUp((event['key'] as num?)?.toInt() ?? 0);
          break;
        case 'clipboard':
          final text = event['text'] as String?;
          if (text != null) {
            _addLog('Clipboard recibido: ${text.length} chars');
          }
          break;
        case 'quality':
          _captureQuality = (event['value'] as num?)?.toInt() ?? 60;
          _addLog('Calidad cambiada a $_captureQuality');
          break;
      }
    };
    _hostSession!.onDone = () {
      _addLog('Sesión remota finalizada');
      _stopHostSession();
    };

    _hostSession!.connect(audioUrl, sessionId).then((_) async {
      _addLog('Captura de pantalla iniciada');
      await ScreenCaptureService.start();
      // Enviar info de pantalla al cliente para que escale el mouse
      _hostSession?.sendInputEvent({
        'type': 'screen_info', 'w': ScreenCaptureService.screenWidth, 'h': ScreenCaptureService.screenHeight,
      });
      while (_hostSession?.isConnected == true) {
        try {
          final frame = await ScreenCaptureService.captureFrame(maxDimension: 1600, quality: _captureQuality);
          if (frame != null && _hostSession?.isConnected == true) {
            _hostSession!.sendFrame(frame);
          }
        } catch (e) {
          _addLog('Error en captura: $e');
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }
      ScreenCaptureService.stop();
    }).catchError((e) {
      _addLog('Error al iniciar sesión remota: $e');
      _stopHostSession();
    });
  }

  void _stopHostSession() {
    _hostSession?.onDone = null;
    _hostSession?.onLog = null;
    _hostSession?.onInputEvent = null;
    _hostSession?.disconnect();
    _hostSession = null;
    ScreenCaptureService.stop();
    _addLog('Sesión remota detenida');
  }

  void disconnectFromServer() {
    _signaling?.disconnect();
    _signaling = null;
    _stopHostSession();
    _hostAudio?.dispose();
    _hostAudio = null;
    _onlinePeers = [];
    _connectionStatus = ConnectionStatus.disconnected;
    _addLog('Desconectado');
    notifyListeners();
  }
}
