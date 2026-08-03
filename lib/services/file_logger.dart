import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Escribe logs de la app a un archivo persistente.
/// En Android el archivo queda en el directorio de documentos de la app
/// (visible con un file manager) y en desktop en el directorio de soporte.
/// Al iniciar, si el archivo supera [maxBytes] se trunca dejando solo la
/// última porción (deja de crecer sin límite).
class FileLogger {
  static final FileLogger instance = FileLogger._();
  FileLogger._();

  static const int maxBytes = 2 * 1024 * 1024; // 2 MB
  static const String _fileName = 'azuldesk.log';

  File? _file;
  String? _dirPath;

  bool get isReady => _file != null;
  String get path => _file?.path ?? '';
  String get dirPath => _dirPath ?? '';

  /// Ubica el directorio de logs según la plataforma.
  Future<Directory> _logDirectory() async {
    if (Platform.isAndroid) {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/AzulDesk');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Inicializa el logger. Si el archivo ya existe y supera [maxBytes],
  /// lo trunca conservando solo la última porción.
  Future<void> init() async {
    try {
      final dir = await _logDirectory();
      _dirPath = dir.path;
      final file = File('${dir.path}${Platform.pathSeparator}$_fileName');
      if (await file.exists()) {
        final size = await file.length();
        if (size > maxBytes) {
          final raf = await file.open(mode: FileMode.writeOnly);
          await raf.truncate(0);
          await raf.close();
        }
      }
      _file = file;
    } catch (_) {
      _file = null;
    }
  }

  void log(String message) {
    final file = _file;
    if (file == null) return;
    try {
      final line = '${DateTime.now().toIso8601String()} $message\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void error(String message) {
    log('ERROR: $message');
  }
}
