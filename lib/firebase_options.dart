import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA2WOvN7YLqM6hZOtVBfMFa0YnfCdTphR4',
    appId: '1:267399612002:android:da35fa75668299e4c2b33b',
    messagingSenderId: '267399612002',
    projectId: 'trotro-ticket-f148a',
    storageBucket: 'trotro-ticket-f148a.firebasestorage.app',
  );
}
