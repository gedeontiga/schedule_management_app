import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/firebase_manager.dart';

class FirebaseAuthService {
  final _auth = FirebaseManager.auth;
  final _firestore = FirebaseManager.firestore;
  final _googleSignIn = GoogleSignIn.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(username);
      await _createUserDocument(
        userId: credential.user!.uid,
        email: email,
        username: username,
        authMethod: 'email',
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final GoogleAuthProvider provider = GoogleAuthProvider();
        final userCredential = await _auth.signInWithPopup(provider);

        if (userCredential.user != null) {
          await _createUserDocument(
            userId: userCredential.user!.uid,
            email: userCredential.user!.email ?? '',
            username: userCredential.user!.displayName ?? 'User',
            authMethod: 'google',
            photoUrl: userCredential.user!.photoURL,
          );
        }

        return userCredential;
      }

      await _googleSignIn.initialize();

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _createUserDocument(
          userId: userCredential.user!.uid,
          email: userCredential.user!.email ?? '',
          username: userCredential.user!.displayName ?? 'User',
          authMethod: 'google',
          photoUrl: userCredential.user!.photoURL,
        );
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception('Failed to sign in with Google: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).delete();
        await user.delete();
      }
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> reauthenticate(String password) async {
    try {
      final user = _auth.currentUser;
      if (user?.email == null) {
        throw Exception('No user signed in');
      }
      final credential = EmailAuthProvider.credential(
        email: user!.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required String username,
    required String authMethod,
    String? photoUrl,
  }) async {
    final userDoc = _firestore.collection('users').doc(userId);
    final docSnapshot = await userDoc.get();

    final userData = {
      'email': email,
      'username': username,
      'auth_method': authMethod,
      'photo_url': photoUrl,
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (!docSnapshot.exists) {
      userData['created_at'] = FieldValue.serverTimestamp();
      await userDoc.set(userData);
    } else {
      await userDoc.update(userData);
    }
  }

  Exception _handleAuthException(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'weak-password':
        message = 'The password is too weak. Use at least 6 characters.';
        break;
      case 'email-already-in-use':
        message = 'An account already exists with this email.';
        break;
      case 'invalid-email':
        message = 'The email address is invalid.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'user-not-found':
        message = 'No account found with this email.';
        break;
      case 'wrong-password':
        message = 'Incorrect password. Please try again.';
        break;
      case 'too-many-requests':
        message = 'Too many failed attempts. Please try again later.';
        break;
      case 'operation-not-allowed':
        message = 'This sign-in method is not enabled.';
        break;
      case 'requires-recent-login':
        message = 'Please sign in again to perform this action.';
        break;
      default:
        message = e.message ?? 'An authentication error occurred.';
    }
    return Exception(message);
  }
}
