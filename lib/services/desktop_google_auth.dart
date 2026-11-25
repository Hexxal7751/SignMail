import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

/// A desktop sign-in problem that can be shown to the user as is.
class DesktopAuthException implements Exception {
  const DesktopAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Google sign-in for Windows and Linux.
///
/// Opens the normal Google page in the browser, receives the answer on a
/// temporary local address (127.0.0.1) and trades it for tokens (OAuth with
/// PKCE, the method Google recommends for desktop apps).
///
/// The "Desktop app" client ID and secret are injected at build time with
/// `--dart-define` (see the build workflow).
class DesktopGoogleAuth {
  DesktopGoogleAuth();

  static const String clientId = String.fromEnvironment('DESKTOP_CLIENT_ID');
  static const String clientSecret =
      String.fromEnvironment('DESKTOP_CLIENT_SECRET');

  static bool get isConfigured => clientId.isNotEmpty;

  static const String _scope = 'https://mail.google.com/ openid email';
  static const String _refreshKey = 'signmail.desktop.refreshToken';
  static const FlutterSecureStorage _vault = FlutterSecureStorage();

  String? _refreshToken;
  String? _accessToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);

  /// Opens the browser, waits for the user to approve, and returns the
  /// signed-in address with a first access token.
  Future<({String email, String accessToken})> signIn({
    String? loginHint,
  }) async {
    if (!isConfigured) {
      throw const DesktopAuthException(
        'Desktop sign-in is not set up in this build. Add the '
        'DESKTOP_CLIENT_ID and DESKTOP_CLIENT_SECRET secrets to the GitHub '
        'repository and build again.',
      );
    }

    final verifier = _randomString(64);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomString(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';

      final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
        if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
      });

      final opened = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const DesktopAuthException(
          'Could not open your web browser for Google sign-in.',
        );
      }

      final code = await _waitForCode(server, state).timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw const DesktopAuthException(
          'Sign-in took too long. Please try again.',
        ),
      );

      final tokens = await _post(<String, String>{
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
      });

      final refresh = tokens['refresh_token'] as String?;
      final access = tokens['access_token'] as String?;
      final idToken = tokens['id_token'] as String?;

      if (access == null || refresh == null || idToken == null) {
        throw const DesktopAuthException(
          'Google did not return everything needed. Please try again.',
        );
      }

      final email = _emailFromIdToken(idToken);
      if (email == null) {
        throw const DesktopAuthException(
          'Google did not tell us which account signed in.',
        );
      }

      _rememberAccess(tokens);
      _refreshToken = refresh;
      try {
        await _vault.write(key: _refreshKey, value: refresh);
      } catch (_) {
        // Some Linux setups have no keyring. The app then asks again after
        // a restart instead of storing the token unprotected.
      }

      return (email: email, accessToken: access);
    } finally {
      await server.close(force: true);
    }
  }

  /// A valid access token, refreshed silently when needed.
  Future<String> accessToken() async {
    final current = _accessToken;
    if (current != null && DateTime.now().isBefore(_expiry)) {
      return current;
    }

    var refresh = _refreshToken;
    if (refresh == null) {
      try {
        refresh = await _vault.read(key: _refreshKey);
      } catch (_) {
        refresh = null;
      }
      _refreshToken = refresh;
    }

    if (refresh == null || refresh.isEmpty) {
      throw const DesktopAuthException('Please reconnect your Google account.');
    }

    try {
      final tokens = await _post(<String, String>{
        'client_id': clientId,
        if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
      });
      _rememberAccess(tokens);
      return _accessToken!;
    } on _InvalidGrant {
      await clear();
      throw const DesktopAuthException(
        'Google needs you to sign in again.',
      );
    }
  }

  /// Forgets all tokens (sign out).
  Future<void> clear() async {
    _refreshToken = null;
    _accessToken = null;
    _expiry = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _vault.delete(key: _refreshKey);
    } catch (_) {
      // Nothing else to do.
    }
  }

  void _rememberAccess(Map<String, dynamic> tokens) {
    final access = tokens['access_token'] as String?;
    final seconds = (tokens['expires_in'] as num?)?.toInt() ?? 3000;
    if (access != null) {
      _accessToken = access;
      _expiry = DateTime.now().add(Duration(seconds: seconds - 60));
    }
  }

  Future<String> _waitForCode(HttpServer server, String state) async {
    await for (final request in server) {
      final params = request.uri.queryParameters;
      final code = params['code'];
      final error = params['error'];

      // Browsers also ask for /favicon.ico and similar; ignore those.
      if (code == null && error == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }

      final ok = code != null && params['state'] == state;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(
          '<html><head><meta charset="utf-8"><title>SignMail</title></head>'
          '<body style="font-family:sans-serif;text-align:center;'
          'margin-top:15vh;background:#0A0F16;color:#E6EDF3">'
          '<h2>${ok ? 'You are signed in' : 'Sign-in was not completed'}</h2>'
          '<p>You can close this tab and return to SignMail.</p>'
          '</body></html>',
        );
      await request.response.close();

      if (error != null) {
        throw DesktopAuthException('Google sign-in was cancelled ($error).');
      }
      if (ok) {
        return code;
      }
    }

    throw const DesktopAuthException('Sign-in was interrupted.');
  }

  Future<Map<String, dynamic>> _post(Map<String, String> fields) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('https://oauth2.googleapis.com/token'),
      );
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        fields.entries
            .map(
              (e) => '${Uri.encodeQueryComponent(e.key)}='
                  '${Uri.encodeQueryComponent(e.value)}',
            )
            .join('&'),
      );

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      Object? json;
      try {
        json = jsonDecode(text);
      } catch (_) {
        json = null;
      }

      if (response.statusCode != 200) {
        if (json is Map && json['error'] == 'invalid_grant') {
          throw const _InvalidGrant();
        }
        final detail = json is Map
            ? '${json['error_description'] ?? json['error']}'
            : text;
        throw DesktopAuthException('Google refused the request: $detail');
      }

      return json as Map<String, dynamic>;
    } on SocketException {
      throw const DesktopAuthException(
        'No connection to Google. Check your internet and try again.',
      );
    } finally {
      client.close();
    }
  }

  String? _emailFromIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length < 2) {
        return null;
      }
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final json = jsonDecode(payload);
      return json is Map ? json['email'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  static String _randomString(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return String.fromCharCodes(
      List<int>.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }
}

/// The refresh token is no longer valid (revoked or expired).
class _InvalidGrant implements Exception {
  const _InvalidGrant();
}