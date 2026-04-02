import { Router } from 'express';
import { db, storage } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { checkInLimiter } from '../middleware/rateLimiter';

export const checkInRoutes = Router();

checkInRoutes.use(authMiddleware);

// Submit a check-in
checkInRoutes.post('/', checkInLimiter, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const now = new Date();
    const checkInDate = now.toISOString().split('T')[0]; // YYYY-MM-DD

    // Verify user is a senior
    const userDoc = await db.collection('users').doc(seniorId).get();
    if (!userDoc.exists || userDoc.data()?.role !== 'senior') {
      res.status(403).json({ error: 'Only seniors can check in' });
      return;
    }

    // Check for existing check-in today
    const existingSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('checkInDate', '==', checkInDate)
      .limit(1)
      .get();

    if (!existingSnap.empty) {
      const existing = existingSnap.docs[0];
      res.json({
        message: 'Already checked in today',
        checkIn: { id: existing.id, ...existing.data() },
      });
      return;
    }

    // Determine status based on check-in window
    const settingsDoc = await db.collection('seniorSettings').doc(seniorId).get();
    const settings = settingsDoc.data();
    let status: 'on_time' | 'late' = 'on_time';

    if (settings) {
      const [endH, endM] = settings.windowEnd.split(':').map(Number);
      const userTz = userDoc.data()?.timezone || 'America/New_York';
      const nowInTz = new Date(now.toLocaleString('en-US', { timeZone: userTz }));
      const endToday = new Date(nowInTz);
      endToday.setHours(endH, endM, 0, 0);

      if (nowInTz > endToday) {
        status = 'late';
      }
    }

    const checkInRef = await db.collection('checkIns').add({
      seniorId,
      checkInDate,
      checkedInAt: now,
      status,
      selfiePath: null,
    });

    res.status(201).json({
      message: 'Check-in recorded',
      checkIn: { id: checkInRef.id, seniorId, checkInDate, checkedInAt: now, status },
    });
  } catch (err: any) {
    console.error('Check-in error:', err);
    res.status(500).json({ error: 'Check-in failed' });
  }
});

// Get today's check-in
checkInRoutes.get('/today', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const today = new Date().toISOString().split('T')[0];

    const snap = await db
      .collection('checkIns')
      .where('seniorId', '==', uid)
      .where('checkInDate', '==', today)
      .limit(1)
      .get();

    if (snap.empty) {
      res.json({ checkedIn: false, checkIn: null });
      return;
    }

    res.json({ checkedIn: true, checkIn: { id: snap.docs[0].id, ...snap.docs[0].data() } });
  } catch (err: any) {
    console.error('Get today check-in error:', err);
    res.status(500).json({ error: 'Failed to get check-in status' });
  }
});

// Get check-in history
checkInRoutes.get('/history', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;

    // Free tier: max 7 days. Premium/family: up to 90 days.
    const userDoc = await db.collection('users').doc(uid).get();
    const entitlements: string[] = userDoc.data()?.entitlements || [];
    const isPremium = entitlements.includes('premium') || entitlements.includes('family');
    const maxDays = isPremium ? 90 : 7;
    const limit = Math.min(parseInt(req.query.limit as string) || maxDays, maxDays);

    const snap = await db
      .collection('checkIns')
      .where('seniorId', '==', uid)
      .orderBy('checkInDate', 'desc')
      .limit(limit)
      .get();

    const checkIns = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ checkIns, maxDays });
  } catch (err: any) {
    console.error('Get history error:', err);
    res.status(500).json({ error: 'Failed to get history' });
  }
});

// Get single check-in with signed selfie URL
checkInRoutes.get('/:id', async (req: AuthRequest, res) => {
  try {
    const id = req.params.id as string;
    const doc = await db.collection('checkIns').doc(id).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Check-in not found' });
      return;
    }

    const data = doc.data()!;

    // Only the senior or their linked caregiver can view
    const uid = req.uid!;
    if (data.seniorId !== uid) {
      const linkSnap = await db
        .collection('seniorCaregiverLinks')
        .where('seniorId', '==', data.seniorId)
        .where('caregiverId', '==', uid)
        .limit(1)
        .get();

      if (linkSnap.empty) {
        res.status(403).json({ error: 'Not authorized to view this check-in' });
        return;
      }
    }

    let selfieUrl: string | null = null;
    if (data.selfiePath) {
      // Selfie history is premium-only. Today's selfie is always viewable.
      const today = new Date().toISOString().split('T')[0];
      const isToday = data.checkInDate === today;

      if (isToday) {
        const [url] = await storage
          .bucket()
          .file(data.selfiePath)
          .getSignedUrl({
            action: 'read',
            expires: Date.now() + 60 * 60 * 1000, // 1 hour
          });
        selfieUrl = url;
      } else {
        // Check entitlements — use the senior's entitlements
        const seniorDoc = await db.collection('users').doc(data.seniorId).get();
        const entitlements: string[] = seniorDoc.data()?.entitlements || [];
        const isPremium = entitlements.includes('premium') || entitlements.includes('family');

        if (isPremium) {
          const [url] = await storage
            .bucket()
            .file(data.selfiePath)
            .getSignedUrl({
              action: 'read',
              expires: Date.now() + 60 * 60 * 1000, // 1 hour
            });
          selfieUrl = url;
        }
      }
    }

    const hasSelfie = !!data.selfiePath;
    res.json({ checkIn: { id: doc.id, ...data, selfieUrl, hasSelfie } });
  } catch (err: any) {
    console.error('Get check-in error:', err);
    res.status(500).json({ error: 'Failed to get check-in' });
  }
});

// Generate presigned upload URL for selfie
checkInRoutes.post('/selfie-url', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const { checkInId } = req.body;

    if (!checkInId) {
      res.status(400).json({ error: 'checkInId is required' });
      return;
    }

    const checkInDoc = await db.collection('checkIns').doc(checkInId).get();
    if (!checkInDoc.exists || checkInDoc.data()?.seniorId !== seniorId) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const filePath = `selfies/${seniorId}/${checkInId}.jpg`;
    const [url] = await storage
      .bucket()
      .file(filePath)
      .getSignedUrl({
        action: 'write',
        expires: Date.now() + 15 * 60 * 1000, // 15 min
        contentType: 'image/jpeg',
      });

    // Update check-in with selfie path
    await db.collection('checkIns').doc(checkInId).update({ selfiePath: filePath });

    res.json({ uploadUrl: url, filePath });
  } catch (err: any) {
    console.error('Selfie URL error:', err);
    res.status(500).json({ error: 'Failed to generate upload URL' });
  }
});
