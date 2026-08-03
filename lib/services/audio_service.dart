import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'file_logger.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  WebSocketChannel? _channel;
  StreamSubscription? _recordSub;
  StreamSubscription? _wsSub;

  bool _micOn = false;
  bool _speakerOn = false;

  bool get isMicOn => _micOn;
  bool get isSpeakerOn => _speakerOn;

  void Function(bool enabled)? onMicChanged;
  void Function(double volume)? onVolumeChanged;
  void Function(String msg)? onLog;

  void _log(String msg) {
    FileLogger.instance.log('[Audio] $msg');
    onLog?.call(msg);
  }

  Future<void> startCall(String serverUrl, String sessionId) async {
    var base = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://')
        .replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/audio/$sessionId');
    _log('Conectando relay de audio: $uri');

    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    _log('Relay de audio conectado ($sessionId)');

    _speakerOn = true;

    _wsSub = _channel!.stream.listen(
      (data) {
        if (data is List<int>) {
          final bytes = Uint8List.fromList(data);
          _playAudio(bytes);
        }
      },
      onDone: () {
        _log('Relay de audio cerrado');
        _stopCall();
      },
      onError: (e) {
        _log('Error en relay de audio: $e');
        _stopCall();
      },
    );

    if (_micOn) {
      _startCapture();
    }
  }

  void _playAudio(Uint8List pcmData) async {
    if (!_speakerOn) return;
    final wav = _pcmToWav(pcmData, 44100);
    await _player.play(BytesSource(Uint8List.fromList(wav)));
  }

  void toggleMic() {
    _micOn = !_micOn;
    onMicChanged?.call(_micOn);
    if (_micOn) {
      _startCapture();
    } else {
      _stopCapture();
    }
  }

  Future<void> _startCapture() async {
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 44100,
        ),
      );
      _recordSub = stream.listen(
        (data) {
          if (_channel != null) {
            _channel!.sink.add(data);
          }
        },
        onError: (_) {},
      );
    } catch (e) {
      _micOn = false;
      onMicChanged?.call(false);
    }
  }

  void _stopCapture() {
    _recordSub?.cancel();
    _recordSub = null;
    _recorder.stop();
  }

  bool _disposed = false;

  void _stopCall() {
    if (_disposed) return;
    _stopCapture();
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _speakerOn = false;
    _micOn = false;
    _log('Llamada de audio detenida');
    onMicChanged?.call(false);
  }

  Uint8List _pcmToWav(Uint8List pcmData, int sampleRate) {
    final bitsPerSample = 16;
    final numChannels = 1;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final headerSize = 44;
    final totalSize = headerSize + dataSize;

    final wav = ByteData(totalSize);

    wav.setUint8(0, 0x52); wav.setUint8(1, 0x49);
    wav.setUint8(2, 0x46); wav.setUint8(3, 0x46);
    wav.setUint32(4, totalSize - 8, Endian.little);
    wav.setUint8(8, 0x57); wav.setUint8(9, 0x41);
    wav.setUint8(10, 0x56); wav.setUint8(11, 0x45);
    wav.setUint8(12, 0x66); wav.setUint8(13, 0x6D);
    wav.setUint8(14, 0x74); wav.setUint8(15, 0x20);
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, numChannels, Endian.little);
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, byteRate, Endian.little);
    wav.setUint16(32, blockAlign, Endian.little);
    wav.setUint16(34, bitsPerSample, Endian.little);
    wav.setUint8(36, 0x64); wav.setUint8(37, 0x61);
    wav.setUint8(38, 0x74); wav.setUint8(39, 0x61);
    wav.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < dataSize; i++) {
      wav.setUint8(headerSize + i, pcmData[i]);
    }

    return wav.buffer.asUint8List();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try { _stopCall(); } catch (_) {}
    try { _recorder.dispose(); } catch (_) {}
    try { _player.dispose(); } catch (_) {}
  }
}
