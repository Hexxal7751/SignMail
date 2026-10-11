
import 'package:google_sign_in/google_sign_in.dart';

/// Handles Google account sign-in and Gmail authorization.
///
/// This service does not yet connect to IMAP/SMTP or implement
/// persistent OAuth token refresh.
class GmailAuthService {
  GmailAuthService();

  // Google Cloud Console > Google Auth Platform > Clients
  // Select the WEB application client, NOT the Android client.
  static const String _webClientId =
      '294956053372-9h12bhshrn9sertq2he2pi1tq8dfrgpb.apps.googleusercontent.com';

  static const String gmailScope = 'https://mail.google.com/';

  static const List<String> _scopes = <String>[
    gmailScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _initialized = false;

  /// Initialize Google Sign-In once before requesting authorization.
  Future<void> initialize() async {
    if (_initialized) return;

    await _googleSignIn.initialize(
      serverClientId: _webClientId,
    );

    _initialized = true;
  }

  /// Sign in to Google and request Gmail access.
  ///
  /// Returns an access token for the authorized Gmail account.
  Future<GmailAuthorization> connectGmail() async {
    await initialize();

    final GoogleSignInAccount account =
        await _googleSignIn.authenticate();

    final GoogleSignInClientAuthorization authorization =
        await account.authorizationClient.authorizeScopes(_scopes);

    return GmailAuthorization(
      email: account.email,
      accessToken: authorization.accessToken,
    );
  }

  /// Sign out of the Google account in this app.
  Future<void> disconnect() async {
    await initialize();
    await _googleSignIn.signOut();
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
