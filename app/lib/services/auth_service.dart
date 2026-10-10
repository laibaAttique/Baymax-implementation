import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'user_session.dart';

/// Authentication for Module 1 (FE-1 register, FE-2 login/logout),
/// backed by Firebase Auth (email + password, Google).
class AuthException implements Exception {
  final String message;

  /// True when the user dismissed a sign-in prompt; not an error to show.
  final bool cancelled;

  const AuthException(this.message, {this.cancelled = false});

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  /// Waits for Firebase to restore any saved session, then reports it.
  Future<bool> isSignedIn() async => (await _auth.authStateChanges().first) != null;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e, 'Login failed'));
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(displayName);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e, 'Sign up failed'));
    }
  }

  /// Requires the Google provider to be enabled in the Firebase console.
  Future<void> signInWithGoogle() async {
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await _auth.signInWithPopup(provider);
      } else {
        await _auth.signInWithProvider(provider);
      }
    } on FirebaseAuthException catch (e) {
      const cancelCodes = {'canceled', 'web-context-canceled', 'popup-closed-by-user', 'cancelled-popup-request'};
      if (cancelCodes.contains(e.code)) {
        throw const AuthException('Sign-in cancelled.', cancelled: true);
      }
      throw AuthException(_messageFor(e, 'Google sign-in failed'));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e, 'Could not send reset email'));
    }
  }

  Future<void> signOut() async {
    UserSession.instance.clear();
    await _auth.signOut();
  }

  String _messageFor(FirebaseAuthException e, String fallback) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in the Firebase console.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? fallback;
    }
  }
}
