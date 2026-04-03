import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { authLimiter, generalLimiter } from '../middleware/rateLimiter';
import { isValidTimezone } from '../config/timezone';
import { v4 as uuidv4 } from 'uuid';

export const authRoutes = Router();

/** Basic email format check (not exhaustive, but prevents garbage). */
function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** E.164 phone format check. */
function isValidPhone(phone: string): boolean {
  return /^\+[1-9]\d{1,14}$/.test(phone);
}

// Get authenticated user's profile
authRoutes.get('/profile', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const uid = req.uid!;
    const userDoc = await db.collection('users').doc(uid).get();

    if (!userDoc.exists) {
      res.status(404).json({ error: 'User profile not found' });
      return;
    }

    const data = userDoc.data()!;
    res.json({
      uid,
      fullName: data.fullName,
      email: data.email,
      phone: data.phone,
      role: data.role,
      timezone: data.timezone,
      entitlements: data.entitlements || [],
      createdAt: data.createdAt,
    });
  } catch (err: unknown) {
    console.error('Get profile error:', err);
    res.status(500).json({ error: 'Failed to get profile' });
  }
});

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

    if (!isValidEmail(email)) {
      res.status(400).json({ error: 'Invalid email format' });
      return;
    }

    if (phone && !isValidPhone(phone)) {
      res.status(400).json({ error: 'Phone must be in E.164 format (e.g. +12025551234)' });
      return;
    }

    if (timezone && !isValidTimezone(timezone)) {
      res.status(400).json({ error: 'Invalid timezone. Use IANA format (e.g. America/New_York)' });
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
        reminderSentToday: false,
        lastAlertReset: new Date().toISOString().split('T')[0],
      });
    }

    res.status(201).json({ message: 'User registered', uid });
  } catch (err: unknown) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Get linked seniors (for caregiver)
authRoutes.get('/linked-seniors', authMiddleware, async (req: AuthRequest, res) => {
  try {
    const caregiverId = req.uid!;

    const linksSnap = await db
      .collection('seniorCaregiverLinks')
      .where('caregiverId', '==', caregiverId)
      .where('acceptedAt', '!=', null)
      .get();

    const seniors: Array<{ seniorId: string; fullName: string; linkedAt: string }> = [];

    for (const linkDoc of linksSnap.docs) {
      const linkData = linkDoc.data();
      const seniorDoc = await db.collection('users').doc(linkData.seniorId).get();
      seniors.push({
        seniorId: linkData.seniorId,
        fullName: seniorDoc.exists ? seniorDoc.data()?.fullName || 'Unknown' : 'Unknown',
        linkedAt: linkData.acceptedAt?.toDate?.()?.toISOString?.() || linkData.acceptedAt || '',
      });
    }

    res.json({ seniors });
  } catch (err: unknown) {
    console.error('Get linked seniors error:', err);
    res.status(500).json({ error: 'Failed to get linked seniors' });
  }
});

// Link caregiver to senior via invite code
authRoutes.post('/link-senior', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
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

    // Fetch senior name for the response
    const seniorDoc = await db.collection('users').doc(linkData.seniorId).get();
    const seniorName = seniorDoc.exists ? seniorDoc.data()?.fullName : null;

    res.json({ message: 'Linked to senior', seniorId: linkData.seniorId, seniorName });
  } catch (err: unknown) {
    console.error('Link senior error:', err);
    res.status(500).json({ error: 'Linking failed' });
  }
});

// Generate invite code (senior only)
authRoutes.post('/generate-invite', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;

    if (req.userRole !== 'senior') {
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
  } catch (err: unknown) {
    console.error('Generate invite error:', err);
    res.status(500).json({ error: 'Failed to generate invite' });
  }
});
