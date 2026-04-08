import { Router } from 'express';
import { db, storage } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { checkInLimiter, generalLimiter } from '../middleware/rateLimiter';
import { todayInTimezone, nowInTimezone } from '../config/timezone';
import { v4 as uuidv4 } from 'uuid';
import { logger } from '../lib/logger';

export const checkInRoutes = Router();

// Submit check-in
checkInRoutes.post('/', checkInLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;

    // Fetch user + settings outside the transaction (reads only, no contention)
    const [userDoc, settingsDoc] = await Promise.all([
      db.collection('users').doc(seniorId).get(),
      db.collection('seniorSettings').doc(seniorId).get(),
    ]);

    if (!userDoc.exists) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    const timezone = userDoc.data()?.timezone || 'America/New_York';
    const today = todayInTimezone(timezone);
    const settingsData = settingsDoc.data() || {};
    const [endH, endM] = (settingsData.windowEnd || '10:00').split(':').map(Number);
    const nowTz = nowInTimezone(timezone);
    const windowEnd = nowTz.hour(endH).minute(endM).second(0).millisecond(0);
    const status = nowTz.isAfter(windowEnd) ? 'late' : 'on_time';
    const checkedInAt = new Date().toISOString();

    // Deterministic doc ID = {seniorId}_{date} — Firestore create() is atomic,
    // so concurrent double-taps both attempt to create the same doc and one wins.
    const checkInId = `${seniorId}_${today}`;
    const checkInRef = db.collection('checkIns').doc(checkInId);

    await db.runTransaction(async (txn) => {
      const existing = await txn.get(checkInRef);
      if (existing.exists && existing.data()?.status !== 'missed') {
        throw Object.assign(new Error('DUPLICATE'), { data: existing.data() });
      }
      txn.set(checkInRef, {
        seniorId,
        checkInDate: today,
        checkedInAt,
        status,
        selfiePath: null,
        hasSelfie: false,
      });
    });

    res.status(201).json({
      message: 'Check-in recorded',
      checkIn: { id: checkInId, checkInDate: today, checkedInAt, status },
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg === 'DUPLICATE') {
      const data = (err as any).data || {};
      res.status(409).json({ error: 'Already checked in today', checkIn: { id: `${req.uid!}_${data.checkInDate}`, ...data } });
      return;
    }
    logger.error('Check-in error', { error: msg });
    res.status(500).json({ error: 'Check-in failed' });
  }
});

// Get today's check-in status
checkInRoutes.get('/today', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;

    const userDoc = await db.collection('users').doc(seniorId).get();
    const timezone = userDoc.exists ? userDoc.data()?.timezone || 'America/New_York' : 'America/New_York';
    const today = todayInTimezone(timezone);

    const checkInSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('checkInDate', '==', today)
      .where('status', '!=', 'missed')
      .limit(1)
      .get();

    if (checkInSnap.empty) {
      res.json({ checkedIn: false });
      return;
    }

    const data = checkInSnap.docs[0].data();
    res.json({
      checkedIn: true,
      checkIn: {
        id: checkInSnap.docs[0].id,
        ...data,
      },
    });
  } catch (err: unknown) {
    logger.error('Get today check-in error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get status' });
  }
});

// Get check-in history
checkInRoutes.get('/history', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const limit = Math.min(parseInt(req.query.limit as string, 10) || 30, 90);

    const checkInsSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .orderBy('checkInDate', 'desc')
      .limit(limit)
      .get();

    const checkIns = checkInsSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.json({ checkIns });
  } catch (err: unknown) {
    logger.error('Get history error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get history' });
  }
});

// Get single check-in by ID
checkInRoutes.get('/:checkInId', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const checkInId = req.params.checkInId as string;
    const doc = await db.collection('checkIns').doc(checkInId).get();

    if (!doc.exists) {
      res.status(404).json({ error: 'Check-in not found' });
      return;
    }

    const data = doc.data()!;

    // Verify access: own check-in or linked caregiver
    if (data.seniorId !== req.uid) {
      const linkSnap = await db
        .collection('seniorCaregiverLinks')
        .where('seniorId', '==', data.seniorId)
        .where('caregiverId', '==', req.uid)
        .where('acceptedAt', '!=', null)
        .limit(1)
        .get();
      if (linkSnap.empty) {
        res.status(403).json({ error: 'Not authorized' });
        return;
      }
    }

    // Generate signed selfie URL if selfie exists
    let selfieUrl: string | null = null;
    if (data.hasSelfie && data.selfiePath) {
      const bucket = storage.bucket();
      const file = bucket.file(data.selfiePath);
      const [url] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 60 * 60 * 1000, // 1 hour
      });
      selfieUrl = url;
    }

    res.json({
      checkIn: {
        id: doc.id,
        ...data,
        selfieUrl,
      },
    });
  } catch (err: unknown) {
    logger.error('Get check-in error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get check-in' });
  }
});

// Generate selfie upload URL (separate from confirming upload)
checkInRoutes.post('/:checkInId/selfie-url', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const checkInId = req.params.checkInId as string;
    const doc = await db.collection('checkIns').doc(checkInId).get();

    if (!doc.exists || doc.data()?.seniorId !== req.uid) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const selfiePath = `selfies/${req.uid}/${checkInId}.jpg`;
    const bucket = storage.bucket();
    const file = bucket.file(selfiePath);

    const [uploadUrl] = await file.getSignedUrl({
      action: 'write',
      expires: Date.now() + 15 * 60 * 1000, // 15 minutes
      contentType: 'image/jpeg',
    });

    // Do NOT set selfiePath yet — wait for upload confirmation
    res.json({ uploadUrl, selfiePath });
  } catch (err: unknown) {
    logger.error('Get selfie URL error', { error: String(err) });
    res.status(500).json({ error: 'Failed to generate upload URL' });
  }
});

// Confirm selfie was uploaded — sets selfiePath on the check-in record
checkInRoutes.post('/:checkInId/selfie-confirm', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const checkInId = req.params.checkInId as string;
    const { selfiePath } = req.body;

    if (!selfiePath) {
      res.status(400).json({ error: 'selfiePath is required' });
      return;
    }

    // Verify the file actually exists in storage before transacting
    const bucket = storage.bucket();
    const file = bucket.file(selfiePath);
    const [exists] = await file.exists();
    if (!exists) {
      res.status(400).json({ error: 'Selfie file not found in storage' });
      return;
    }

    // Use transaction to atomically verify ownership + update
    await db.runTransaction(async (txn) => {
      const docRef = db.collection('checkIns').doc(checkInId);
      const doc = await txn.get(docRef);

      if (!doc.exists || doc.data()?.seniorId !== req.uid) {
        throw new Error('NOT_AUTHORIZED');
      }

      txn.update(docRef, { selfiePath, hasSelfie: true });
    });

    res.json({ message: 'Selfie confirmed' });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg === 'NOT_AUTHORIZED') {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }
    logger.error('Confirm selfie error', { error: String(err) });
    res.status(500).json({ error: 'Failed to confirm selfie' });
  }
});
