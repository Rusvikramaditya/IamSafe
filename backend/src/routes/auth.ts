import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { authLimiter } from '../middleware/rateLimiter';
import { v4 as uuidv4 } from 'uuid';

export const authRoutes = Router();

// Register user profile after Firebase Auth signup
authRoutes.post('/register', authLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { fullName, email, phone, role, timezone } = req.body;
    const uid = req.uid!;

    if (!fullName || !email || !role) {
      res.status(400).json({ error: 'fullName, email, and role are required' });
      return;
    }

    if (role !== 'senior' && role !== 'caregiver') {
      res.status(400).json({ error: 'role must be "senior" or "caregiver"' });
      return;
    }

    const userDoc = await db.collection('users').doc(uid).get();
    if (userDoc.exists) {
      res.status(409).json({ error: 'User already registered' });
      return;
    }

    await db.collection('users').doc(uid).set({
      email,
      phone: phone || null,
      fullName,
      role,
      fcmToken: null,
      timezone: timezone || 'America/New_York',
      createdAt: new Date(),
      entitlements: [],
    });

    // If senior, create default settings
    if (role === 'senior') {
      await db.collection('seniorSettings').doc(uid).set({
        windowStart: '08:00',
        windowEnd: '10:00',
        selfieEnabled: false,
        reminderMinutes: 30,
        alertSentToday: false,
        lastAlertReset: new Date().toISOString().split('T')[0],
      });
    }

    res.status(201).json({ message: 'User registered', uid });
  } catch (err: any) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Link caregiver to senior via invite code
authRoutes.post('/link-senior', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { inviteCode } = req.body;
    const caregiverId = req.uid!;

    if (!inviteCode) {
      res.status(400).json({ error: 'inviteCode is required' });
      return;
    }

    const linksSnap = await db
      .collection('seniorCaregiverLinks')
      .where('inviteCode', '==', inviteCode)
      .where('acceptedAt', '==', null)
      .limit(1)
      .get();

    if (linksSnap.empty) {
      res.status(404).json({ error: 'Invalid or expired invite code' });
      return;
    }

    const linkDoc = linksSnap.docs[0];
    const linkData = linkDoc.data();

    if (linkData.inviteExpires && new Date(linkData.inviteExpires) < new Date()) {
      res.status(410).json({ error: 'Invite code has expired' });
      return;
    }

    await linkDoc.ref.update({
      caregiverId,
      acceptedAt: new Date(),
    });

    res.json({ message: 'Linked to senior', seniorId: linkData.seniorId });
  } catch (err: any) {
    console.error('Link senior error:', err);
    res.status(500).json({ error: 'Linking failed' });
  }
});

// Generate invite code (senior only)
authRoutes.post('/generate-invite', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;

    const userDoc = await db.collection('users').doc(seniorId).get();
    if (!userDoc.exists || userDoc.data()?.role !== 'senior') {
      res.status(403).json({ error: 'Only seniors can generate invite codes' });
      return;
    }

    const inviteCode = uuidv4().substring(0, 8).toUpperCase();
    const inviteExpires = new Date();
    inviteExpires.setDate(inviteExpires.getDate() + 7);

    const linkRef = await db.collection('seniorCaregiverLinks').add({
      seniorId,
      caregiverId: null,
      inviteCode,
      inviteExpires: inviteExpires.toISOString(),
      acceptedAt: null,
    });

    res.status(201).json({ inviteCode, linkId: linkRef.id, expiresAt: inviteExpires.toISOString() });
  } catch (err: any) {
    console.error('Generate invite error:', err);
    res.status(500).json({ error: 'Failed to generate invite' });
  }
});
