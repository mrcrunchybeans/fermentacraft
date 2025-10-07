// lib/services/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:fermentacraft/services/firestore_user.dart';
// if not already present elsewhere
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Toggle verbose logging (never enable in production builds).
const bool kAuthDebugLogs = true; // enable verbose auth logs during debugging

/// Timeouts/safety limits.
const Duration _kDesktopAuthWaitTimeout = Duration(minutes: 3);
const Duration _kTokenPostTimeout = Duration(seconds: 30);

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // === DESKTOP OAUTH CONFIG (Google Cloud: OAuth client "Desktop app") ===
  static const String _googleDesktopClientId =
      '747130944683-0a6fk646jhks0sfihg2064b68d8l0i92.apps.googleusercontent.com';

  // Provide via --dart-define. Do NOT hardcode in source.
  static const String _googleDesktopClientSecret =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET', defaultValue: '');

  // Mobile only (Android/iOS)
  static final GoogleSignIn _googleSignIn =
      GoogleSignIn(scopes: const ['email']);

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Call once after Firebase.initializeApp(). Harmless on non-web.
  Future<void> initForWebIfNeeded() async {
    if (!kIsWeb) return;
    try {
      await _auth.setPersistence(Persistence.LOCAL);
      await _auth.getRedirectResult(); // resolves prior redirect if any
    } catch (e) {
      if (kAuthDebugLogs) debugPrint('[AUTH] Web init note: $e');
    }
  }

  // ---------------------------- Public API -----------------------------------

  /// Starts Google sign-in. Returns a [UserCredential] on success, or throws
  /// [AuthFlowException] with a user-friendly `code` you can map to UI.
  Future<UserCredential> signInWithGoogle() async {
    if (_signInInProgress) {
      throw const AuthFlowException(
        code: AuthFlowCode.busy,
        message: 'Sign-in already in progress.',
      );
    }
    _signInInProgress = true;
    try {
      if (kIsWeb) {
        return await _signInWeb();
      }

      if (_isDesktop) {
        final tokens = await _desktopGoogleOAuth().timeout(
          const Duration(minutes: 3),
          onTimeout: () {
            throw const AuthFlowException(
              code: AuthFlowCode.network,
              message: 'Desktop authentication timed out. Please try again.',
            );
          },
        );

        if (tokens == null) {
          throw const AuthFlowException(
            code: AuthFlowCode.canceled,
            message: 'Sign-in canceled.',
          );
        }

        try {
          final cred = GoogleAuthProvider.credential(
            idToken: tokens.idToken,
            accessToken: tokens.accessToken,
          );

          final userCred = await _auth.signInWithCredential(cred).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw FirebaseAuthException(
                code: 'timeout',
                message: 'Firebase sign-in timed out. Please try again.',
              );
            },
          );

          // Ensure user document creation doesn't block login
          FirestoreUser.instance.ensureUserDoc(userCred.user!).catchError((e) {
            debugPrint('User document creation failed (non-blocking): $e');
          });

          return userCred;
        } on FirebaseAuthException catch (e) {
          _handleFirebaseAuthErrors(e); // will throw AuthFlowException
          rethrow;
        }
      }

      if (_isMobile) {
        try {
          // Add timeout to prevent hanging indefinitely
          final googleUser = await _googleSignIn.signIn().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const AuthFlowException(
                code: AuthFlowCode.network,
                message: 'Google sign-in timed out. Please try again.',
              );
            },
          );

          if (googleUser == null) {
            throw const AuthFlowException(
              code: AuthFlowCode.canceled,
              message: 'Sign-in canceled.',
            );
          }

          final googleAuth = await googleUser.authentication.timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw const AuthFlowException(
                code: AuthFlowCode.network,
                message: 'Authentication timed out. Please try again.',
              );
            },
          );

          final cred = GoogleAuthProvider.credential(
            idToken: googleAuth.idToken,
            accessToken: googleAuth.accessToken,
          );

          final userCred = await _auth.signInWithCredential(cred).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw FirebaseAuthException(
                code: 'timeout',
                message: 'Firebase sign-in timed out. Please try again.',
              );
            },
          );

          // Ensure user document creation doesn't block login
          FirestoreUser.instance.ensureUserDoc(userCred.user!).catchError((e) {
            debugPrint('User document creation failed (non-blocking): $e');
          });

          return userCred;
        } on FirebaseAuthException catch (e) {
          _handleFirebaseAuthErrors(e);
          rethrow;
        } on AuthFlowException {
          rethrow;
        } catch (e) {
          throw AuthFlowException(
            code: AuthFlowCode.unknown,
            message: 'Google sign-in failed. Please try again.',
            details: e.toString(),
          );
        }
      }

      throw const AuthFlowException(
        code: AuthFlowCode.unsupported,
        message: 'Unsupported platform.',
      );
    } finally {
      _signInInProgress = false;
    }
  }

  /// Starts Sign in with Apple. iOS/macOS: native dialog. Web: popup with apple.com.
  Future<UserCredential> signInWithApple() async {
    if (_signInInProgress) {
      throw const AuthFlowException(
        code: AuthFlowCode.busy,
        message: 'Sign-in already in progress.',
      );
    }
    _signInInProgress = true;
    try {
      // Prepare a secure nonce
      final rawNonce = _randomUrlSafe(32);
      // Firebase expects you to pass the SHA256 hash of the raw nonce (hex string)
      final String hashedNonceHex =
          sha256.convert(utf8.encode(rawNonce)).toString();

      if (kIsWeb) {
        final provider = OAuthProvider('apple.com');
        // On web, pass the SHA256-hex hashed nonce in the custom parameters
        provider.setCustomParameters({'nonce': hashedNonceHex});
        final cred = await _auth.signInWithPopup(provider);
        await FirestoreUser.instance.ensureUserDoc(cred.user!);
        return cred;
      }

      if (_isApplePlatform) {
        // Preferred path: Use Firebase Auth's native Apple provider (handles nonce internally)
        try {
          if (kAuthDebugLogs) {
            debugPrint(
                '[AUTH][Apple] Trying Firebase native AppleAuthProvider…');
          }
          final provider = AppleAuthProvider();
          provider.addScope('email');
          provider.addScope('name');
          final userCred = await _auth
              .signInWithProvider(provider)
              .timeout(const Duration(seconds: 30), onTimeout: () {
            throw FirebaseAuthException(
              code: 'timeout',
              message: 'Apple sign-in timed out. Please try again.',
            );
          });

          if (kAuthDebugLogs) {
            debugPrint('[AUTH][Apple] Firebase native provider succeeded');
          }
          // Ensure user document creation doesn't block login
          FirestoreUser.instance.ensureUserDoc(userCred.user!).catchError(
              (e) => debugPrint('User doc creation failed (non-blocking): $e'));
          return userCred;
        } on FirebaseAuthException catch (e) {
          if (kAuthDebugLogs) {
            debugPrint(
                '[AUTH][Apple] Native provider error ${e.code}: ${e.message}');
          }
          // Fall back to manual SIWA flow only for specific errors
          // e.g., if provider not available or invalid-credential persists
        } catch (e) {
          if (kAuthDebugLogs) {
            debugPrint('[AUTH][Apple] Native provider threw: $e; falling back');
          }
        }

        // Fallback path: Manual SIWA with nonce handling
        try {
          final credential = await SignInWithApple.getAppleIDCredential(
            scopes: const [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
            // Per plugin + Firebase docs, pass the SHA256-hex of rawNonce to Apple
            nonce: hashedNonceHex,
          );

          if (kAuthDebugLogs) {
            debugPrint('[AUTH][Apple] Authorization received. hasFullName: '
                '${credential.givenName != null || credential.familyName != null}, '
                'hasEmail: ${credential.email != null}, '
                'idToken.len: ${credential.identityToken?.length ?? 0}');
          }

          // If Apple did not return an identity token, Firebase cannot proceed
          final token = credential.identityToken;
          if (token == null || token.isEmpty) {
            throw const AuthFlowException(
              code: AuthFlowCode.misconfigured,
              message:
                  'Apple did not return an identity token. Make sure you’re signed into iCloud on this device and try again. On Simulator, sign into iCloud in Settings or test on a physical device.',
            );
          }

          // Optional diagnostics: decode JWT to verify audience and nonce
          if (kAuthDebugLogs) {
            try {
              final parts = token.split('.');
              if (parts.length >= 2) {
                String _pad(String s) => s + '=' * ((4 - s.length % 4) % 4);
                final payloadJson =
                    utf8.decode(base64Url.decode(_pad(parts[1])));
                final payload =
                    json.decode(payloadJson) as Map<String, dynamic>;
                final aud = payload['aud'];
                final nonceClaim = payload['nonce'];
                final iss = payload['iss'];
                final email = payload['email'];
                final sub = payload['sub'];
                final iat = payload['iat'];
                final exp = payload['exp'];
                final nonceMatches = nonceClaim == hashedNonceHex;
                debugPrint(
                    '[AUTH][Apple] idToken aud=$aud, iss=$iss, emailPresent=${email != null}');
                debugPrint(
                    '[AUTH][Apple] nonce claim present=${nonceClaim != null}, matchesHashedNonce=$nonceMatches');
                debugPrint('[AUTH][Apple] sub=$sub, iat=$iat, exp=$exp');
              }
            } catch (e) {
              debugPrint('[AUTH][Apple] Failed to decode idToken payload: $e');
            }
          }

          final oauthCred = OAuthProvider('apple.com').credential(
            idToken: token,
            // Provide the ORIGINAL raw nonce to Firebase for verification
            rawNonce: rawNonce,
          );

          final userCred = await _auth.signInWithCredential(oauthCred).timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw FirebaseAuthException(
                code: 'timeout',
                message: 'Firebase sign-in timed out. Please try again.',
              );
            },
          );

          // Optionally update display name if available
          final fullName = credential.givenName;
          if (fullName != null &&
              (userCred.user?.displayName?.isEmpty ?? true)) {
            await userCred.user!.updateDisplayName(fullName);
          }

          FirestoreUser.instance.ensureUserDoc(userCred.user!).catchError((e) {
            debugPrint('User doc creation failed (non-blocking): $e');
          });
          return userCred;
        } on SignInWithAppleAuthorizationException catch (e) {
          if (kAuthDebugLogs) {
            debugPrint(
                '[AUTH][Apple] Authorization error: ${e.code.name}: ${e.message}');
          }
          switch (e.code) {
            case AuthorizationErrorCode.canceled:
              throw const AuthFlowException(
                code: AuthFlowCode.canceled,
                message: 'Sign-in canceled.',
              );
            case AuthorizationErrorCode.failed:
              throw AuthFlowException(
                code: AuthFlowCode.unknown,
                message:
                    'Apple sign-in failed. Ensure you’re signed into iCloud and try again.',
                details: '${e.code.name}: ${e.message}'.trim(),
              );
            case AuthorizationErrorCode.invalidResponse:
              throw AuthFlowException(
                code: AuthFlowCode.unknown,
                message: 'Invalid response from Apple. Please try again.',
                details: '${e.code.name}: ${e.message}'.trim(),
              );
            case AuthorizationErrorCode.notHandled:
              throw AuthFlowException(
                code: AuthFlowCode.unknown,
                message:
                    'Apple sign-in was not handled. Try again or restart the app.',
                details: '${e.code.name}: ${e.message}'.trim(),
              );
            case AuthorizationErrorCode.notInteractive:
              throw const AuthFlowException(
                code: AuthFlowCode.unknown,
                message:
                    'Apple sign-in requires user interaction. Please try again.',
              );
            case AuthorizationErrorCode.unknown:
              throw AuthFlowException(
                code: AuthFlowCode.unknown,
                message: 'Apple sign-in failed. Please try again.',
                details: '${e.code.name}: ${e.message}'.trim(),
              );
          }
        } on FirebaseAuthException catch (e) {
          _handleFirebaseAuthErrors(e);
          rethrow;
        }
      }

      throw const AuthFlowException(
        code: AuthFlowCode.unsupported,
        message: 'Sign in with Apple not supported on this platform.',
      );
    } finally {
      _signInInProgress = false;
    }
  }

  /// Signs out of Firebase (and Google on mobile).
  Future<void> signOut() async {
    if (_isMobile) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {/* ignore */}
    }
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  // ---------------------------- Web flow -------------------------------------

  Future<UserCredential> _signInWeb() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      final userCred = await _auth.signInWithPopup(provider);
      await FirestoreUser.instance.ensureUserDoc(userCred.user!);
      return userCred;
    } on FirebaseAuthException catch (e) {
      if (kAuthDebugLogs) debugPrint('[AUTH] Web popup failed: ${e.code}');
      const fallback = {
        'popup-blocked',
        'popup-closed-by-user',
        'unauthorized-domain',
        'operation-not-supported-in-this-environment',
      };
      if (fallback.contains(e.code)) {
        await _auth.signInWithRedirect(provider);
        // Control resumes via getRedirectResult() on next load.
        throw const AuthFlowException(
          code: AuthFlowCode.redirecting,
          message: 'Redirecting to Google…',
        );
      }
      _handleFirebaseAuthErrors(e);
      rethrow;
    }
  }

  // -------------------------- Desktop (PKCE) ---------------------------------

  /// Full OAuth (PKCE + localhost loopback) for Windows/macOS/Linux.
  /// Returns null if user cancels/times out.
  Future<_GoogleTokens?> _desktopGoogleOAuth() async {
    _ensureDesktopSecret(); // fail fast if the secret wasn’t baked into this build

    // CSRF protection
    final state = _randomUrlSafe(32);

    // 1) Start loopback server (random ephemeral port)
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    if (kAuthDebugLogs) {
      debugPrint(
          '[AUTH] clientId=$_googleDesktopClientId redirect=$redirectUri');
    }

    // 2) PKCE (verifier -> S256 challenge)
    final verifier = _randomUrlSafe(64);
    final challenge = _b64UrlNoPad(sha256.convert(utf8.encode(verifier)).bytes);

    // 3) Build auth URL (use SAME redirectUri)
    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': _googleDesktopClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
      'state': state,
      // 'access_type': 'offline', // optional; not required for sign-in
    });

    // 4) Launch system browser
    final launched =
        await launchUrl(authUri, mode: LaunchMode.externalApplication);
    if (!launched) {
      await server.close(force: true);
      throw const AuthFlowException(
        code: AuthFlowCode.browserOpenFailed,
        message: 'Could not open your browser for Google sign-in.',
      );
    }

    // 5) Wait for redirect to our loopback
    String? codeParam;
    try {
      final request = await server.first.timeout(_kDesktopAuthWaitTimeout);
      final qp = request.requestedUri.queryParameters;

      final html = (qp['error'] != null)
          ? _htmlClose(
              'Sign-in failed: ${qp['error']}. You can close this window.')
          : _htmlClose('Sign-in complete. You can close this window.');
      request.response.headers.set('Content-Type', 'text/html; charset=utf-8');
      request.response.write(html);
      await request.response.close();

      // CSRF check + error handling
      if (qp['state'] != state) {
        throw const AuthFlowException(
          code: AuthFlowCode.security,
          message: 'Security check failed. Please try again.',
        );
      }
      if (qp['error'] == 'access_denied') {
        return null; // user canceled at Google prompt
      }

      codeParam = qp['code'];
      if (codeParam == null || codeParam.isEmpty) {
        throw const AuthFlowException(
          code: AuthFlowCode.unknown,
          message: 'Google did not return an authorization code.',
        );
      }
    } on TimeoutException {
      return null;
    } finally {
      await server.close(force: true);
    }

    // Make a non-null local so we don't need '!'
    final String code = codeParam;

    // 6) Exchange code for tokens (same redirectUri). Include secret if provided.
    final body = <String, String>{
      'client_id': _googleDesktopClientId,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    };
    if (_googleDesktopClientSecret.isNotEmpty) {
      body['client_secret'] = _googleDesktopClientSecret;
    }

    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: body,
          )
          .timeout(_kTokenPostTimeout);
    } on TimeoutException {
      throw const AuthFlowException(
        code: AuthFlowCode.network,
        message: 'Timed out talking to Google. Check your connection.',
      );
    } on SocketException catch (e) {
      throw AuthFlowException(
        code: AuthFlowCode.network,
        message: 'Network error. Please check your connection.',
        details: e.message,
      );
    }

    if (resp.statusCode != 200) {
      final err = _parseGoogleError(resp.body);
      throw AuthFlowException(
        code: _mapGoogleErrorToCode(err.code),
        message: _mapGoogleErrorToMessage(err),
        details: 'HTTP ${resp.statusCode}: ${resp.body}',
      );
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final idToken = json['id_token'] as String?;
    final accessToken = json['access_token'] as String?;
    if (idToken == null || accessToken == null) {
      throw const AuthFlowException(
        code: AuthFlowCode.unknown,
        message: 'Missing tokens from Google.',
      );
    }
    return _GoogleTokens(idToken: idToken, accessToken: accessToken);
  }

  // ------------------------ Error mapping/helpers ----------------------------

  void _ensureDesktopSecret() {
    if (_googleDesktopClientSecret.isEmpty) {
      throw const AuthFlowException(
        code: AuthFlowCode.misconfigured,
        message: 'Build missing GOOGLE_DESKTOP_CLIENT_SECRET.',
      );
    }
  }

  void _handleFirebaseAuthErrors(FirebaseAuthException e) {
    if (kAuthDebugLogs) {
      debugPrint('[AUTH] FirebaseAuthException ${e.code}: ${e.message}');
    }
    switch (e.code) {
      case 'invalid-credential':
        throw const AuthFlowException(
          code: AuthFlowCode.misconfigured,
          message:
              'Invalid credentials from identity provider. For Apple: ensure device is signed into iCloud, Apple returned an identity token, and the Firebase project has Apple provider enabled. Also confirm the nonce handling is correct (SHA256-hex to Apple, raw nonce to Firebase).',
        );
      case 'account-exists-with-different-credential':
        throw const AuthFlowException(
          code: AuthFlowCode.accountExistsDifferentCred,
          message:
              'An account exists with a different sign-in method. Use your original method, then link Google in Settings.',
        );
      case 'operation-not-allowed':
        throw const AuthFlowException(
          code: AuthFlowCode.misconfigured,
          message: 'Google sign-in is disabled for this project.',
        );
      case 'network-request-failed':
        throw const AuthFlowException(
          code: AuthFlowCode.network,
          message: 'Network error. Please check your connection.',
        );
      case 'too-many-requests':
        throw const AuthFlowException(
          code: AuthFlowCode.rateLimited,
          message: 'Too many attempts. Please try again later.',
        );
      default:
        throw AuthFlowException(
          code: AuthFlowCode.unknown,
          message: 'Sign-in failed (${e.code}).',
          details: e.message,
        );
    }
  }

  static _GoogleApiError _parseGoogleError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return _GoogleApiError(
        code: (m['error'] ?? '').toString(),
        description: (m['error_description'] ?? '').toString(),
      );
    } catch (_) {
      return const _GoogleApiError(code: 'unknown', description: '');
    }
  }

  static AuthFlowCode _mapGoogleErrorToCode(String code) {
    switch (code) {
      case 'invalid_client':
      case 'unauthorized_client':
        return AuthFlowCode.misconfigured;
      case 'invalid_grant':
      case 'redirect_uri_mismatch':
        return AuthFlowCode.misconfigured;
      case 'access_denied':
        return AuthFlowCode.canceled;
      default:
        return AuthFlowCode.unknown;
    }
  }

  static String _mapGoogleErrorToMessage(_GoogleApiError err) {
    switch (err.code) {
      case 'invalid_client':
        return 'OAuth client not found or misconfigured.';
      case 'unauthorized_client':
        return 'This client is not allowed to request access.';
      case 'invalid_grant':
        return 'Authorization code invalid or expired. Please try again.';
      case 'redirect_uri_mismatch':
        return 'Redirect URI mismatch. Restart the app and try again.';
      case 'access_denied':
        return 'You denied access.';
      default:
        return 'Google sign-in error.';
    }
  }

  // ----------------------------- Utils --------------------------------------

  static String _randomUrlSafe(int length) {
    final r = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static String _b64UrlNoPad(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static String _htmlClose(String msg) => '''
<!doctype html><meta charset="utf-8">
<title>FermentaCraft</title>
<style>body{font-family:system-ui,Segoe UI,Roboto,Helvetica,Arial;margin:2rem;}</style>
<p>$msg</p>
<script>setTimeout(()=>{window.close()},500);</script>
''';

  // Prevent overlapping sign-in attempts.
  static bool _signInInProgress = false;
}

// ----------------------------- Types ----------------------------------------

class _GoogleTokens {
  final String idToken;
  final String accessToken;
  const _GoogleTokens({required this.idToken, required this.accessToken});
}

class _GoogleApiError {
  final String code;
  final String description;
  const _GoogleApiError({required this.code, required this.description});
}

/// A user-friendly, app-level exception you can map to UI.
class AuthFlowException implements Exception {
  final AuthFlowCode code;
  final String message;
  final String? details;
  const AuthFlowException({
    required this.code,
    required this.message,
    this.details,
  });
  @override
  String toString() =>
      'AuthFlowException($code, $message${details != null ? ' — $details' : ''})';
}

enum AuthFlowCode {
  canceled,
  busy,
  network,
  misconfigured,
  browserOpenFailed,
  rateLimited,
  security,
  redirecting,
  unsupported,
  accountExistsDifferentCred, // <-- added to fix enum error
  unknown,
}
