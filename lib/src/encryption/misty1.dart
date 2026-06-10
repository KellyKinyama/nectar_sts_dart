/// MISTY1 64-bit block cipher (RFC 2994).
///
/// 128-bit key, 64-bit block, 8 Feistel rounds (plus a final FL pair).
/// Direct port of the implementation in
/// `domain/encryptionalgorithm/Misty1AlgorithmEncryptionAlgorithm.java`
/// (the inner `Misty1Functions` helper class), kept structurally
/// identical so the constant tables and round numbering can be
/// audited 1:1 against the Java reference.
///
/// All intermediate values fit in 32 bits; Dart `int` (64-bit signed)
/// holds them exactly without wrap. We use `>>>` for unsigned shifts
/// and explicit masks where the Java original implicitly truncates
/// via `long` semantics.
library;

import 'dart:typed_data';

import '../exceptions/exceptions.dart';

class Misty1 {
  /// Length of the MISTY1 key, in bytes.
  static const int keyLength = 16;

  /// Length of the MISTY1 block, in bytes.
  static const int blockLength = 8;

  /// Expand a 128-bit key into the 32-entry extended-key schedule
  /// used by [encryptBlock] / [decryptBlock]. Mirrors the Java
  /// `KeySchedule(char[] key)` exactly.
  static List<int> keySchedule(List<int> key) {
    if (key.length != keyLength) {
      throw const InvalidKeyDataException(
        'MISTY1 key must be exactly 16 bytes',
      );
    }
    final ek = List<int>.filled(32, 0);
    for (var i = 0; i < 8; i++) {
      ek[i] = ((key[i * 2] & 0xFF) << 8) | (key[i * 2 + 1] & 0xFF);
    }
    for (var i = 0; i < 8; i++) {
      ek[i + 8] = _fi(ek[i], ek[(i + 1) % 8]);
      ek[i + 16] = ek[i + 8] & 0x1FF;
      ek[i + 24] = (ek[i + 8] >>> 9) & 0x7F;
    }
    return ek;
  }

  /// Encrypt one 8-byte block in-place into [out].
  static void encryptBlock(List<int> ek, List<int> input, List<int> out) {
    _checkBlock(input, 'input');
    _checkBlock(out, 'out');

    var l =
        ((input[0] & 0xFF) << 24) |
        ((input[1] & 0xFF) << 16) |
        ((input[2] & 0xFF) << 8) |
        (input[3] & 0xFF);
    var r =
        ((input[4] & 0xFF) << 24) |
        ((input[5] & 0xFF) << 16) |
        ((input[6] & 0xFF) << 8) |
        (input[7] & 0xFF);

    // 8 Feistel rounds, FL pairs at the even-numbered ones.
    var r1 = _fl(ek, l, 0);
    var l1 = _fo(ek, r1, 0) ^ _fl(ek, r, 1);

    var r2 = l1;
    var l2 = _fo(ek, r2, 1) ^ r1;

    var r3 = _fl(ek, l2, 2);
    var l3 = _fo(ek, r3, 2) ^ _fl(ek, r2, 3);

    var r4 = l3;
    var l4 = _fo(ek, r4, 3) ^ r3;

    var r5 = _fl(ek, l4, 4);
    var l5 = _fo(ek, r5, 4) ^ _fl(ek, r4, 5);

    var r6 = l5;
    var l6 = _fo(ek, r6, 5) ^ r5;

    var r7 = _fl(ek, l6, 6);
    var l7 = _fo(ek, r7, 6) ^ _fl(ek, r6, 7);

    var r8 = l7;
    var l8 = _fo(ek, r8, 7) ^ r7;

    final r9 = _fl(ek, l8, 8);
    final l9 = _fl(ek, r8, 9);

    out[0] = (l9 >>> 24) & 0xFF;
    out[1] = (l9 >>> 16) & 0xFF;
    out[2] = (l9 >>> 8) & 0xFF;
    out[3] = l9 & 0xFF;
    out[4] = (r9 >>> 24) & 0xFF;
    out[5] = (r9 >>> 16) & 0xFF;
    out[6] = (r9 >>> 8) & 0xFF;
    out[7] = r9 & 0xFF;
  }

