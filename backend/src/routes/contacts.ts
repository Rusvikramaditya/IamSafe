import { Router } from 'express';
import { db } from '../config/firebase';
import { authMiddleware, AuthRequest } from '../middleware/authMiddleware';
import { AlertService } from '../services/AlertService';

export const contactRoutes = Router();

contactRoutes.use(authMiddleware);

// List contacts for the authenticated senior
contactRoutes.get('/', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const snap = await db
      .collection('contacts')
      .where('seniorId', '==', seniorId)
      .get();

    const contacts = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    res.json({ contacts });
  } catch (err: any) {
    console.error('List contacts error:', err);
    res.status(500).json({ error: 'Failed to list contacts' });
  }
});

// Add a contact
contactRoutes.post('/', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const { fullName, phone, email, relationship } = req.body;

    if (!fullName || !email) {
      res.status(400).json({ error: 'fullName and email are required' });
      return;
    }

    // Free tier: max 1 contact. Check entitlements.
    const userDoc = await db.collection('users').doc(seniorId).get();
    const entitlements: string[] = userDoc.data()?.entitlements || [];
    const isPremium = entitlements.includes('premium') || entitlements.includes('family');

    if (!isPremium) {
      const existingSnap = await db
        .collection('contacts')
        .where('seniorId', '==', seniorId)
        .get();

      if (existingSnap.size >= 1) {
        res.status(403).json({ error: 'Free tier allows 1 contact. Upgrade to add more.' });
        return;
      }
    }

    const ref = await db.collection('contacts').add({
      seniorId,
      fullName,
      phone: phone || null,
      email,
      relationship: relationship || null,
      alertOnMissed: true,
      emailOptedOut: false,
      smsOptedOut: false,
    });

    res.status(201).json({ message: 'Contact added', contactId: ref.id });
  } catch (err: any) {
    console.error('Add contact error:', err);
    res.status(500).json({ error: 'Failed to add contact' });
  }
});

// Update a contact
contactRoutes.put('/:id', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const id = req.params.id as string;
    const doc = await db.collection('contacts').doc(id).get();

    if (!doc.exists || doc.data()?.seniorId !== seniorId) {
      res.status(404).json({ error: 'Contact not found' });
      return;
    }

    const allowed = ['fullName', 'phone', 'email', 'relationship', 'alertOnMissed'];
    const updates: Record<string, any> = {};
    for (const key of allowed) {
      if (req.body[key] !== undefined) updates[key] = req.body[key];
    }

    await db.collection('contacts').doc(id).update(updates);
    res.json({ message: 'Contact updated' });
  } catch (err: any) {
    console.error('Update contact error:', err);
    res.status(500).json({ error: 'Failed to update contact' });
  }
});

// Delete a contact
contactRoutes.delete('/:id', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const id = req.params.id as string;
    const doc = await db.collection('contacts').doc(id).get();

    if (!doc.exists || doc.data()?.seniorId !== seniorId) {
      res.status(404).json({ error: 'Contact not found' });
      return;
    }

    await db.collection('contacts').doc(id).delete();
    res.json({ message: 'Contact deleted' });
  } catch (err: any) {
    console.error('Delete contact error:', err);
    res.status(500).json({ error: 'Failed to delete contact' });
  }
});

// Send test alert to a contact
contactRoutes.post('/:id/test-alert', async (req: AuthRequest, res) => {
  try {
    const seniorId = req.uid!;
    const id = req.params.id as string;
    const doc = await db.collection('contacts').doc(id).get();

    if (!doc.exists || doc.data()?.seniorId !== seniorId) {
      res.status(404).json({ error: 'Contact not found' });
      return;
    }

    const contact = doc.data()!;
    const userDoc = await db.collection('users').doc(seniorId).get();
    const seniorName = userDoc.data()?.fullName || 'Your loved one';

    const result = await AlertService.sendMissedCheckInEmail(
      {
        contactId: id,
        fullName: contact.fullName,
        email: contact.email,
        emailOptedOut: false,
        smsOptedOut: false,
      },
      seniorName
    );

    res.json({ message: 'Test alert sent', result });
  } catch (err: any) {
    console.error('Test alert error:', err);
    res.status(500).json({ error: 'Failed to send test alert' });
  }
});
