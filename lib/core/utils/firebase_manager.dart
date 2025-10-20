import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../firebase_options.dart';

class FirebaseManager {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;

  static String? get currentUserId => auth.currentUser?.uid;
  static Stream<User?> get authStateChanges => auth.authStateChanges();

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Firestore settings can be configured after initialization.
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      rethrow;
    }
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
