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
      status: kind === 'deposit' ? 'posted' : 'pending',
    };
  }

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
