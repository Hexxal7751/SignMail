import 'dart:convert';
import 'dart:typed_data';

/// Builds DER-encoded ASN.1 data (the counterpart of the reader in asn1.dart).

Uint8List _lengthBytes(int length) {
  if (length < 0x80) {
    return Uint8List.fromList([length]);
  }
  final bytes = <int>[];
  var value = length;
  while (value > 0) {
    bytes.insert(0, value & 0xFF);
    value >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

/// One element with the given [tag] and [content].
Uint8List derTlv(int tag, List<int> content) {
  final length = _lengthBytes(content.length);
  final out = BytesBuilder(copy: false)
    ..addByte(tag)
    ..add(length)
    ..add(content);
  return out.toBytes();
}

Uint8List _concat(Iterable<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final part in parts) {
    out.add(part);
  }
  return out.toBytes();
}

Uint8List derSequence(Iterable<List<int>> items) =>
    derTlv(0x30, _concat(items));

/// A SET OF, sorted as DER requires.
Uint8List derSetOf(Iterable<List<int>> items) {
  final list = items.map((e) => Uint8List.fromList(e)).toList()
    ..sort(_compareBytes);
  return derTlv(0x31, _concat(list));
}

int _compareBytes(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      return a[i] - b[i];
    }
  }
  return a.length - b.length;
}

/// [tagNumber] with the context-specific constructed class: `[n]`.
Uint8List derContext(int tagNumber, List<int> content) =>
    derTlv(0xA0 | tagNumber, content);

Uint8List derOid(String oid) {
  final parts = oid.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7F];
    var value = part >> 7;
    while (value > 0) {
      chunk.insert(0, (value & 0x7F) | 0x80);
      value >>= 7;
    }
    out.addAll(chunk);
  }
  return derTlv(0x06, out);
}

Uint8List derInteger(BigInt value) {
  if (value == BigInt.zero) {
    return derTlv(0x02, [0]);
  }
  final bytes = <int>[];
  var v = value;
  if (value > BigInt.zero) {
    while (v > BigInt.zero) {
      bytes.insert(0, (v & BigInt.from(0xFF)).toInt());
      v >>= 8;
    }
    if (bytes[0] & 0x80 != 0) {
      bytes.insert(0, 0);
    }
  } else {
    // Negative numbers are not needed here.
    throw ArgumentError('negative integers are not supported');
  }
  return derTlv(0x02, bytes);
}

Uint8List derInt(int value) => derInteger(BigInt.from(value));

Uint8List derOctetString(List<int> bytes) => derTlv(0x04, bytes);

Uint8List derNull() => derTlv(0x05, const <int>[]);

Uint8List derUtf8(String text) => derTlv(0x0C, utf8.encode(text));

/// An AlgorithmIdentifier with NULL parameters (or none).
Uint8List derAlgorithm(String oid, {bool withNull = true}) =>
    derSequence([derOid(oid), if (withNull) derNull()]);

Uint8List derUtcTime(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final text = '${two(t.year % 100)}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  return derTlv(0x17, ascii.encode(text));
}