  /// Decrypt one 8-byte block in-place into [out].
  static void decryptBlock(List<int> ek, List<int> input, List<int> out) {
    _checkBlock(input, 'input');
    _checkBlock(out, 'out');

    final l9 =
        ((input[0] & 0xFF) << 24) |
        ((input[1] & 0xFF) << 16) |
        ((input[2] & 0xFF) << 8) |
        (input[3] & 0xFF);
    final r9 =
        ((input[4] & 0xFF) << 24) |
        ((input[5] & 0xFF) << 16) |
        ((input[6] & 0xFF) << 8) |
        (input[7] & 0xFF);

    final r8 = _flInv(ek, l9, 9);
    final l8 = _fo(ek, r8, 7) ^ _flInv(ek, r9, 8);

    final r7 = l8;
    final l7 = _fo(ek, r7, 6) ^ r8;

    final r6 = _flInv(ek, l7, 7);
    final l6 = _fo(ek, r6, 5) ^ _flInv(ek, r7, 6);

    final r5 = l6;
    final l5 = _fo(ek, r5, 4) ^ r6;

    final r4 = _flInv(ek, l5, 5);
    final l4 = _fo(ek, r4, 3) ^ _flInv(ek, r5, 4);

    final r3 = l4;
    final l3 = _fo(ek, r3, 2) ^ r4;

    final r2 = _flInv(ek, l3, 3);
    final l2 = _fo(ek, r2, 1) ^ _flInv(ek, r3, 2);

    final r1 = l2;
    final l1 = _fo(ek, r1, 0) ^ r2;

    // Mirror of Java decrypt(): r0 uses r1 (the post-round-1 value),
    // l0 uses r1 as well. Bit-for-bit faithful to the upstream.
    final r0 = _flInv(ek, l1, 1);
    final l0 = _flInv(ek, r1, 0);

    out[0] = (l0 >>> 24) & 0xFF;
    out[1] = (l0 >>> 16) & 0xFF;
    out[2] = (l0 >>> 8) & 0xFF;
    out[3] = l0 & 0xFF;
    out[4] = (r0 >>> 24) & 0xFF;
    out[5] = (r0 >>> 16) & 0xFF;
    out[6] = (r0 >>> 8) & 0xFF;
    out[7] = r0 & 0xFF;
  }

  /// Convenience: encrypt one 8-byte block; allocate the output.
  static Uint8List encrypt(List<int> key, List<int> input) {
    final ek = keySchedule(key);
    final out = Uint8List(blockLength);
    encryptBlock(ek, input, out);
    return out;
  }

  /// Convenience: decrypt one 8-byte block; allocate the output.
  static Uint8List decrypt(List<int> key, List<int> input) {
    final ek = keySchedule(key);
    final out = Uint8List(blockLength);
    decryptBlock(ek, input, out);
    return out;
  }
}

void _checkBlock(List<int> b, String which) {
  if (b.length != Misty1.blockLength) {
    throw InvalidKeyDataException(
      'MISTY1 $which block must be exactly 8 bytes (was ${b.length})',
    );
  }
}

int _fl(List<int> ek, int input, int k) {
  var dl = (input >>> 16) & 0xFFFF;
  var dr = input & 0xFFFF;
  final int t;
  if (k.isOdd) {
    t = (k - 1) ~/ 2;
    dr ^= (dl & ek[((t + 2) % 8) + 8]);
    dl ^= (dr | ek[(t + 4) % 8]);
  } else {
    t = k ~/ 2;
    dr ^= (dl & ek[t]);
    dl ^= (dr | ek[((t + 6) % 8) + 8]);
  }
  dl &= 0xFFFF;
  dr &= 0xFFFF;
  return (dl << 16) | dr;
}

