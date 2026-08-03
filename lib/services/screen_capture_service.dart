import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;

final class BITMAPINFOHEADER extends Struct {
  @Uint32() external int biSize;
  @Int32() external int biWidth;
  @Int32() external int biHeight;
  @Uint16() external int biPlanes;
  @Uint16() external int biBitCount;
  @Uint32() external int biCompression;
  @Uint32() external int biSizeImage;
  @Int32() external int biXPelsPerMeter;
  @Int32() external int biYPelsPerMeter;
  @Uint32() external int biClrUsed;
  @Uint32() external int biClrImportant;
}

final class BITMAPINFO extends Struct {
  external BITMAPINFOHEADER bmiHeader;
}

void _captureIsolate(SendPort sendPort) {
  final user32 = DynamicLibrary.open('user32.dll');
  final gdi32 = DynamicLibrary.open('gdi32.dll');

  final getSystemMetrics = user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics');
  final getDC = user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetDC');
  final releaseDC = user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('ReleaseDC');
  final createCompatibleDC = gdi32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('CreateCompatibleDC');
  final createCompatibleBitmap = gdi32.lookupFunction<IntPtr Function(IntPtr, Int32, Int32), int Function(int, int, int)>('CreateCompatibleBitmap');
  final selectObject = gdi32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('SelectObject');
  final bitBlt = gdi32.lookupFunction<Int32 Function(IntPtr, Int32, Int32, Int32, Int32, IntPtr, Int32, Int32, Uint32), int Function(int, int, int, int, int, int, int, int, int)>('BitBlt');
  final getDIBits = gdi32.lookupFunction<Int32 Function(IntPtr, IntPtr, Uint32, Uint32, Pointer<Void>, Pointer<BITMAPINFO>, Uint32), int Function(int, int, int, int, Pointer<Void>, Pointer<BITMAPINFO>, int)>('GetDIBits');
  final deleteDC = gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteDC');
  final deleteObject = gdi32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DeleteObject');

  final screenW = getSystemMetrics(0);
  final screenH = getSystemMetrics(1);

  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message == 'exit') {
      Isolate.exit();
      return;
    }

    final msg = message as _CaptureMessage;
    // If maxDimension is 0, return screen dimensions
    if (msg.maxDimension == 0) {
      msg.replyPort.send([screenW, screenH]);
      return;
    }

    final hdcScreen = getDC(0);
    if (hdcScreen == 0) { msg.replyPort.send(null); return; }

    final hdcMem = createCompatibleDC(hdcScreen);
    if (hdcMem == 0) { releaseDC(0, hdcScreen); msg.replyPort.send(null); return; }

    final hBitmap = createCompatibleBitmap(hdcScreen, screenW, screenH);
    if (hBitmap == 0) { deleteDC(hdcMem); releaseDC(0, hdcScreen); msg.replyPort.send(null); return; }

    final hOld = selectObject(hdcMem, hBitmap);
    bitBlt(hdcMem, 0, 0, screenW, screenH, hdcScreen, 0, 0, 0x00CC0020);

    final bi = calloc<BITMAPINFO>();
    bi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bi.ref.bmiHeader.biWidth = screenW;
    bi.ref.bmiHeader.biHeight = -screenH;
    bi.ref.bmiHeader.biPlanes = 1;
    bi.ref.bmiHeader.biBitCount = 32;
    bi.ref.bmiHeader.biCompression = 0;

    final bufSize = screenW * screenH * 4;
    final buffer = calloc<Uint8>(bufSize);
    getDIBits(hdcMem, hBitmap, 0, screenH, buffer.cast<Void>(), bi, 0);

    final pixels = buffer.asTypedList(bufSize);
    final rawImage = img.Image.fromBytes(
      width: screenW, height: screenH,
      bytes: pixels.buffer,
      numChannels: 4, order: img.ChannelOrder.bgra,
    );

    selectObject(hdcMem, hOld);
    deleteObject(hBitmap);
    deleteDC(hdcMem);
    releaseDC(0, hdcScreen);
    calloc.free(bi);
    calloc.free(buffer);

    if (rawImage == null) { msg.replyPort.send(null); return; }

    final maxDim = msg.maxDimension;
    img.Image scaled;
    if (maxDim > 0 && (screenW > maxDim || screenH > maxDim)) {
      int newW, newH;
      if (screenW > screenH) {
        newW = maxDim;
        newH = (screenH * maxDim / screenW).round();
      } else {
        newH = maxDim;
        newW = (screenW * maxDim / screenH).round();
      }
      scaled = img.copyResize(rawImage, width: newW, height: newH);
    } else {
      scaled = rawImage;
    }

    final jpeg = img.encodeJpg(scaled, quality: msg.quality);
    msg.replyPort.send(Uint8List.fromList(jpeg));
  });
}

class _CaptureMessage {
  final int maxDimension;
  final int quality;
  final SendPort replyPort;
  _CaptureMessage(this.maxDimension, this.quality, this.replyPort);
}

class ScreenCaptureService {
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static ReceivePort? _receivePort;
  static int screenWidth = 1920;
  static int screenHeight = 1080;

  static Future<void> start() async {
    if (!Platform.isWindows) return;
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_captureIsolate, _receivePort!.sendPort);
    _sendPort = await _receivePort!.first as SendPort;
    // Get screen dimensions for mouse scaling
    final resp = ReceivePort();
    _sendPort!.send(_CaptureMessage(0, 0, resp.sendPort));
    final dims = await resp.first;
    resp.close();
    if (dims is List<int> && dims.length == 2) {
      screenWidth = dims[0];
      screenHeight = dims[1];
    }
  }

  static void stop() {
    _sendPort?.send('exit');
    _sendPort = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate?.kill();
    _isolate = null;
  }

  static Future<Uint8List?> captureFrame({int maxDimension = 1600, int quality = 55}) async {
    if (!Platform.isWindows || _sendPort == null) return null;
    final response = ReceivePort();
    _sendPort!.send(_CaptureMessage(maxDimension, quality, response.sendPort));
    final result = await response.first;
    response.close();
    return result as Uint8List?;
  }
}
