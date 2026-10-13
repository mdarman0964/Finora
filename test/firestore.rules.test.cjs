const fs = require('node:fs');
const { after, before, beforeEach, describe, it } = require('mocha');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { collection, doc, getDoc, setDoc, addDoc, updateDoc, Timestamp } = require('firebase/firestore');

describe('Finora Firestore security rules', function () {
  let env;
  const projectId = 'demo-finora-rules';

  before(async function () {
    env = await initializeTestEnvironment({
      projectId,
      firestore: { rules: fs.readFileSync('firestore.rules', 'utf8') },
    });
  });

  beforeEach(async function () {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'messes', 'mess1'), {
        name: 'Test mess',
        ownerUid: 'owner1',
        inviteCode: 'ABC123',
        memberUids: ['owner1', 'member1'],
        defaultSplitStrategy: 'equal',
      });
      await setDoc(doc(db, 'messInvites', 'ABC123'), {
        messId: 'mess1',
        ownerUid: 'owner1',
        createdAt: Timestamp.now(),
      });
      await setDoc(doc(db, 'messes', 'mess1', 'monthClosures', '2026-09'), {
        monthKey: '2026-09',
        closedBy: 'owner1',
        balanceSnapshot: { owner1: 0, member1: 0 },
        totalMeals: 0,
        mealEligibleExpenseMinor: 0,
        incomeMinor: 0,
        expenseMinor: 0,
      });
      await setDoc(doc(db, 'users', 'member2'), { privateNote: 'private' });
    });
  });

  after(async function () {
    await env.cleanup();
  });

  function transactionData(uid, monthKey) {
    return {
      kind: 'messExpense',
      memberUidsAtPosting: ['member1', 'owner1'],
      amountMinor: 1000,
      currencyCode: 'BDT',
      category: 'food',
      description: 'Test expense',
      transactionDate: Timestamp.fromDate(new Date(monthKey + '-15T12:00:00Z')),
      monthKey,
      paidByUid: uid,
      createdBy: uid,
      splitStrategy: 'equal',
      mealEligible: true,
      status: 'pending',
    };
  }


  it('allows the owner to create a mess, owner profile, invite, and user pointer atomically', async function () {
    const uid = 'new-owner';
    const db = env.authenticatedContext(uid).firestore();
    const batch = db.batch();
    const messRef = doc(collection(db, 'messes'));
    const inviteCode = 'ABCD234567';
    batch.set(messRef, {
      name: 'My new mess',
      ownerUid: uid,
      inviteCode,
      memberUids: [uid],
      defaultSplitStrategy: 'equal',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    batch.set(doc(db, 'messes', messRef.id, 'members', uid), {
      uid,
      displayName: 'New Owner',
      email: 'owner@example.com',
      joinedAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    batch.set(doc(db, 'messInvites', inviteCode), {
      messId: messRef.id,
      ownerUid: uid,
      createdAt: Timestamp.now(),
    });
    batch.set(doc(db, 'users', uid), {
      displayName: 'New Owner',
      email: 'owner@example.com',
      messId: messRef.id,
      updatedAt: Timestamp.now(),
    });
    await assertSucceeds(batch.commit());
  });

  it('does not let an authenticated user create a mess owned by someone else', async function () {
    const db = env.authenticatedContext('attacker').firestore();
    await assertFails(setDoc(doc(db, 'messes', 'spoofed'), {
      name: 'Spoofed mess',
      ownerUid: 'victim',
      inviteCode: 'ABCD234567',
      memberUids: ['victim'],
      defaultSplitStrategy: 'equal',
    }));
  });

  it('allows a signed-in user to join a mess through a valid invite code', async function () {
    const uid = 'member2';
    const db = env.authenticatedContext(uid).firestore();
    const messRef = doc(db, 'messes', 'mess1');
    const invite = await assertSucceeds(getDoc(doc(db, 'messInvites', 'ABC123')));
    if (!invite.exists()) throw new Error('Test invite should exist');
    await assertSucceeds(getDoc(messRef));
    const batch = db.batch();
    batch.update(messRef, {
      memberUids: ['owner1', 'member1', uid],
      updatedAt: Timestamp.now(),
    });
    batch.set(doc(db, 'messes', 'mess1', 'members', uid), {
      uid,
      displayName: 'Member Two',
      email: 'member2@example.com',
      joinedAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    batch.set(doc(db, 'users', uid), {
      displayName: 'Member Two',
      email: 'member2@example.com',
      messId: 'mess1',
      updatedAt: Timestamp.now(),
    });
    await assertSucceeds(batch.commit());
  });

  it('allows a member to post a transaction in an open month', async function () {
    const db = env.authenticatedContext('member1').firestore();
    await assertSucceeds(addDoc(collection(db, 'messes', 'mess1', 'transactions'),
      transactionData('member1', '2026-10')));
  });

  it('creates expenses as pending and only owner can approve', async function () {
    const memberDb = env.authenticatedContext('member1').firestore();
    const ref = await assertSucceeds(addDoc(collection(memberDb, 'messes', 'mess1', 'transactions'), transactionData('member1', '2026-10')));
    await assertFails(updateDoc(ref, { status: 'posted', approvedByUid: 'member1', approvedAt: Timestamp.now() }));
    const ownerDb = env.authenticatedContext('owner1').firestore();
    await assertSucceeds(updateDoc(doc(ownerDb, ref.path), { status: 'posted', approvedByUid: 'owner1', approvedAt: Timestamp.now() }));
  });

  it('blocks transactions dated in a closed month', async function () {
    const db = env.authenticatedContext('member1').firestore();
    await assertFails(addDoc(collection(db, 'messes', 'mess1', 'transactions'),
      transactionData('member1', '2026-09')));
  });

  it('blocks meal changes in a closed month but allows an open month', async function () {
    const db = env.authenticatedContext('member1').firestore();
    await assertSucceeds(setDoc(doc(db, 'messes', 'mess1', 'meals', 'member1_2026-10-15'), {
      memberUid: 'member1',
      dateKey: '2026-10-15',
      monthKey: '2026-10',
      count: 2,
    }));
    await assertFails(setDoc(doc(db, 'messes', 'mess1', 'meals', 'member1_2026-09-15'), {
      memberUid: 'member1',
      dateKey: '2026-09-15',
      monthKey: '2026-09',
      count: 2,
    }));
  });

  it('keeps another user private document unreadable', async function () {
    const db = env.authenticatedContext('member1').firestore();
    await assertFails(getDoc(doc(db, 'users', 'member2')));
  });
});