int _flInv(List<int> ek, int input, int k) {
  var d0 = (input >>> 16) & 0xFFFF;
  var d1 = input & 0xFFFF;
  final int t;
  if (k.isOdd) {
    t = (k - 1) ~/ 2;
    d0 ^= (d1 | ek[(t + 4) % 8]);
    d1 ^= (d0 & ek[((t + 2) % 8) + 8]);
  } else {
    t = k ~/ 2;
    d0 ^= (d1 | ek[((t + 6) % 8) + 8]);
    d1 ^= (d0 & ek[t]);
  }
  d0 &= 0xFFFF;
  d1 &= 0xFFFF;
  return (d0 << 16) | d1;
}

int _fo(List<int> ek, int input, int k) {
  var t0 = (input >>> 16) & 0xFFFF;
  var t1 = input & 0xFFFF;
  t0 ^= ek[k];
  t0 = _fi(t0, ek[((k + 5) % 8) + 8]);
  t0 ^= t1;
  t1 ^= ek[(k + 2) % 8];
  t1 = _fi(t1, ek[((k + 1) % 8) + 8]);
  t1 ^= t0;
  t0 ^= ek[(k + 7) % 8];
  t0 = _fi(t0, ek[((k + 3) % 8) + 8]);
  t0 ^= t1;
  t1 ^= ek[(k + 4) % 8];
  t0 &= 0xFFFF;
  t1 &= 0xFFFF;
  return (t1 << 16) | t0;
}

int _fi(int input, int key) {
  var d9 = (input >>> 7) & 0x1FF;
  var d7 = input & 0x7F;
  d9 = _s9[d9] ^ d7;
  d7 = (_s7[d7] ^ d9) & 0x7F;

  d7 ^= ((key >>> 9) & 0x7F);
  d9 ^= (key & 0x1FF);
  d9 = _s9[d9] ^ d7;
  return ((d7 << 9) | d9) & 0xFFFF;
}

// 7-bit S-box (128 entries).
const List<int> _s7 = [
  27,
  50,
  51,
  90,
  59,
  16,
  23,
  84,
  91,
  26,
  114,
  115,
  107,
  44,
  102,
  73,
  31,
  36,
  19,
  108,
  55,
  46,
  63,
  74,
  93,
  15,
  64,
  86,
  37,
  81,
  28,
  4,
  11,
  70,
  32,
  13,
  123,
  53,
  68,
  66,
  43,
  30,
  65,
  20,
  75,
  121,
  21,
  111,
  14,
  85,
  9,
  54,
  116,
  12,
  103,
  83,
  40,
  10,
  126,
  56,
  2,
  7,
  96,
  41,
  25,
  18,
  101,
  47,
  48,
  57,
  8,
  104,
  95,
  120,
  42,
  76,
  100,
  69,
  117,
  61,
  89,
  72,
  3,
  87,
  124,
  79,
  98,
  60,
  29,
  33,
  94,
  39,
  106,
  112,
  77,
  58,
  1,
  109,
  110,
  99,
  24,
  119,
  35,
  5,
  38,
  118,
  0,
  49,
  45,
  122,
  127,
  97,
  80,
  34,
  17,
  6,
  71,
  22,
  82,
  78,
  113,
  62,
  105,
  67,
  52,
  92,
  88,
  125,
];

