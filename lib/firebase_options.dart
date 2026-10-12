import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configure these values with --dart-define when building the app.
/// No Firebase secrets are committed to the repository.
class FirebaseOptionsConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
  static const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');

  static bool get isConfigured {
    final commonValuesPresent = apiKey.isNotEmpty &&
        appId.isNotEmpty &&
        messagingSenderId.isNotEmpty &&
        projectId.isNotEmpty;
    if (!commonValuesPresent) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return iosAppId.isNotEmpty && iosBundleId.isNotEmpty;
    }
    return true;
  }

  static FirebaseOptions get current {
    if (!isConfigured) {
      throw StateError('Firebase is not configured. See docs/FIREBASE_SETUP.md.');
    }
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain: authDomain.isEmpty ? null : authDomain,
        storageBucket: storageBucket.isEmpty ? null : storageBucket,
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return FirebaseOptions(
          apiKey: apiKey,
          appId: iosAppId.isEmpty ? appId : iosAppId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
          iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
        );
      default:
        return FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: messagingSenderId,
          projectId: projectId,
          storageBucket: storageBucket.isEmpty ? null : storageBucket,
        );
    }
  }
}
