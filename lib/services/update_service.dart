import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateManifest {
  final String version;
  final String downloadUrl;
  final String checksum;
  final bool mandatory;
  final String releaseNotes;

  UpdateManifest({
    required this.version,
    required this.downloadUrl,
    this.checksum = '',
    this.mandatory = false,
    this.releaseNotes = '',
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) => UpdateManifest(
    version: json['version'],
    downloadUrl: json['download_url'],
    checksum: json['checksum'] ?? '',
    mandatory: json['mandatory'] ?? false,
    releaseNotes: json['release_notes'] ?? '',
  );
}

class UpdateService {
  final String serverUrl;

  UpdateService(this.serverUrl);

  Future<String> _getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  Future<UpdateManifest?> checkForUpdates() async {
    try {
      final url = '$serverUrl/updates/manifest.json';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final manifest = UpdateManifest.fromJson(json.decode(response.body));
      final currentVersion = await _getCurrentVersion();
      if (manifest.version == currentVersion) return null;
      return manifest;
    } catch (e) {
      return null;
    }
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$serverUrl/updates/$url';
  }

  Future<void> applyUpdate(UpdateManifest manifest) async {
    final downloadUrl = _resolveUrl(manifest.downloadUrl);
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Download failed: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    if (manifest.checksum.isNotEmpty) {
      final hash = sha256.convert(bytes).toString();
      if (hash != manifest.checksum) {
        throw Exception('Checksum mismatch');
      }
    }

    final ext = _getExtension();
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/azuldesk_update$ext';
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    // Open file with system installer
    await OpenFilex.open(filePath);

    // Delete after a delay so installer can read it first
    Future.delayed(const Duration(seconds: 10), () {
      file.delete().catchError((_) {});
    });

    if (!Platform.isAndroid && !Platform.isIOS) {
      exit(0);
    }
  }

  String _getExtension() {
    if (Platform.isAndroid) return '.apk';
    if (Platform.isWindows) return '.exe';
    if (Platform.isLinux) return '.AppImage';
    if (Platform.isMacOS) return '.dmg';
    return '.bin';
  }
}
