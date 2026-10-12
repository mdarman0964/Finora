import 'dart:io';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Stores receipt images in the signed-in user's Google Drive.
/// Mess receipts are explicitly shared with the mess members' Google accounts.
class GoogleDriveReceiptService {
  GoogleDriveReceiptService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: <String>[drive.DriveApi.driveFileScope],
              clientId: _iosClientId.isEmpty ? null : _iosClientId,
              serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
            );

  static const _serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _iosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  final GoogleSignIn _googleSignIn;

  Future<drive.DriveApi> _api() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('রসিদ Google Drive-এ রাখতে Google অ্যাকাউন্টে সাইন ইন করুন।');
    }
    return drive.DriveApi(_GoogleAuthClient(await account.authHeaders));
  }

  Future<String> uploadReceipt(
    File image, {
    required String scope,
    String? messId,
    List<String> shareWithEmails = const <String>[],
  }) async {
    if (scope == 'mess' && shareWithEmails.isEmpty) {
      throw StateError('মেসের সদস্যদের Google অ্যাকাউন্টের ইমেইল পাওয়া যায়নি। সদস্যদের অ্যাপ খুলে আবার চেষ্টা করতে বলুন।');
    }
    final api = await _api();
    final file = await api.files.create(
      drive.File(
        name: 'finora-receipt-${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
        description: 'Finora ${scope == 'mess' ? 'mess $messId' : 'personal'} receipt',
        appProperties: <String, String>{
          'app': 'Finora',
          'scope': scope,
          if (messId != null) 'messId': messId,
        },
      ),
      uploadMedia: drive.Media(image.openRead(), await image.length(),
          contentType: 'image/jpeg'),
      $fields: 'id,name',
    );
    final id = file.id;
    if (id == null || id.isEmpty) {
      throw StateError('Google Drive ফাইল আইডি পাওয়া যায়নি।');
    }

    if (scope == 'mess') {
      try {
        for (final email in shareWithEmails.map((e) => e.trim().toLowerCase()).toSet()) {
          if (email.isEmpty) continue;
          await api.permissions.create(
            drive.Permission(type: 'user', role: 'reader', emailAddress: email),
            id,
            sendNotificationEmail: false,
          );
        }
      } catch (_) {
        // Avoid leaving an inaccessible shared receipt in Drive if sharing fails.
        try {
          await api.files.delete(id);
        } catch (_) {}
        rethrow;
      }
    }
    return 'drive:$id';
  }

  Future<Uint8List> receiptBytes(String receiptPath) async {
    final id = _fileId(receiptPath);
    final api = await _api();
    final response = await api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    if (response is! drive.Media) {
      throw StateError('Google Drive থেকে রসিদের ছবি পাওয়া যায়নি।');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  String _fileId(String path) {
    if (!path.startsWith('drive:') || path.length <= 6) {
      throw ArgumentError('রসিদের Google Drive আইডি সঠিক নয়।');
    }
    return path.substring(6);
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
