import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Handles Google account sign-in and Gmail authorization.
///
/// One shared instance is used across the app, so the connected account is
/// remembered between screens. Gmail access tokens are short-lived, so a fresh
/// one is requested (silently) every time mail is accessed.
class GmailAuthService {
  factory GmailAuthService() => _instance;

  GmailAuthService._();

  static final GmailAuthService _instance = GmailAuthService._();

  // Google Cloud Console > Google Auth Platform > Clients
  // Select the WEB application client, NOT the Android client.
  static const String _webClientId =
      '294956053372-golg2d9tunff4v8smk19fdfct3k4at4l.apps.googleusercontent.com';

  static const String gmailScope = 'https://mail.google.com/';

  static const List<String> _scopes = <String>[
    gmailScope,
  ];

  static const String _emailKey = 'signmail.account.email';

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _initialized = false;
  GoogleSignInAccount? _account;

  /// Initialize Google Sign-In once before requesting authorization.
  Future<void> initialize() async {
    if (_initialized) return;

    await _googleSignIn.initialize(
      serverClientId: _webClientId,
    );

    _initialized = true;
  }

  /// The email address connected on this device, or null when signed out.
  Future<String?> savedEmail() async {
    try {
      return await _storage.read(key: _emailKey);
    } catch (_) {
      // Secure storage can be unreadable after a restore; treat as signed out.
      return null;
    }
  }

  /// Sign in to Google and request Gmail access (shows Google's screens).
  ///
  /// The connected address is remembered so the next app start can skip
  /// the welcome flow.
  Future<GmailAuthorization> connectGmail() async {
    await initialize();

    final GoogleSignInAccount account =
        await _googleSignIn.authenticate();

    final GoogleSignInClientAuthorization authorization =
        await account.authorizationClient.authorizeScopes(_scopes);

    _account = account;
    await _storage.write(key: _emailKey, value: account.email);

    return GmailAuthorization(
      email: account.email,
      accessToken: authorization.accessToken,
    );
  }

  /// Returns a fresh Gmail access token without showing any screen.
  ///
  /// With [background] set, no Activity is needed, so this also works while
  /// the app is closed (used by the background mail check).
  ///
  /// Throws [GmailAuthException] when Google needs the user to sign in or
  /// approve access again.
  Future<String> accessToken({bool background = false}) async {
    await initialize();

    if (background) {
      return _silentToken();
    }

    final GoogleSignInAccount account;
    try {
      account = await _restoreAccount();
    } on GmailAuthException {
      // Restoring needs the screen; the silent path may still succeed.
      return _silentToken();
    }

    final GoogleSignInClientAuthorization? authorization =
        await account.authorizationClient.authorizationForScopes(_scopes);

    if (authorization == null) {
      return _silentToken();
    }

    return authorization.accessToken;
  }

  /// Asks Android for a token for the remembered account. This never shows
  /// any screen and does not need an Activity.
  Future<String> _silentToken() async {
    final String? email = await savedEmail();
    if (email == null) {
      throw const GmailAuthException('Please reconnect your Google account.');
    }

    try {
      final ClientAuthorizationTokenData? tokens =
          await GoogleSignInPlatform.instance
              .clientAuthorizationTokensForScopes(
        ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
            scopes: _scopes,
            userId: null,
            email: email,
            promptIfUnauthorized: false,
          ),
        ),
      );

      if (tokens == null) {
        throw const GmailAuthException(
          'Google needs you to approve Gmail access again.',
        );
      }

      return tokens.accessToken;
    } on GoogleSignInException catch (error) {
      throw GmailAuthException(
        'Google sign-in could not be restored (${error.code.name}).',
      );
    }
  }

  Future<GoogleSignInAccount> _restoreAccount() async {
    final GoogleSignInAccount? existing = _account;
    if (existing != null) return existing;

    try {
      final Future<GoogleSignInAccount?>? attempt =
          _googleSignIn.attemptLightweightAuthentication();
      final GoogleSignInAccount? restored =
          attempt == null ? null : await attempt;

      if (restored != null) {
        _account = restored;
        return restored;
      }
    } on GoogleSignInException catch (error) {
      throw GmailAuthException(
        'Google sign-in could not be restored (${error.code.name}).',
      );
    }

    throw const GmailAuthException(
      'Please reconnect your Google account.',
    );
  }

  /// Sign out of the Google account in this app and forget it.
  Future<void> disconnect() async {
    _account = null;
    await _storage.delete(key: _emailKey);

    try {
      await initialize();
      await _googleSignIn.signOut();
    } catch (_) {
      // Local state is already cleared; Google's side can be retried later.
    }
  }
}

/// Result of the initial Gmail authorization.
class GmailAuthorization {
  const GmailAuthorization({
    required this.email,
    required this.accessToken,
  });

  final String email;
  final String accessToken;
}

/// Raised when the user has to sign in or approve access again.
class GmailAuthException implements Exception {
  const GmailAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}