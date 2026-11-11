import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-movies-rules';
const rulesPath = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
  'firestore.rules',
);

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { rules: readFileSync(rulesPath, 'utf8') },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
});

after(async () => {
  await environment?.cleanup();
});

function profile(uid) {
  return {
    uid,
    name: 'Test User',
    email: `${uid}@example.com`,
    phone: '123456789',
    avatar: 'assets/avatars/avatar_hoodie.jpg',
    createdAt: serverTimestamp(),
  };
}

function movieEntry(id, timeField) {
  return {
    id,
    title: 'Doctor Strange in the Multiverse of Madness',
    year: '2022',
    poster: 'assets/doctor_strange_reviews_onboarding.jpg',
    [timeField]: serverTimestamp(),
  };
}

function review(uid, rating = 5) {
  return {
    userId: uid,
    userName: 'Test User',
    rating,
    comment: 'A test review',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

test('profile reads and writes are limited to the matching authenticated UID', async () => {
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const anonymous = environment.unauthenticatedContext().firestore();
  const aliceProfile = doc(alice, 'users/alice');

  await assertSucceeds(setDoc(aliceProfile, profile('alice')));
  await assertSucceeds(getDoc(aliceProfile));
  await assertSucceeds(updateDoc(aliceProfile, { name: 'Alice Updated' }));
  await assertFails(getDoc(doc(bob, 'users/alice')));
  await assertFails(getDocs(collection(alice, 'users')));
  await assertFails(setDoc(doc(bob, 'users/alice'), profile('alice')));
  await assertFails(
    setDoc(doc(bob, 'users/bob'), {
      ...profile('bob'),
      createdAt: new Date(),
    }),
  );
  await assertFails(getDoc(doc(anonymous, 'users/alice')));
  await assertFails(updateDoc(aliceProfile, { uid: 'bob' }));
  await assertFails(updateDoc(aliceProfile, { email: 'changed@example.com' }));
});

test('Watch List, Favorites, and Recently Watched are UID isolated', async () => {
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const anonymous = environment.unauthenticatedContext().firestore();

  for (const [collectionName, timeField] of [
    ['watchlist', 'addedAt'],
    ['favorites', 'addedAt'],
    ['recently_watched', 'watchedAt'],
  ]) {
    const aliceEntry = doc(alice, `users/alice/${collectionName}/movie-1`);
    const bobEntry = doc(bob, `users/bob/${collectionName}/movie-1`);
    const entry = movieEntry('movie-1', timeField);

    await assertSucceeds(setDoc(aliceEntry, entry));
    await assertSucceeds(getDoc(aliceEntry));
    await assertSucceeds(
      updateDoc(aliceEntry, {
        title: 'Updated title',
        [timeField]: serverTimestamp(),
      }),
    );
    await assertSucceeds(setDoc(bobEntry, movieEntry('movie-1', timeField)));
    await assertFails(
      getDoc(doc(anonymous, `users/alice/${collectionName}/movie-1`)),
    );
    await assertFails(
      setDoc(
        doc(anonymous, `users/alice/${collectionName}/anonymous-entry`),
        movieEntry('anonymous-entry', timeField),
      ),
    );
    await assertFails(getDoc(doc(bob, `users/alice/${collectionName}/movie-1`)));
    await assertFails(
      updateDoc(doc(bob, `users/alice/${collectionName}/movie-1`), {
        title: 'Modified by Bob',
      }),
    );
    await assertFails(
      deleteDoc(doc(bob, `users/alice/${collectionName}/movie-1`)),
    );
    await assertFails(
      setDoc(
        doc(bob, `users/alice/${collectionName}/movie-2`),
        movieEntry('movie-2', timeField),
      ),
    );
    await assertFails(
      setDoc(
        doc(alice, `users/alice/${collectionName}/wrong-id`),
        movieEntry('movie-1', timeField),
      ),
    );
    await assertFails(
      setDoc(
        doc(alice, `users/alice/${collectionName}/spoofed-time`),
        { ...movieEntry('spoofed-time', timeField), [timeField]: new Date() },
      ),
    );
  }

  const recent = doc(alice, 'users/alice/recently_watched/movie-1');
  await assertSucceeds(
    updateDoc(recent, { watchedAt: serverTimestamp() }),
  );
});

test('Watch List and Favorites merge writes retain existing extra fields', async () => {
  const alice = environment.authenticatedContext('alice').firestore();

  for (const collectionName of ['watchlist', 'favorites']) {
    const path = `users/alice/${collectionName}/legacy-movie`;
    const reference = doc(alice, path);

    await environment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), path), {
        ...movieEntry('legacy-movie', 'addedAt'),
        legacyField: 'preserve me',
      });
    });

    await assertSucceeds(
      setDoc(
        reference,
        movieEntry('legacy-movie', 'addedAt'),
        { merge: true },
      ),
    );
    const saved = await assertSucceeds(getDoc(reference));
    assert.equal(saved.data()?.legacyField, 'preserve me');
  }
});

test('reviews are readable by signed-in users and writable only by their UID owner', async () => {
  const alice = environment.authenticatedContext('alice').firestore();
  const bob = environment.authenticatedContext('bob').firestore();
  const anonymous = environment.unauthenticatedContext().firestore();
  const aliceReview = doc(alice, 'movies/movie-1/reviews/alice');
  const bobReview = doc(bob, 'movies/movie-1/reviews/bob');

  await assertSucceeds(setDoc(aliceReview, review('alice')));
  await assertSucceeds(
    updateDoc(aliceReview, { rating: 4, updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(getDoc(doc(bob, 'movies/movie-1/reviews/alice')));
  await assertSucceeds(
    getDocs(collection(bob, 'movies/movie-1/reviews')),
  );
  await assertFails(getDoc(doc(anonymous, 'movies/movie-1/reviews/alice')));
  await assertFails(updateDoc(aliceReview, { userId: 'bob' }));
  await assertFails(
    updateDoc(doc(bob, 'movies/movie-1/reviews/alice'), {
      comment: 'Changed by Bob',
    }),
  );
  await assertSucceeds(deleteDoc(aliceReview));

  for (const invalidRating of [0, 6, '5']) {
    await assertFails(
      setDoc(
        doc(alice, `movies/movie-1/reviews/invalid-${String(invalidRating)}`),
        review('alice', invalidRating),
      ),
    );
  }

  await assertFails(
    setDoc(doc(alice, 'movies/movie-1/reviews/bob'), review('bob')),
  );
  await assertFails(
    setDoc(doc(bob, 'movies/movie-1/reviews/alice'), review('alice')),
  );
  await assertSucceeds(setDoc(bobReview, review('bob')));
});

