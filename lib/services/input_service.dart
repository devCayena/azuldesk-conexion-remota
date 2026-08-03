import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

final class _INPUT extends Struct {
  @Uint32() external int type;
  @Uint32() external int _padding;
}

class InputService {
  static bool _initialized = false;
  static DynamicLibrary? _user32;

  static int Function(int, Pointer<_INPUT>, int) _sendInputDart = (_, __, ___) => 0;

  static void _init() {
    if (_initialized) return;
    _initialized = true;
    if (!Platform.isWindows) return;
    _user32 = DynamicLibrary.open('user32.dll');
    _sendInputDart = _user32!
        .lookupFunction<Uint32 Function(Uint32, Pointer<_INPUT>, Int32), int Function(int, Pointer<_INPUT>, int)>('SendInput');
  }

  static const int _inputSize = 40; // sizeof(INPUT) on Windows x64
  static const int _INPUT_MOUSE = 0;
  static const int _INPUT_KEYBOARD = 1;

  static const int _MOUSEEVENTF_MOVE = 0x0001;
  static const int _MOUSEEVENTF_LEFTDOWN = 0x0002;
  static const int _MOUSEEVENTF_LEFTUP = 0x0004;
  static const int _MOUSEEVENTF_RIGHTDOWN = 0x0008;
  static const int _MOUSEEVENTF_RIGHTUP = 0x0010;
  static const int _MOUSEEVENTF_WHEEL = 0x0800;
  static const int _MOUSEEVENTF_ABSOLUTE = 0x8000;
  
  static const int _KEYEVENTF_KEYDOWN = 0x0000;
  static const int _KEYEVENTF_KEYUP = 0x0002;

  static void _sendMouseEvent(int x, int y, int flags, int mouseData, int dx, int dy) {
    _init();
    if (!Platform.isWindows) return;

    final buf = calloc<Uint8>(_inputSize);
    final input = buf.cast<_INPUT>();
    input.ref.type = _INPUT_MOUSE;
    input.ref._padding = 0;

    final union = Pointer<Uint32>.fromAddress(buf.address + 8);
    union[0] = dx;
    union[1] = dy;
    union[2] = mouseData;
    union[3] = flags;
    union[4] = 0; // time
    union[5] = 0; // padding
    union[6] = 0; // dwExtraInfo low
    union[7] = 0; // dwExtraInfo high

    _sendInputDart(1, input, _inputSize);
    calloc.free(buf);
  }

  static void mouseMove(int x, int y) {
    _sendMouseEvent(x, y, _MOUSEEVENTF_MOVE, 0, x, y);
  }

  static void mouseDown(int button) {
    final flag = button == 1 ? _MOUSEEVENTF_LEFTDOWN : _MOUSEEVENTF_RIGHTDOWN;
    _sendMouseEvent(0, 0, flag, 0, 0, 0);
  }

  static void mouseUp(int button) {
    final flag = button == 1 ? _MOUSEEVENTF_LEFTUP : _MOUSEEVENTF_RIGHTUP;
    _sendMouseEvent(0, 0, flag, 0, 0, 0);
  }

  static void mouseWheel(int delta) {
    _sendMouseEvent(0, 0, _MOUSEEVENTF_WHEEL, delta, 0, 0);
  }

  static void _sendKeyEvent(int vk, int flags) {
    _init();
    if (!Platform.isWindows) return;

    final buf = calloc<Uint8>(_inputSize);
    final input = buf.cast<_INPUT>();
    input.ref.type = _INPUT_KEYBOARD;
    input.ref._padding = 0;

    final union = Pointer<Uint32>.fromAddress(buf.address + 8);
    union[0] = vk;
    union[1] = flags;
    union[2] = 0; // time

    _sendInputDart(1, input, _inputSize);
    calloc.free(buf);
  }

  static void keyDown(int vk) {
    _sendKeyEvent(vk, _KEYEVENTF_KEYDOWN);
  }

  static void keyUp(int vk) {
    _sendKeyEvent(vk, _KEYEVENTF_KEYUP);
  }

  static void keyPress(int vk) {
    keyDown(vk);
    keyUp(vk);
  }
}
