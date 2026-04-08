import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { generalLimiter } from '../middleware/rateLimiter';
import { logger } from '../lib/logger';

export const settingsRoutes = Router();

/** Validate HH:MM time format with valid ranges. */
function isValidTime(time: string): boolean {
  const match = time.match(/^(\d{2}):(\d{2})$/);
  if (!match) return false;
  const h = parseInt(match[1], 10);
  const m = parseInt(match[2], 10);
  return h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

// Get settings
settingsRoutes.get('/', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const doc = await db.collection('seniorSettings').doc(req.uid!).get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Settings not found' });
      return;
    }
    res.json({ settings: doc.data() });
  } catch (err: unknown) {
    logger.error('Get settings error', { error: String(err) });
    res.status(500).json({ error: 'Failed to get settings' });
  }
});

// Update settings
settingsRoutes.put('/', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const allowed = [
      'windowStart',
      'windowEnd',
      'selfieEnabled',
      'reminderMinutes',
      'fcmToken', // Fixed: was missing from allowed list
    ];
    const updates: Record<string, unknown> = {};

    for (const key of allowed) {
      if (req.body[key] !== undefined) {
        updates[key] = req.body[key];
      }
    }

    // Validate time fields
    if (updates.windowStart && !isValidTime(updates.windowStart as string)) {
      res.status(400).json({ error: 'Invalid windowStart format. Use HH:MM (00:00–23:59)' });
      return;
    }
    if (updates.windowEnd && !isValidTime(updates.windowEnd as string)) {
      res.status(400).json({ error: 'Invalid windowEnd format. Use HH:MM (00:00–23:59)' });
      return;
    }

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: 'No valid fields to update' });
      return;
    }

    // If fcmToken is being updated, store it on the user doc (not settings)
    if (updates.fcmToken !== undefined) {
      await db.collection('users').doc(req.uid!).update({
        fcmToken: updates.fcmToken,
      });
      delete updates.fcmToken;
    }

    if (Object.keys(updates).length > 0) {
      await db.collection('seniorSettings').doc(req.uid!).update(updates);
    }

    res.json({ message: 'Settings updated' });
  } catch (err: unknown) {
    logger.error('Update settings error', { error: String(err) });
    res.status(500).json({ error: 'Failed to update settings' });
  }
});
