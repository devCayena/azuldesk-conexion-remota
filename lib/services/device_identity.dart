import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'windows_cert_store.dart';

class DeviceIdentity {
  static const _fileName = 'device_identity.json';

  static String? _serialNumber;
  static String? _certificatePem;

  static String? get serialNumber => _serialNumber;
  static String? get certificatePem => _certificatePem;
  static bool get hasCertificate => _certificatePem != null && _certificatePem!.isNotEmpty;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}\\$_fileName');
  }

  static Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _serialNumber = data['serial_number'] as String?;
      }
    } catch (_) {}

    // Fuente de verdad: certificado INSTALADO en el store de Windows,
    // filtrado por el serial del equipo (evita leer un cert viejo o de otro PC).
    _certificatePem = await WindowsCertStore.read(serialNumber: _serialNumber);
    if (_certificatePem == null) {
      try {
        final file = await _file();
        if (await file.exists()) {
          final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _certificatePem = data['certificate'] as String?;
        }
      } catch (_) {}
    }
  }

  static Future<void> ensureSerial() async {
    if (_serialNumber != null) return;
    _serialNumber = _generateSerial();
    await save();
  }

  static String _generateSerial() {
    final chars = '0123456789ABCDEF';
    final rnd = Random();
    return List.generate(12, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  static Future<void> saveCertificate(String certPem) async {
    _certificatePem = certPem;
    await WindowsCertStore.install(certPem);
    await save();
  }

  static Future<void> save() async {
    try {
      final file = await _file();
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'serial_number': _serialNumber,
        'certificate': _certificatePem,
      }));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _serialNumber = null;
    _certificatePem = null;
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
