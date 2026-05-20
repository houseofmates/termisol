typedef CharsetTranslator = int Function(int);

final _charsets = <int, CharsetTranslator>{
  '0'.codeUnitAt(0): decSpecGraphicsTranslator,
  'B'.codeUnitAt(0): asciiTranslator,
};

class Charset {
  var _charsetMap = <int, CharsetTranslator>{};
  var _currentIndex = 0;

  var _savedCharsetMap = <int, CharsetTranslator>{};
  var _savedIndex = 0;

  var _cached = asciiTranslator;

  void _updateCache() {
    _cached = _charsetMap[_currentIndex] ?? asciiTranslator;
  }

  int translate(int codePoint) {
    return _cached(codePoint);
  }

  void designate(int index, int name) {
    final charset = _charsets[name];
    if (charset != null) {
      _charsetMap[index] = charset;
      _updateCache();
    }
  }

  void use(int index) {
    _currentIndex = index;
    _updateCache();
  }

  void save() {
    _savedCharsetMap = Map.from(_charsetMap);
    _savedIndex = _currentIndex;
  }

  void restore() {
    _charsetMap = _savedCharsetMap;
    _currentIndex = _savedIndex;
    _updateCache();
  }
}

const decSpecGraphics = <int, int>{
  0x5f: 0x00A0, // no-break space
  0x60: 0x25C6, // black diamond
  0x61: 0x2592, // medium shade
  0x62: 0x2409, // symbol for horizontal tabulation
  0x63: 0x240C, // symbol for form feed
  0x64: 0x240D, // symbol for carriage return
  0x65: 0x240A, // symbol for line feed
  0x66: 0x00B0, // degree sign
  0x67: 0x00B1, // plus-minus sign
  0x68: 0x2424, // symbol for newline
  0x69: 0x240B, // symbol for vertical tabulation
  0x6a: 0x2518, // box drawings light up and left
  0x6b: 0x2510, // box drawings light down and left
  0x6c: 0x250C, // box drawings light down and right
  0x6d: 0x2514, // box drawings light up and right
  0x6e: 0x253C, // box drawings light vertical and horizontal
  0x6f: 0x23BA, // horizontal scan line-1
  0x70: 0x23BB, // horizontal scan line-3
  0x71: 0x2500, // box drawings light horizontal
  0x72: 0x23BC, // horizontal scan line-7
  0x73: 0x23BD, // horizontal scan line-9
  0x74: 0x251C, // box drawings light vertical and right
  0x75: 0x2524, // box drawings light vertical and left
  0x76: 0x2534, // box drawings light up and horizontal
  0x77: 0x252C, // box drawings light down and horizontal
  0x78: 0x2502, // box drawings light vertical
  0x79: 0x2264, // less-than or equal to
  0x7a: 0x2265, // greater-than or equal to
  0x7b: 0x03C0, // greek small letter pi
  0x7c: 0x2260, // not equal to
  0x7d: 0x00A3, // pound sign
  0x7e: 0x00B7, // middle dot
};

int asciiTranslator(int codePoint) {
  return codePoint;
}

int decSpecGraphicsTranslator(int codePoint) {
  if (codePoint >= 127) {
    return codePoint;
  }

  return decSpecGraphics[codePoint] ?? codePoint;
}
