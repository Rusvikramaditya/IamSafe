import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';

export const settingsRoutes = Router();

settingsRoutes.use(authMiddleware);

// Get senior settings
settingsRoutes.get('/', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const doc = await db.collection('seniorSettings').doc(uid).get();

    if (!doc.exists) {
      res.status(404).json({ error: 'Settings not found' });
      return;
    }

    res.json({ settings: doc.data() });
  } catch (err: any) {
    console.error('Get settings error:', err);
    res.status(500).json({ error: 'Failed to get settings' });
  }
});

// Update senior settings
settingsRoutes.put('/', async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const allowed = ['windowStart', 'windowEnd', 'selfieEnabled', 'reminderMinutes'];
    const updates: Record<string, any> = {};

    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }

    if (Object.keys(updates).length === 0) {
      res.status(400).json({ error: 'No valid fields to update' });
      return;
    }

    // Validate time format
    for (const key of ['windowStart', 'windowEnd']) {
      if (updates[key] && !/^\d{2}:\d{2}$/.test(updates[key])) {
        res.status(400).json({ error: `${key} must be in HH:mm format` });
        return;
      }
    }

    await db.collection('seniorSettings').doc(uid).update(updates);
    res.json({ message: 'Settings updated' });
  } catch (err: any) {
    console.error('Update settings error:', err);
    res.status(500).json({ error: 'Failed to update settings' });
  }
});