// 9-bit S-box (512 entries).
const List<int> _s9 = [
  451,
  203,
  339,
  415,
  483,
  233,
  251,
  53,
  385,
  185,
  279,
  491,
  307,
  9,
  45,
  211,
  199,
  330,
  55,
  126,
  235,
  356,
  403,
  472,
  163,
  286,
  85,
  44,
  29,
  418,
  355,
  280,
  331,
  338,
  466,
  15,
  43,
  48,
  314,
  229,
  273,
  312,
  398,
  99,
  227,
  200,
  500,
  27,
  1,
  157,
  248,
  416,
  365,
  499,
  28,
  326,
  125,
  209,
  130,
  490,
  387,
  301,
  244,
  414,
  467,
  221,
  482,
  296,
  480,
  236,
  89,
  145,
  17,
  303,
  38,
  220,
  176,
  396,
  271,
  503,
  231,
  364,
  182,
  249,
  216,
  337,
  257,
  332,
  259,
  184,
  340,
  299,
  430,
  23,
  113,
  12,
  71,
  88,
  127,
  420,
  308,
  297,
  132,
  349,
  413,
  434,
  419,
  72,
  124,
  81,
  458,
  35,
  317,
  423,
  357,
  59,
  66,
  218,
  402,
  206,
  193,
  107,
  159,
  497,
  300,
  388,
  250,
  406,
  481,
  361,
  381,
  49,
  384,
  266,
  148,
  474,
  390,
  318,
  284,
  96,
  373,
  463,
  103,
  281,
  101,
  104,
  153,
  336,
  8,
  7,
  380,
  183,
  36,
  25,
  222,
  295,
  219,
  228,
  425,
  82,
  265,
  144,
  412,
  449,
  40,
  435,
  309,
  362,
  374,
  223,
  485,
  392,
  197,
  366,
  478,
  433,
  195,
  479,
  54,
  238,
  494,
  240,
  147,
  73,
  154,
  438,
  105,
  129,
  293,
  11,
  94,
  180,
  329,
  455,
  372,
  62,
  315,
  439,
  142,
  454,
  174,
  16,
  149,
  495,
  78,
  242,
  509,
  133,
  253,
  246,
  160,
  367,
  131,
  138,
  342,
  155,
  316,
  263,
  359,
  152,
  464,
  489,
  3,
  510,
  189,
  290,
  137,
  210,
  399,
  18,
  51,
  106,
  322,
  237,
  368,
  283,
  226,
  335,
  344,
  305,
  327,
  93,
  275,
  461,
  121,
  353,
  421,
  377,
  158,
  436,
  204,
  34,
  306,
  26,
  232,
  4,
  391,
  493,
  407,
  57,
  447,
  471,
  39,
  395,
  198,
  156,
  208,
  334,
  108,
  52,
  498,
  110,
  202,
  37,
  186,
  401,
  254,
  19,
  262,
  47,
  429,
  370,
  475,
  192,
  267,
  470,
  245,
  492,
  269,
  118,
  276,
  427,
  117,
  268,
  484,
  345,
  84,
  287,
  75,
  196,
  446,
  247,
  41,
  164,
  14,
  496,
  119,
  77,
  378,
  134,
  139,
  179,
  369,
  191,
  270,
  260,
  151,
  347,
  352,
  360,
  215,
  187,
  102,
  462,
  252,
  146,
  453,
  111,
  22,
  74,
  161,
  313,
  175,
  241,
  400,
  10,
  426,
  323,
  379,
  86,
  397,
  358,
  212,
  507,
  333,
  404,
  410,
  135,
  504,
  291,
  167,
  440,
  321,
  60,
  505,
  320,
  42,
  341,
  282,
  417,
  408,
  213,
  294,
  431,
  97,
  302,
  343,
  476,
  114,
  394,
  170,
  150,
  277,
  239,
  69,
  123,
  141,
  325,
  83,
  95,
  376,
  178,
  46,
  32,
  469,
  63,
  457,
  487,
  428,
  68,
  56,
  20,
  177,
  363,
  171,
  181,
  90,
  386,
  456,
  468,
  24,
  375,
  100,
  207,
  109,
  256,
  409,
  304,
  346,
  5,
  288,
  443,
  445,
  224,
  79,
  214,
  319,
  452,
  298,
  21,
  6,
  255,
  411,
  166,
  67,
  136,
  80,
  351,
  488,
  289,
  115,
  382,
  188,
  194,
  201,
  371,
  393,
  501,
  116,
  460,
  486,
  424,
  405,
  31,
  65,
  13,
  442,
  50,
  61,
  465,
  128,
  168,
  87,
  441,
  354,
  328,
  217,
  261,
  98,
  122,
  33,
  511,
  274,
  264,
  448,
  169,
  285,
  432,
  422,
  205,
  243,
  92,
  258,
  91,
  473,
  324,
  502,
  173,
  165,
  58,
  459,
  310,
  383,
  70,
  225,
  30,
  477,
  230,
  311,
  506,
  389,
  140,
  143,
  64,
  437,
  190,
  120,
  0,
  172,
  272,
  350,
  292,
  2,
  444,
  162,
  234,
  112,
  508,
  278,
  348,
  76,
  450,
];
