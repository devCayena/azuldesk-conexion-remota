class DeviceInfo {
  final String peerId;
  final String hostname;
  final String os;
  final String version;
  final String? publicIp;

  DeviceInfo({
    required this.peerId,
    required this.hostname,
    required this.os,
    required this.version,
    this.publicIp,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
    peerId: json['peer_id'],
    hostname: json['hostname'],
    os: json['os'],
    version: json['version'],
    publicIp: json['public_ip'],
  );
}

class OnlinePeer {
  final String peerId;
  final String hostname;
  final String os;
  final String version;
  final String publicIp;
  final int listenPort;
  final String lastSeen;

  OnlinePeer({
    required this.peerId,
    required this.hostname,
    required this.os,
    required this.version,
    required this.publicIp,
    required this.listenPort,
    required this.lastSeen,
  });

  /// ID de conexión corto en formato XXXX-XXXX-XXXX, derivado igual que el
  /// servidor (primeros 12 chars del hash SHA-256 del serial, en mayúsculas).
  String get connectionId {
    final id = peerId;
    if (id.length < 12) return id.toUpperCase();
    return '${id.substring(0, 4)}-${id.substring(4, 8)}-${id.substring(8, 12)}'.toUpperCase();
  }

  factory OnlinePeer.fromJson(Map<String, dynamic> json) => OnlinePeer(
    peerId: json['peer_id'],
    hostname: json['hostname'],
    os: json['os'],
    version: json['version'],
    publicIp: json['public_ip'],
    listenPort: json['listen_port'] ?? 7890,
    lastSeen: json['last_seen'],
  );
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class RemoteSession {
  final String sessionId;
  final String peerId;
  final String hostname;
  final ConnectionStatus status;
  final DateTime startedAt;

  RemoteSession({
    required this.sessionId,
    required this.peerId,
    required this.hostname,
    required this.status,
    required this.startedAt,
  });
}
