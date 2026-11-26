import 'x509.dart';

/// Certificates SignMail accepts as trust anchors.
class TrustStore {
  const TrustStore({
    this.roots = const <X509Certificate>[],
    this.pinnedFingerprints = const <String>{},
  });

  /// Public certificate authorities.
  final List<X509Certificate> roots;

  /// SHA-256 fingerprints of certificates the user chose to trust.
  final Set<String> pinnedFingerprints;
}

/// The result of looking for a trusted path from a certificate.
class ChainResult {
  ChainResult({
    required this.path,
    required this.trusted,
    required this.pinned,
    this.problem,
  });

  /// The certificates from the signer upwards.
  final List<X509Certificate> path;

  /// True when the path ends at a trusted authority or a pinned certificate.
  final bool trusted;

  /// True when the user trusted this exact certificate.
  final bool pinned;

  final String? problem;
}

/// Looks for a path from [leaf] to something in [store], using
/// [extras] (certificates that came with the message) as intermediates.
ChainResult buildChain(
  X509Certificate leaf,
  List<X509Certificate> extras,
  TrustStore store,
  DateTime at,
) {
  final path = <X509Certificate>[leaf];
  final rootPrints = store.roots.map((c) => c.fingerprint).toSet();

  if (store.pinnedFingerprints.contains(leaf.fingerprint)) {
    return ChainResult(path: path, trusted: true, pinned: true);
  }

  var current = leaf;
  for (var depth = 0; depth < 8; depth++) {
    if (rootPrints.contains(current.fingerprint)) {
      return ChainResult(path: path, trusted: true, pinned: false);
    }

    if (current.isSelfSigned) {
      final ok = current.didSign(current);
      return ChainResult(
        path: path,
        trusted: false,
        pinned: false,
        problem: !ok
            ? 'The certificate\'s own signature is invalid.'
            : (path.length > 1
                ? 'The certificate chain ends at an authority SignMail does '
                    'not know (${current.commonName}).'
                : 'The certificate is self-issued and not from a known '
                    'authority.'),
      );
    }

    X509Certificate? issuer;
    for (final candidate in <X509Certificate>[...extras, ...store.roots]) {
      if (candidate.fingerprint == current.fingerprint) {
        continue;
      }
      if (!_sameName(candidate, current)) {
        continue;
      }
      if (candidate.isCa == false || !candidate.canSignCertificates) {
        continue;
      }
      if (!candidate.isValidAt(at)) {
        continue;
      }
      if (candidate.didSign(current)) {
        issuer = candidate;
        break;
      }
    }

    if (issuer == null) {
      return ChainResult(
        path: path,
        trusted: false,
        pinned: false,
        problem: 'The issuing authority could not be found or verified.',
      );
    }

    path.add(issuer);
    current = issuer;
  }

  return ChainResult(
    path: path,
    trusted: false,
    pinned: false,
    problem: 'The certificate chain is too long.',
  );
}

bool _sameName(X509Certificate issuer, X509Certificate child) {
  if (issuer.subjectDer.length != child.issuerDer.length) {
    return false;
  }
  for (var i = 0; i < issuer.subjectDer.length; i++) {
    if (issuer.subjectDer[i] != child.issuerDer[i]) {
      return false;
    }
  }
  return true;
}