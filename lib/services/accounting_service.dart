import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AccountingService {
  AccountingService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  User get user {
    final current = _auth.currentUser;
    if (current == null) throw StateError('Please sign in first.');
    return current;
  }

  CollectionReference<Map<String, dynamic>> _personalTransactions(String uid) =>
      _db.collection('users').doc(uid).collection('personalTransactions');

  CollectionReference<Map<String, dynamic>> _loans(String uid) =>
      _db.collection('users').doc(uid).collection('loans');

  Future<String> createMess(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('মেসের নাম লিখুন।');
    final uid = user.uid;
    final code = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final ref = _db.collection('messes').doc();
    await ref.set({
      'name': trimmed,
      'inviteCode': code,
      'ownerUid': uid,
      'memberUids': [uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(uid).set({
      'displayName': user.displayName ?? user.email ?? 'Member',
      'email': user.email,
      'messId': ref.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  Future<void> joinMess(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('ইনভাইট কোড লিখুন।');
    final matches = await _db.collection('messes')
        .where('inviteCode', isEqualTo: code).limit(1).get();
    if (matches.docs.isEmpty) throw StateError('এই ইনভাইট কোডটি পাওয়া যায়নি।');
    final mess = matches.docs.first;
    final uid = user.uid;
    await _db.collection('messes').doc(mess.id).update({
      'memberUids': FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('users').doc(uid).set({
      'displayName': user.displayName ?? user.email ?? 'Member',
      'email': user.email,
      'messId': mess.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String?> currentMessId() async {
    final doc = await _db.collection('users').doc(user.uid).get();
    return doc.data()?['messId'] as String?;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> messStream(String messId) =>
      _db.collection('messes').doc(messId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> messTransactions(String messId) =>
      _db.collection('messes').doc(messId).collection('transactions')
          .orderBy('transactionDate', descending: true).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> personalTransactions() =>
      _personalTransactions(user.uid)
          .orderBy('transactionDate', descending: true).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> loans() =>
      _loans(user.uid).orderBy('createdAt', descending: true).snapshots();

  Future<void> addMessTransaction({
    required String messId,
    required String kind,
    required int amountMinor,
    required String category,
    required String description,
    required DateTime transactionDate,
    String? receiptPath,
    String splitStrategy = 'equal',
  }) async {
    if (amountMinor <= 0) throw ArgumentError('টাকার পরিমাণ শূন্যের বেশি হতে হবে।');
    await _db.collection('messes').doc(messId).collection('transactions').add({
      'kind': kind,
      'amountMinor': amountMinor,
      'currencyCode': 'BDT',
      'category': category.trim(),
      'description': description.trim(),
      'transactionDate': Timestamp.fromDate(transactionDate),
      'paidByUid': user.uid,
      'createdBy': user.uid,
      'receiptStoragePath': receiptPath,
      'splitStrategy': splitStrategy,
      'status': 'posted',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addPersonalTransaction({
    required String kind,
    required int amountMinor,
    required String category,
    required String description,
    required DateTime transactionDate,
    String? receiptPath,
  }) async {
    if (amountMinor <= 0) throw ArgumentError('টাকার পরিমাণ শূন্যের বেশি হতে হবে।');
    await _personalTransactions(user.uid).add({
      'ownerUid': user.uid,
      'kind': kind,
      'amountMinor': amountMinor,
      'currencyCode': 'BDT',
      'category': category.trim(),
      'description': description.trim(),
      'transactionDate': Timestamp.fromDate(transactionDate),
      'receiptStoragePath': receiptPath,
      'sharedWithUids': <String>[],
      'status': 'posted',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadReceipt(
    File image, {
    required String scope,
    String? messId,
  }) async {
    final uid = user.uid;
    final path = scope == 'mess'
        ? 'mess/${messId ?? ''}/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg'
        : 'personal/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('receipts/$path');
    await ref.putFile(image, SettableMetadata(contentType: 'image/jpeg'));
    return ref.fullPath;
  }

  Future<String> receiptUrl(String storagePath) =>
      _storage.ref().child(storagePath).getDownloadURL();

  Future<void> addLoan({
    required String counterpartyName,
    required String direction,
    required int principalMinor,
    required DateTime? dueDate,
    String notes = '',
  }) async {
    if (principalMinor <= 0) throw ArgumentError('টাকার পরিমাণ শূন্যের বেশি হতে হবে।');
    await _loans(user.uid).add({
      'ownerUid': user.uid,
      'counterpartyName': counterpartyName.trim(),
      'direction': direction,
      'principalMinor': principalMinor,
      'paidMinor': 0,
      'currencyCode': 'BDT',
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate),
      'notes': notes.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addLoanRepayment({
    required String loanId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) throw ArgumentError('টাকার পরিমাণ শূন্যের বেশি হতে হবে।');
    final ref = _loans(user.uid).doc(loanId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('Loan not found.');
      final data = snapshot.data()!;
      final principal = data['principalMinor'] as int? ?? 0;
      final paid = data['paidMinor'] as int? ?? 0;
      if (paid + amountMinor > principal) {
        throw StateError('পরিশোধের পরিমাণ বাকি টাকার চেয়ে বেশি।');
      }
      final newPaid = paid + amountMinor;
      transaction.update(ref, {
        'paidMinor': newPaid,
        'status': newPaid == principal ? 'settled' : 'partiallyPaid',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(ref.collection('repayments').doc(), {
        'amountMinor': amountMinor,
        'recordedBy': user.uid,
        'recordedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
