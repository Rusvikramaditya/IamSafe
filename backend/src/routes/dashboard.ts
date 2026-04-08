import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { generalLimiter } from '../middleware/rateLimiter';
import { todayInTimezone } from '../config/timezone';
import { logger } from '../lib/logger';

export const dashboardRoutes = Router();

/**
 * Middleware: verify the authenticated user has access to the given senior's data.
 * The user must be the senior themselves OR a linked caregiver.
 */
async function verifySeniorAccess(
  req: AuthRequest,
  seniorId: string
): Promise<boolean> {
  if (req.uid === seniorId) return true;

  const linkSnap = await db
    .collection('seniorCaregiverLinks')
    .where('seniorId', '==', seniorId)
    .where('caregiverId', '==', req.uid)
    .where('acceptedAt', '!=', null)
    .limit(1)
    .get();

  return !linkSnap.empty;
}

// 30-day summary
dashboardRoutes.get('/:seniorId/summary', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.params.seniorId as string;

    if (!(await verifySeniorAccess(req, seniorId))) {
      res.status(403).json({ error: 'Not authorized to view this senior' });
      return;
    }

    // Get senior's timezone for correct date calculation
    const userDoc = await db.collection('users').doc(seniorId).get();
    const timezone = userDoc.data()?.timezone || 'America/New_York';

    const checkInsSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .orderBy('checkInDate', 'desc')
      .limit(30)
      .get();

    const days = checkInsSnap.docs.map((doc) => {
      const data = doc.data();
      return {
        date: data.checkInDate,
        status: data.status,
        checkedInAt: data.checkedInAt,
        checkInId: doc.id,
        hasSelfie: data.hasSelfie || false,
      };
    });

    res.json({ days, timezone });
  } catch (err: unknown) {
    logger.error('Dashboard summary error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get dashboard summary' });
  }
});

// Streak
dashboardRoutes.get('/:seniorId/streak', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.params.seniorId as string;

    if (!(await verifySeniorAccess(req, seniorId))) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    // Get senior's timezone
    const userDoc = await db.collection('users').doc(seniorId).get();
    const timezone = userDoc.data()?.timezone || 'America/New_York';

    const checkInsSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('status', 'in', ['on_time', 'late'])
      .orderBy('checkInDate', 'desc')
      .limit(90)
      .get();

    if (checkInsSnap.empty) {
      res.json({ streak: 0 });
      return;
    }

    // Calculate streak using timezone-correct dates
    const { dayjs } = await import('../config/timezone');
    let streak = 0;
    let expectedDate = dayjs().tz(timezone).startOf('day');

    for (const doc of checkInsSnap.docs) {
      const data = doc.data();
      const checkInDate = dayjs(data.checkInDate);

      if (checkInDate.isSame(expectedDate, 'day')) {
        streak++;
        expectedDate = expectedDate.subtract(1, 'day');
      } else {
        break;
      }
    }

    res.json({ streak });
  } catch (err: unknown) {
    logger.error('Streak error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get streak' });
  }
});

// Alert history
dashboardRoutes.get('/:seniorId/alerts', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.params.seniorId as string;

    if (!(await verifySeniorAccess(req, seniorId))) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const alertsSnap = await db
      .collection('alertLog')
      .where('seniorId', '==', seniorId)
      .orderBy('sentAt', 'desc')
      .limit(30)
      .get();

    const alerts = alertsSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.json({ alerts });
  } catch (err: unknown) {
    logger.error('Alert history error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get alert history' });
  }
});
