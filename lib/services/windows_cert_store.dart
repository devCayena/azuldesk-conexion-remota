import 'dart:convert';
import 'dart:io';

/// Instala y lee el certificado AzulRemote en el almacén de certificados
/// de Windows (CurrentUser\My). El CN es fijo ("AzulRemote") en todos los PCs.
class WindowsCertStore {
  static const certName = 'AzulRemote';

  static const _begin = '-----BEGIN CERTIFICATE-----';
  static const _end = '-----END CERTIFICATE-----';

  static String? _certBlock(String pem) {
    final a = pem.indexOf(_begin);
    final b = pem.indexOf(_end, a + _begin.length);
    if (a == -1 || b == -1 || b <= a) return null;
    return pem.substring(a, b + _end.length);
  }

  /// Extrae solo el bloque base64 del certificado (sin cabeceras PEM).
  static String _bodyOnly(String block) {
    final body = block
        .replaceFirst(_begin, '')
        .replaceFirst(_end, '')
        .replaceAll(RegExp(r'\s'), '');
    final wrapped = <String>[];
    for (var i = 0; i < body.length; i += 64) {
      wrapped.add(body.substring(i, i + 64 > body.length ? body.length : i + 64));
    }
    return wrapped.join('\r\n');
  }

  /// Instala el certificado (público) en CurrentUser\My.
  /// Antes elimina cualquier cert AzulRemote previo para no acumular
  /// duplicados (certutil -addstore agrega, no reemplaza).
  static Future<bool> install(String certPem) async {
    if (!Platform.isWindows) return false;
    final block = _certBlock(certPem);
    if (block == null) return false;
    final dir = await Directory.systemTemp.createTemp('azuldesk');
    final cer = File('${dir.path}\\azulremote.cer');
    try {
      await _removeExisting();
      await cer.writeAsString(_bodyOnly(block));
      final r = await Process.run('certutil', ['-user', '-addstore', 'My', cer.path]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Elimina todos los certificados AzulRemote del store del usuario.
  static Future<void> _removeExisting() async {
    const script =
        "Get-ChildItem Cert:\\CurrentUser\\My | Where-Object { \$_.Subject -like '*AzulRemote*' } | Remove-Item";
    try {
      await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
    } catch (_) {}
  }

  /// Lee el certificado instalado con CN=AzulRemote que corresponde al serial
  /// del equipo (embebido como serialNumber en el subject). Si no hay match,
  /// devuelve el más reciente. Devuelve el PEM completo o null si no existe.
  static Future<String?> read({String? serialNumber}) async {
    if (!Platform.isWindows) return null;
    final serialFilter = (serialNumber == null || serialNumber.isEmpty)
        ? ''
        : " -and \$_.Subject -match 'serialNumber=$serialNumber'";
    final script =
        "\$c = Get-ChildItem Cert:\\CurrentUser\\My | Where-Object { \$_.Subject -like '*AzulRemote*'$serialFilter } | Sort-Object NotBefore -Descending | Select-Object -First 1; "
        "if (\$c) { [Convert]::ToBase64String(\$c.RawData) }";
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script]);
      if (r.exitCode != 0) return null;
      final b64 = (r.stdout as String).trim();
      if (b64.isEmpty) return null;
      final der = base64Decode(b64);
      final b64body = base64Encode(der);
      final lines = <String>[];
      for (var i = 0; i < b64body.length; i += 64) {
        lines.add(b64body.substring(i, i + 64 > b64body.length ? b64body.length : i + 64));
      }
      return '$_begin\n${lines.join('\n')}\n$_end';
    } catch (_) {
      return null;
    }
  }
}
