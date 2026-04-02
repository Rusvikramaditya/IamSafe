import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';

export const dashboardRoutes = Router();

dashboardRoutes.use(authMiddleware);

// 30-day summary for a senior
dashboardRoutes.get('/:seniorId/summary', async (req: AuthRequest, res) => {
  try {
    const caregiverId = req.uid!;
    const { seniorId } = req.params;

    // Verify caregiver is linked
    const linkSnap = await db
      .collection('seniorCaregiverLinks')
      .where('seniorId', '==', seniorId)
      .where('caregiverId', '==', caregiverId)
      .limit(1)
      .get();

    // Allow senior to view their own dashboard too
    if (linkSnap.empty && caregiverId !== seniorId) {
      res.status(403).json({ error: 'Not authorized to view this senior' });
      return;
    }

    // Free tier: 7-day summary. Premium/family: 30-day summary.
    const seniorDoc = await db.collection('users').doc(seniorId as string).get();
    const entitlements: string[] = seniorDoc.data()?.entitlements || [];
    const isPremium = entitlements.includes('premium') || entitlements.includes('family');
    const daysBack = isPremium ? 30 : 7;

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - daysBack);
    const startDate = cutoff.toISOString().split('T')[0];

    const snap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('checkInDate', '>=', startDate)
      .orderBy('checkInDate', 'desc')
      .get();

    const days = snap.docs.map((doc) => ({
      date: doc.data().checkInDate,
      status: doc.data().status,
      checkedInAt: doc.data().checkedInAt,
    }));

    res.json({ seniorId, days, daysBack });
  } catch (err: any) {
    console.error('Dashboard summary error:', err);
    res.status(500).json({ error: 'Failed to get summary' });
  }
});

// Streak
dashboardRoutes.get('/:seniorId/streak', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const { seniorId } = req.params;

    // Quick auth check
    if (uid !== seniorId) {
      const linkSnap = await db
        .collection('seniorCaregiverLinks')
        .where('seniorId', '==', seniorId)
        .where('caregiverId', '==', uid)
        .limit(1)
        .get();
      if (linkSnap.empty) {
        res.status(403).json({ error: 'Not authorized' });
        return;
      }
    }

    const snap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('status', 'in', ['on_time', 'late'])
      .orderBy('checkInDate', 'desc')
      .limit(90)
      .get();

    let streak = 0;
    const today = new Date();

    for (const doc of snap.docs) {
      const expected = new Date(today);
      expected.setDate(expected.getDate() - streak);
      const expectedDate = expected.toISOString().split('T')[0];

      if (doc.data().checkInDate === expectedDate) {
        streak++;
      } else {
        break;
      }
    }

    res.json({ seniorId, streak });
  } catch (err: any) {
    console.error('Streak error:', err);
    res.status(500).json({ error: 'Failed to get streak' });
  }
});

// Alert history
dashboardRoutes.get('/:seniorId/alerts', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const { seniorId } = req.params;

    if (uid !== seniorId) {
      const linkSnap = await db
        .collection('seniorCaregiverLinks')
        .where('seniorId', '==', seniorId)
        .where('caregiverId', '==', uid)
        .limit(1)
        .get();
      if (linkSnap.empty) {
        res.status(403).json({ error: 'Not authorized' });
        return;
      }
    }

    const snap = await db
      .collection('alertLog')
      .where('seniorId', '==', seniorId)
      .orderBy('sentAt', 'desc')
      .limit(50)
      .get();

    const alerts = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ alerts });
  } catch (err: any) {
    console.error('Alert history error:', err);
    res.status(500).json({ error: 'Failed to get alerts' });
  }
});
