import 'package:flutter/services.dart';

/// Traduce una [LogicalKeyboardKey] de Flutter a un Virtual-Key code de
/// Windows, que es lo que espera `SendInput` en el equipo remoto
/// (ver input_service.dart, InputService.keyDown/keyUp).
///
/// Por que hace falta esto: LogicalKeyboardKey.keyId para las letras usa el
/// codepoint Unicode en minuscula (ej. 'a' = 0x61), mientras que el VK code
/// de Windows para las letras es el ASCII en MAYUSCULA (VK_A = 0x41). Si se
/// manda el keyId de Flutter directo a SendInput, 0x61 termina interpretado
/// como VK_NUMPAD1 y el teclado remoto escribe cosas completamente distintas
/// a lo que se tecleo. Lo mismo pasa con signos de puntuacion (los VK_OEM_*
/// no coinciden con el codepoint ASCII) y con teclas no imprimibles.
///
/// Se construye a partir de las constantes reales de LogicalKeyboardKey en
/// vez de numeros fijos, para no depender de los valores internos de Flutter.
int? vkFromLogicalKey(LogicalKeyboardKey key) {
  return _map[key];
}

final Map<LogicalKeyboardKey, int> _map = {
  // Letras: VK_A..VK_Z = 0x41..0x5A
  LogicalKeyboardKey.keyA: 0x41, LogicalKeyboardKey.keyB: 0x42,
  LogicalKeyboardKey.keyC: 0x43, LogicalKeyboardKey.keyD: 0x44,
  LogicalKeyboardKey.keyE: 0x45, LogicalKeyboardKey.keyF: 0x46,
  LogicalKeyboardKey.keyG: 0x47, LogicalKeyboardKey.keyH: 0x48,
  LogicalKeyboardKey.keyI: 0x49, LogicalKeyboardKey.keyJ: 0x4A,
  LogicalKeyboardKey.keyK: 0x4B, LogicalKeyboardKey.keyL: 0x4C,
  LogicalKeyboardKey.keyM: 0x4D, LogicalKeyboardKey.keyN: 0x4E,
  LogicalKeyboardKey.keyO: 0x4F, LogicalKeyboardKey.keyP: 0x50,
  LogicalKeyboardKey.keyQ: 0x51, LogicalKeyboardKey.keyR: 0x52,
  LogicalKeyboardKey.keyS: 0x53, LogicalKeyboardKey.keyT: 0x54,
  LogicalKeyboardKey.keyU: 0x55, LogicalKeyboardKey.keyV: 0x56,
  LogicalKeyboardKey.keyW: 0x57, LogicalKeyboardKey.keyX: 0x58,
  LogicalKeyboardKey.keyY: 0x59, LogicalKeyboardKey.keyZ: 0x5A,

  // Digitos fila superior: VK_0..VK_9 = 0x30..0x39 (coincide con ASCII,
  // pero los mapeamos explicitamente igual por claridad y consistencia).
  LogicalKeyboardKey.digit0: 0x30, LogicalKeyboardKey.digit1: 0x31,
  LogicalKeyboardKey.digit2: 0x32, LogicalKeyboardKey.digit3: 0x33,
  LogicalKeyboardKey.digit4: 0x34, LogicalKeyboardKey.digit5: 0x35,
  LogicalKeyboardKey.digit6: 0x36, LogicalKeyboardKey.digit7: 0x37,
  LogicalKeyboardKey.digit8: 0x38, LogicalKeyboardKey.digit9: 0x39,

  // Numpad: VK_NUMPAD0..9 = 0x60..0x69
  LogicalKeyboardKey.numpad0: 0x60, LogicalKeyboardKey.numpad1: 0x61,
  LogicalKeyboardKey.numpad2: 0x62, LogicalKeyboardKey.numpad3: 0x63,
  LogicalKeyboardKey.numpad4: 0x64, LogicalKeyboardKey.numpad5: 0x65,
  LogicalKeyboardKey.numpad6: 0x66, LogicalKeyboardKey.numpad7: 0x67,
  LogicalKeyboardKey.numpad8: 0x68, LogicalKeyboardKey.numpad9: 0x69,
  LogicalKeyboardKey.numpadMultiply: 0x6A,
  LogicalKeyboardKey.numpadAdd: 0x6B,
  LogicalKeyboardKey.numpadSubtract: 0x6D,
  LogicalKeyboardKey.numpadDecimal: 0x6E,
  LogicalKeyboardKey.numpadDivide: 0x6F,

  // Funcion: VK_F1..VK_F24 = 0x70..0x87
  LogicalKeyboardKey.f1: 0x70, LogicalKeyboardKey.f2: 0x71,
  LogicalKeyboardKey.f3: 0x72, LogicalKeyboardKey.f4: 0x73,
  LogicalKeyboardKey.f5: 0x74, LogicalKeyboardKey.f6: 0x75,
  LogicalKeyboardKey.f7: 0x76, LogicalKeyboardKey.f8: 0x77,
  LogicalKeyboardKey.f9: 0x78, LogicalKeyboardKey.f10: 0x79,
  LogicalKeyboardKey.f11: 0x7A, LogicalKeyboardKey.f12: 0x7B,
  LogicalKeyboardKey.f13: 0x7C, LogicalKeyboardKey.f14: 0x7D,
  LogicalKeyboardKey.f15: 0x7E, LogicalKeyboardKey.f16: 0x7F,
  LogicalKeyboardKey.f17: 0x80, LogicalKeyboardKey.f18: 0x81,
  LogicalKeyboardKey.f19: 0x82, LogicalKeyboardKey.f20: 0x83,

  // Control / navegacion
  LogicalKeyboardKey.backspace: 0x08,
  LogicalKeyboardKey.tab: 0x09,
  LogicalKeyboardKey.enter: 0x0D,
  LogicalKeyboardKey.numpadEnter: 0x0D,
  LogicalKeyboardKey.shiftLeft: 0xA0,
  LogicalKeyboardKey.shiftRight: 0xA1,
  LogicalKeyboardKey.shift: 0x10,
  LogicalKeyboardKey.controlLeft: 0xA2,
  LogicalKeyboardKey.controlRight: 0xA3,
  LogicalKeyboardKey.control: 0x11,
  LogicalKeyboardKey.altLeft: 0xA4,
  LogicalKeyboardKey.altRight: 0xA5,
  LogicalKeyboardKey.alt: 0x12,
  LogicalKeyboardKey.pause: 0x13,
  LogicalKeyboardKey.capsLock: 0x14,
  LogicalKeyboardKey.escape: 0x1B,
  LogicalKeyboardKey.space: 0x20,
  LogicalKeyboardKey.pageUp: 0x21,
  LogicalKeyboardKey.pageDown: 0x22,
  LogicalKeyboardKey.end: 0x23,
  LogicalKeyboardKey.home: 0x24,
  LogicalKeyboardKey.arrowLeft: 0x25,
  LogicalKeyboardKey.arrowUp: 0x26,
  LogicalKeyboardKey.arrowRight: 0x27,
  LogicalKeyboardKey.arrowDown: 0x28,
  LogicalKeyboardKey.printScreen: 0x2C,
  LogicalKeyboardKey.insert: 0x2D,
  LogicalKeyboardKey.delete: 0x2E,
  LogicalKeyboardKey.numLock: 0x90,
  LogicalKeyboardKey.scrollLock: 0x91,
  LogicalKeyboardKey.metaLeft: 0x5B,
  LogicalKeyboardKey.metaRight: 0x5C,
  LogicalKeyboardKey.contextMenu: 0x5D,

  // Puntuacion (VK_OEM_*, no coinciden con el codepoint ASCII)
  LogicalKeyboardKey.semicolon: 0xBA,
  LogicalKeyboardKey.equal: 0xBB,
  LogicalKeyboardKey.comma: 0xBC,
  LogicalKeyboardKey.minus: 0xBD,
  LogicalKeyboardKey.period: 0xBE,
  LogicalKeyboardKey.slash: 0xBF,
  LogicalKeyboardKey.backquote: 0xC0,
  LogicalKeyboardKey.bracketLeft: 0xDB,
  LogicalKeyboardKey.backslash: 0xDC,
  LogicalKeyboardKey.bracketRight: 0xDD,
  LogicalKeyboardKey.quote: 0xDE,
};
