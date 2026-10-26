import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB_example_replace_me',
    appId: '1:000000000:android:000000000000000',
    messagingSenderId: '000000000',
    projectId: 'trotro-ticket-f148a',
    storageBucket: 'trotro-ticket-f148a.firebasestorage.app',
  );
}
