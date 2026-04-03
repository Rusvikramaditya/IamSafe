import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { generalLimiter } from '../middleware/rateLimiter';
import { AlertService, AlertContact } from '../services/AlertService';

export const contactRoutes = Router();

/** Basic email format check. */
function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

// Get contacts for the authenticated senior
contactRoutes.get('/', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const contactsSnap = await db
      .collection('contacts')
      .where('seniorId', '==', req.uid)
      .get();

    const contacts = contactsSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));

    res.json({ contacts });
  } catch (err: unknown) {
    console.error('Get contacts error:', err);
    res.status(500).json({ error: 'Failed to get contacts' });
  }
});

// Add a new contact
contactRoutes.post('/', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const { fullName, email, phone, relationship } = req.body;
    const seniorId = req.uid!;

    if (!fullName || !email) {
      res.status(400).json({ error: 'fullName and email are required' });
      return;
    }

    if (!isValidEmail(email)) {
      res.status(400).json({ error: 'Invalid email format' });
      return;
    }

    // Check contact limit for free tier
    const userDoc = await db.collection('users').doc(seniorId).get();
    const entitlements = userDoc.data()?.entitlements || [];
    const isPremium = entitlements.includes('premium') || entitlements.includes('family');

    const existingSnap = await db
      .collection('contacts')
      .where('seniorId', '==', seniorId)
      .get();

    if (!isPremium && existingSnap.size >= 1) {
      res.status(403).json({ error: 'Free tier allows 1 contact. Upgrade for more.' });
      return;
    }

    if (isPremium && existingSnap.size >= 5) {
      res.status(403).json({ error: 'Maximum 5 contacts allowed.' });
      return;
    }

    const contactRef = await db.collection('contacts').add({
      seniorId,
      fullName,
      email,
      phone: phone || null,
      relationship: relationship || 'Family',
      alertOnMissed: true,
      emailOptedOut: false,
      smsOptedOut: false,
      createdAt: new Date(),
    });

    res.status(201).json({
      message: 'Contact added',
      contact: { id: contactRef.id, fullName, email },
    });
  } catch (err: unknown) {
    console.error('Add contact error:', err);
    res.status(500).json({ error: 'Failed to add contact' });
  }
});

// Delete a contact
contactRoutes.delete('/:contactId', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const contactId = req.params.contactId as string;
    const doc = await db.collection('contacts').doc(contactId).get();

    if (!doc.exists || doc.data()?.seniorId !== req.uid) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    await doc.ref.delete();
    res.json({ message: 'Contact deleted' });
  } catch (err: unknown) {
    console.error('Delete contact error:', err);
    res.status(500).json({ error: 'Failed to delete contact' });
  }
});

// Test alert — send a test email to a contact
contactRoutes.post('/:contactId/test-alert', generalLimiter, authMiddleware, async (req: AuthRequest, res) => {
  try {
    const contactId = req.params.contactId as string;
    const doc = await db.collection('contacts').doc(contactId).get();

    if (!doc.exists || doc.data()?.seniorId !== req.uid) {
      res.status(403).json({ error: 'Not authorized' });
      return;
    }

    const userDoc = await db.collection('users').doc(req.uid!).get();
    const seniorName = userDoc.data()?.fullName || 'Your loved one';
    const contact = doc.data()!;

    const alertContact: AlertContact = {
      contactId,
      fullName: contact.fullName,
      email: contact.email,
      phone: contact.phone,
      emailOptedOut: contact.emailOptedOut,
      smsOptedOut: contact.smsOptedOut,
    };

    const result = await AlertService.sendMissedCheckInEmail(alertContact, seniorName);
    res.json({ message: 'Test alert sent', result });
  } catch (err: unknown) {
    console.error('Test alert error:', err);
    res.status(500).json({ error: 'Failed to send test alert' });
  }
});

// Public unsubscribe endpoint — no auth required (linked from email)
contactRoutes.get('/:contactId/unsubscribe', async (req, res) => {
  try {
    const contactId = req.params.contactId as string;
    const doc = await db.collection('contacts').doc(contactId).get();

    if (!doc.exists) {
      res.status(404).send('<h1>Contact not found</h1>');
      return;
    }

    await doc.ref.update({ emailOptedOut: true });
    res
      .status(200)
      .set('Content-Type', 'text/html')
      .send(`
        <html>
          <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; text-align: center;">
            <h1>Unsubscribed</h1>
            <p>You will no longer receive email alerts from IamSafe.</p>
            <p style="color: #888; margin-top: 20px;">If this was a mistake, contact the senior who added you.</p>
          </body>
        </html>
      `);
  } catch (err: unknown) {
    console.error('Unsubscribe error:', err);
    res.status(500).send('<h1>Something went wrong</h1>');
  }
});
