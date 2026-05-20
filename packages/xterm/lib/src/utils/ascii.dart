// ignore_for_file: constant_identifier_names

abstract class Ascii {
  /*
   * helper functions
   */

  static bool isNonPrintable(int c) {
    return c < 32 || c == 127;
  }

  /*
   * non-printable ascii characters
   */

  ///  null character
  static const NULL = 00;

  ///  start of header
  static const SOH = 01;

  ///  start of text
  static const STX = 02;

  ///  end of text, hearts card suit
  static const ETX = 03;

  ///  end of transmission, diamonds card suit
  static const EOT = 04;

  ///  enquiry, clubs card suit
  static const ENQ = 05;

  ///  acknowledgement, spade card suit
  static const ACK = 06;

  ///  bell
  static const BEL = 07;

  ///  backspace
  static const BS = 08;

  ///  horizontal tab
  static const HT = 09;

  ///  line feed
  static const LF = 10;

  ///  vertical tab, male symbol, symbol for mars
  static const VT = 11;

  ///  form feed, female symbol, symbol for venus
  static const FF = 12;

  ///  carriage return
  static const CR = 13;

  ///  shift out
  static const SO = 14;

  ///  shift in
  static const SI = 15;

  ///  data link escape
  static const DLE = 16;

  ///  device control 1
  static const DC1 = 17;

  ///  device control 2
  static const DC2 = 18;

  ///  device control 3
  static const DC3 = 19;

  ///  device control 4
  static const DC4 = 20;

  ///  nak negative-acknowledge
  static const NAK = 21;

  ///  synchronous idle
  static const SYN = 22;

  ///  end of trans. block
  static const ETB = 23;

  ///  cancel
  static const CAN = 24;

  ///  end of medium
  static const EM = 25;

  ///  substitute
  static const SUB = 26;

  ///  escape
  static const ESC = 27;

  ///  file separator
  static const FS = 28;

  ///  group separator
  static const GS = 29;

  ///  record separator
  static const RS = 30;

  ///  unit separator
  static const US = 31;

  ///  delete
  static const DEL = 127;

  /*
   * printable ascii characters
   */

  /// space " "
  static const space = 32;

  /// exclamation mark "!"
  static const exclamationMark = 33;

  /// double quotes '"'
  static const doubleQuotes = 34;

  /// number sign '#'
  static const numberSign = 35;

  /// dollar sign '$'
  static const dollarSign = 36;

  /// percent sign '%'
  static const percentSign = 37;

  /// ampersand '&'
  static const ampersand = 38;

  /// single quote "'"
  static const singleQuote = 39;

  /// round brackets or parentheses, opening round bracket '('
  static const openParentheses = 40;

  /// parentheses or round brackets, closing parentheses ')'
  static const closeParentheses = 41;

  /// asterisk '*'
  static const asterisk = 42;

  /// plus sign '+'
  static const plus = 43;

  /// comma ","
  static const comma = 44;

  /// hyphen , minus sign '-'
  static const minus = 45;

  /// dot, full stop '.'
  static const dot = 46;

  /// slash , forward slash , fraction bar , division slash '/'
  static const slash = 47;

  /// number zero
  static const num0 = 48;

  /// number one
  static const num1 = 49;

  /// number two
  static const num2 = 50;

  /// number three
  static const num3 = 51;

  /// number four
  static const num4 = 52;

  /// number five
  static const num5 = 53;

  /// number six
  static const num6 = 54;

  /// number seven
  static const num7 = 55;

  /// number eight
  static const num8 = 56;

  /// number nine
  static const num9 = 57;

  /// colon ':'
  static const colon = 58;

  /// semicolon ';'
  static const semicolon = 59;

  /// less-than sign '<'
  static const lessThan = 60;

  /// equals sign '='
  static const equal = 61;

  /// greater-than sign ; inequality sign '>'
  static const greaterThan = 62;

  /// question mark '?'
  static const questionMark = 63;

  /// at sign '@'
  static const atSign = 64;

  /// capital letter a
  static const A = 65;

  /// capital letter b
  static const B = 66;

  /// capital letter c
  static const C = 67;

  /// capital letter d
  static const D = 68;

  /// capital letter e
  static const E = 69;

  /// capital letter f
  static const F = 70;

  /// capital letter g
  static const G = 71;

  /// capital letter h
  static const H = 72;

  /// capital letter i
  static const I = 73;

  /// capital letter j
  static const J = 74;

  /// capital letter k
  static const K = 75;

  /// capital letter l
  static const L = 76;

  /// capital letter m
  static const M = 77;

  /// capital letter n
  static const N = 78;

  /// capital letter o
  static const O = 79;

  /// capital letter p
  static const P = 80;

  /// capital letter q
  static const Q = 81;

  /// capital letter r
  static const R = 82;

  /// capital letter s
  static const S = 83;

  /// capital letter t
  static const T = 84;

  /// capital letter u
  static const U = 85;

  /// capital letter v
  static const V = 86;

  /// capital letter w
  static const W = 87;

  /// capital letter x
  static const X = 88;

  /// capital letter y
  static const Y = 89;

  /// capital letter z
  static const Z = 90;

  /// square brackets or box brackets, opening bracket '['
  static const openBracket = 91;

  /// backslash , reverse slash '\\'
  static const backslash = 92;

  /// box brackets or square brackets, closing bracket ']'
  static const closeBracket = 93;

  /// circumflex accent or caret  '^'
  static const caret = 94;

  /// underscore , understrike , underbar or low line '_'
  static const underscore = 95;

  /// grave accent  '`'
  static const graveAccent = 96;

  /// lowercase letter a , minuscule a
  static const a = 97;

  /// lowercase letter b , minuscule b
  static const b = 98;

  /// lowercase letter c , minuscule c
  static const c = 99;

  /// lowercase letter d , minuscule d
  static const d = 100;

  /// lowercase letter e , minuscule e
  static const e = 101;

  /// lowercase letter f , minuscule f
  static const f = 102;

  /// lowercase letter g , minuscule g
  static const g = 103;

  /// lowercase letter h , minuscule h
  static const h = 104;

  /// lowercase letter i , minuscule i
  static const i = 105;

  /// lowercase letter j , minuscule j
  static const j = 106;

  /// lowercase letter k , minuscule k
  static const k = 107;

  /// lowercase letter l , minuscule l
  static const l = 108;

  /// lowercase letter m , minuscule m
  static const m = 109;

  /// lowercase letter n , minuscule n
  static const n = 110;

  /// lowercase letter o , minuscule o
  static const o = 111;

  /// lowercase letter p , minuscule p
  static const p = 112;

  /// lowercase letter q , minuscule q
  static const q = 113;

  /// lowercase letter r , minuscule r
  static const r = 114;

  /// lowercase letter s , minuscule s
  static const s = 115;

  /// lowercase letter t , minuscule t
  static const t = 116;

  /// lowercase letter u , minuscule u
  static const u = 117;

  /// lowercase letter v , minuscule v
  static const v = 118;

  /// lowercase letter w , minuscule w
  static const w = 119;

  /// lowercase letter x , minuscule x
  static const x = 120;

  /// lowercase letter y , minuscule y
  static const y = 121;

  /// lowercase letter z , minuscule z
  static const z = 122;

  /// braces or curly brackets, opening braces '{'
  static const openBrace = 123;

  /// vertical-bar, vbar, vertical line or vertical slash '|'
  static const verticalBar = 124;

  /// curly brackets or braces, closing curly brackets '}'
  static const closeBrace = 125;

  /// tilde ; swung dash '~'
  static const tilde = 126;
}
