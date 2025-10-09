import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class FirebaseManager {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;

  static User? get currentUser => auth.currentUser;
  static String? get currentUserId => auth.currentUser?.uid;
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: _getFirebaseOptions(),
      );

      // Enable offline persistence for Firestore
      await _configureFirestore();
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> _configureFirestore() async {
    final settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    firestore.settings = settings;

    // Enable network for real-time updates
    await firestore.enableNetwork();
  }

  static FirebaseOptions _getFirebaseOptions() {
    // Add your Firebase configuration here
    // You can get this from Firebase Console > Project Settings

    if (defaultTargetPlatform == TargetPlatform.android) {
      return const FirebaseOptions(
        apiKey: 'YOUR_ANDROID_API_KEY',
        appId: 'YOUR_ANDROID_APP_ID',
        messagingSenderId: 'YOUR_SENDER_ID',
        projectId: 'YOUR_PROJECT_ID',
        storageBucket: 'YOUR_STORAGE_BUCKET',
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const FirebaseOptions(
        apiKey: 'YOUR_IOS_API_KEY',
        appId: 'YOUR_IOS_APP_ID',
        messagingSenderId: 'YOUR_SENDER_ID',
        projectId: 'YOUR_PROJECT_ID',
        storageBucket: 'YOUR_STORAGE_BUCKET',
        iosBundleId: 'YOUR_IOS_BUNDLE_ID',
      );
    }

    throw UnsupportedError('Platform not supported');
  }

  static Future<bool> isOnline() async {
    try {
      await firestore
          .collection('_connectivity_check')
          .doc('test')
          .get(const GetOptions(source: Source.server));
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<void> setNetworkEnabled(bool enabled) async {
    try {
      if (enabled) {
        await firestore.enableNetwork();
      } else {
        await firestore.disableNetwork();
      }
    } catch (e) {
      // Handle error
    }
  }

  static Future<void> clearCache() async {
    try {
      await firestore.clearPersistence();
    } catch (e) {
      // Handle error
    }
  }
}
