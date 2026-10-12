import 'dart:io';
import 'dart:math' as math;

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
    final current = user;
    final uid = current.uid;
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random.secure();
    final code = List.generate(
      10, (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    final ref = _db.collection('messes').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'name': trimmed,
      'inviteCode': code,
      'defaultSplitStrategy': 'equal',
      'ownerUid': uid,
      'memberUids': [uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('members').doc(uid), {
      'uid': uid,
      'displayName': current.displayName ?? 'Member',
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('messInvites').doc(code), {
      'messId': ref.id,
      'ownerUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_db.collection('users').doc(uid), {
      'displayName': current.displayName ?? current.email ?? 'Member',
      'email': current.email,
      'messId': ref.id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // The mess, owner profile, invite, and private user pointer are committed
    // together so a transient failure cannot leave a half-created mess.
    await batch.commit();
    return code;
  }

  Future<void> joinMess(String inviteCode) async {
    final code = inviteCode.trim().toUpperCase();
    if (code.isEmpty) throw ArgumentError('ইনভাইট কোড লিখুন।');
    final inviteSnapshot = await _db.collection('messInvites').doc(code).get();
    final invite = inviteSnapshot.data();
    final messId = invite?['messId'] as String?;
    if (!inviteSnapshot.exists || messId == null) {
      throw StateError('এই ইনভাইট কোডটি পাওয়া যায়নি।');
    }
    final current = user;
    final uid = current.uid;
    final messRef = _db.collection('messes').doc(messId);
    final messSnapshot = await messRef.get();
    final mess = messSnapshot.data();
    if (mess == null || mess['inviteCode'] != code) {
      throw StateError('ইনভাইট কোডের সঙ্গে মেসের তথ্য মিলছে না।');
    }

    final existingMembers = (mess['memberUids'] as List<dynamic>? ?? const [])
        .whereType<String>().toSet();
    final batch = _db.batch();
    if (!existingMembers.contains(uid)) {
      batch.update(messRef, {
        'memberUids': FieldValue.arrayUnion([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(messRef.collection('members').doc(uid), {
      'uid': uid,
      'displayName': current.displayName ?? 'Member',
      if (!existingMembers.contains(uid)) 'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_db.collection('users').doc(uid), {
      'displayName': current.displayName ?? current.email ?? 'Member',
      'email': current.email,
      'messId': messId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Membership, shared profile, and the user's active-mess pointer move
    // atomically; repeated joins simply repair the profile pointer.
    await batch.commit();
  }

  Future<void> ensureCurrentMemberProfile(String messId) async {
    final current = user;
    final uid = current.uid;
    final ref = _db.collection('messes').doc(messId).collection('members').doc(uid);
    final snapshot = await ref.get();
    final displayName = (current.displayName ?? '').trim();
    final savedName = (snapshot.data()?['displayName'] as String? ?? '').trim();
    if (!snapshot.exists || (displayName.isNotEmpty && displayName != savedName)) {
      await ref.set({
        'uid': uid,
        'displayName': displayName.isNotEmpty ? displayName : 'সদস্য',
        if (snapshot.data()?['joinedAt'] == null) 'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<Map<String, Map<String, dynamic>>> getMemberProfiles(
    String messId,
    List<String> memberUids,
  ) async {
    final ids = memberUids.where((uid) => uid.isNotEmpty).toSet().toList();
    final currentUid = user.uid;
    // Backfill only the signed-in member's own shared profile. Firestore rules
    // deliberately prevent reading another member's private /users document.
    if (ids.contains(currentUid)) {
      await ensureCurrentMemberProfile(messId);
    }
    final profiles = <String, Map<String, dynamic>>{};
    for (var start = 0; start < ids.length; start += 10) {
      final batch = ids.skip(start).take(10).toList();
      final snapshot = await _db.collection('messes').doc(messId)
          .collection('members')
          .where(FieldPath.documentId, whereIn: batch).get();
      for (final doc in snapshot.docs) {
        profiles[doc.id] = doc.data();
      }
    }
    return profiles;
  }

  String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>?> latestMonthClosure(String messId) async {
    final snapshot = await _db.collection('messes').doc(messId)
        .collection('monthClosures')
        .orderBy('monthKey', descending: true)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
  }

  Future<void> closeMessMonth({
    required String messId,
    required DateTime month,
    required Map<String, int> balanceSnapshot,
    required int totalMeals,
    required int mealEligibleExpenseMinor,
    required int incomeMinor,
    required int expenseMinor,
  }) async {
    final uid = user.uid;
    final key = monthKey(month);
    final messRef = _db.collection('messes').doc(messId);
    final closureRef = messRef.collection('monthClosures').doc(key);
    await _db.runTransaction((transaction) async {
      final mess = await transaction.get(messRef);
      final existing = await transaction.get(closureRef);
      if (!mess.exists || mess.data()?['ownerUid'] != uid) {
        throw StateError('শুধু মেসের মালিক মাসের হিসাব বন্ধ করতে পারবেন।');
      }
      if (existing.exists) {
        throw StateError('$key মাসের হিসাব আগে থেকেই বন্ধ করা হয়েছে।');
      }
      transaction.set(closureRef, {
        'monthKey': key,
        'closedBy': uid,
        'closedAt': FieldValue.serverTimestamp(),
        'balanceSnapshot': balanceSnapshot,
        'totalMeals': totalMeals,
        'mealEligibleExpenseMinor': mealEligibleExpenseMinor,
        'incomeMinor': incomeMinor,
        'expenseMinor': expenseMinor,
        'currencyCode': 'BDT',
      });
    });
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

  Stream<QuerySnapshot<Map<String, dynamic>>> mealCounts(String messId) =>
      _db.collection('messes').doc(messId).collection('meals').snapshots();

  Future<void> addMealCount({
    required String messId,
    required int count,
    DateTime? date,
  }) async {
    if (count < 0 || count > 20) {
      throw ArgumentError('মিলের সংখ্যা ০ থেকে ২০-এর মধ্যে হতে হবে।');
    }
    final now = date ?? DateTime.now();
    final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final uid = user.uid;
    final key = monthKey(now);
    final closure = await _db.collection('messes').doc(messId)
        .collection('monthClosures').doc(key).get();
    if (closure.exists) {
      throw StateError('$key মাসের হিসাব বন্ধ। ওই মাসের মিল পরিবর্তন করা যাবে না।');
    }
    await _db.collection('messes').doc(messId).collection('meals')
        .doc('${uid}_$day').set({
      'memberUid': uid,
      'memberName': user.displayName ?? user.email ?? 'Member',
      'dateKey': day,
      'monthKey': key,
      'count': count,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateDefaultSplitStrategy(String messId, String strategy) async {
    const allowed = {'equal', 'meals', 'payer'};
    if (!allowed.contains(strategy)) throw ArgumentError('ভাগের নিয়মটি সঠিক নয়।');
    final ref = _db.collection('messes').doc(messId);
    final snapshot = await ref.get();
    if (snapshot.data()?['ownerUid'] != user.uid) {
      throw StateError('শুধু মেস ম্যানেজার ভাগের নিয়ম পরিবর্তন করতে পারবেন।');
    }
    await ref.update({
      'defaultSplitStrategy': strategy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

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
    String? splitStrategy,
    bool mealEligible = false,
  }) async {
    if (amountMinor <= 0) throw ArgumentError('টাকার পরিমাণ শূন্যের বেশি হতে হবে।');
    final key = monthKey(transactionDate);
    final closure = await _db.collection('messes').doc(messId)
        .collection('monthClosures').doc(key).get();
    if (closure.exists) {
      throw StateError('$key মাসের হিসাব বন্ধ। ওই মাসে নতুন লেনদেন যোগ করা যাবে না।');
    }
    final messSnapshot = await _db.collection('messes').doc(messId).get();
    final messData = messSnapshot.data();
    if (messData == null || !(messData['memberUids'] as List<dynamic>? ?? const []).contains(user.uid)) {
      throw StateError('আপনি এই মেসের সদস্য নন।');
    }
    final memberUidsAtPosting = (messData['memberUids'] as List<dynamic>? ?? const [])
        .whereType<String>().toSet().toList()..sort();
    final effectiveSplit = splitStrategy ?? (messData['defaultSplitStrategy'] as String? ?? 'equal');
    await _db.collection('messes').doc(messId).collection('transactions').add({
      'kind': kind,
      'memberUidsAtPosting': memberUidsAtPosting,
      'amountMinor': amountMinor,
      'currencyCode': 'BDT',
      'category': category.trim(),
      'description': description.trim(),
      'transactionDate': Timestamp.fromDate(transactionDate),
      'monthKey': key,
      'paidByUid': user.uid,
      'createdBy': user.uid,
      'receiptStoragePath': receiptPath,
      'splitStrategy': effectiveSplit,
      'mealEligible': mealEligible,
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
