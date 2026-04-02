import { Router, Request, Response } from 'express';
import { db } from '../config/firebase';

export const webhookRoutes = Router();

// Twilio SMS delivery status + STOP opt-out
webhookRoutes.post('/twilio', async (req: Request, res: Response) => {
  try {
    const { MessageSid, MessageStatus, Body, From } = req.body;

    // Handle STOP opt-out
    if (Body && Body.trim().toUpperCase() === 'STOP') {
      const contactSnap = await db
        .collection('contacts')
        .where('phone', '==', From)
        .get();

      for (const doc of contactSnap.docs) {
        await doc.ref.update({ smsOptedOut: true });
      }
    }

    // Update alert log with delivery status
    if (MessageSid) {
      const alertSnap = await db
        .collection('alertLog')
        .where('messageId', '==', MessageSid)
        .limit(1)
        .get();

      if (!alertSnap.empty) {
        await alertSnap.docs[0].ref.update({ status: MessageStatus });
      }
    }

    res.status(200).send('<Response></Response>');
  } catch (err: any) {
    console.error('Twilio webhook error:', err);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

// Resend email delivery status
webhookRoutes.post('/resend', async (req: Request, res: Response) => {
  try {
    const { type, data } = req.body;

    if (data?.email_id) {
      const alertSnap = await db
        .collection('alertLog')
        .where('messageId', '==', data.email_id)
        .limit(1)
        .get();

      if (!alertSnap.empty) {
        await alertSnap.docs[0].ref.update({ status: type });
      }
    }

    res.json({ received: true });
  } catch (err: any) {
    console.error('Resend webhook error:', err);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

// RevenueCat subscription events
webhookRoutes.post('/revenuecat', async (req: Request, res: Response) => {
  try {
    const { event } = req.body;

    if (!event) {
      res.status(400).json({ error: 'Missing event' });
      return;
    }

    const appUserId = event.app_user_id;
    if (!appUserId) {
      res.status(400).json({ error: 'Missing app_user_id' });
      return;
    }

    const eventType = event.type;
    const productId: string = event.product_id || '';

    let entitlements: string[] = [];

    if (
      eventType === 'INITIAL_PURCHASE' ||
      eventType === 'RENEWAL' ||
      eventType === 'PRODUCT_CHANGE'
    ) {
      if (productId.includes('family')) {
        entitlements = ['premium', 'family'];
      } else if (productId.includes('premium')) {
        entitlements = ['premium'];
      }
    } else if (
      eventType === 'CANCELLATION' ||
      eventType === 'EXPIRATION'
    ) {
      entitlements = [];
    }

    await db.collection('users').doc(appUserId).update({ entitlements });

    res.json({ received: true, entitlements });
  } catch (err: any) {
    console.error('RevenueCat webhook error:', err);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});
