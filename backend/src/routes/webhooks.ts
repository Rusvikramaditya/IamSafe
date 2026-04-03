import { Router, Request, Response } from 'express';
import twilio from 'twilio';
import crypto from 'crypto';
import { db } from '../config/firebase';
import { webhookLimiter } from '../middleware/rateLimiter';

export const webhookRoutes = Router();

// ─── Signature Verification Helpers ────────────────────────────────

/** Verify RevenueCat webhook signature. */
function verifyRevenueCatSignature(req: Request): boolean {
  const secret = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!secret) {
    console.warn('REVENUECAT_WEBHOOK_SECRET not set — skipping signature check (unsafe in production)');
    return process.env.NODE_ENV !== 'production';
  }
  const authHeader = req.headers['authorization'];
  return authHeader === `Bearer ${secret}`;
}

/** Verify Twilio webhook signature. */
function verifyTwilioSignature(req: Request): boolean {
  const twilioSignature = req.headers['x-twilio-signature'] as string;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  if (!twilioSignature || !authToken) {
    console.warn('Twilio signature or auth token missing');
    return process.env.NODE_ENV !== 'production';
  }
  const url = `${process.env.PUBLIC_API_URL || ''}/api/v1/webhooks/twilio`;
  return twilio.validateRequest(authToken, twilioSignature, url, req.body);
}

/** Verify Resend webhook signature via HMAC. */
function verifyResendSignature(req: Request): boolean {
  const secret = process.env.RESEND_WEBHOOK_SECRET;
  const signature = req.headers['resend-signature'] as string;
  if (!secret || !signature) {
    console.warn('Resend webhook secret or signature missing');
    return process.env.NODE_ENV !== 'production';
  }
  const rawBody = JSON.stringify(req.body);
  const hmac = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
  return crypto.timingSafeEqual(Buffer.from(hmac), Buffer.from(signature));
}

// Explicit product ID to entitlement mapping — no string matching
const PRODUCT_ENTITLEMENTS: Record<string, string> = {
  // Add your actual RevenueCat product IDs here
  'iamsafe_premium_monthly': 'premium',
  'iamsafe_premium_annual': 'premium',
  'iamsafe_family_monthly': 'family',
  'iamsafe_family_annual': 'family',
};

// ─── RevenueCat Webhook ────────────────────────────────────────────

webhookRoutes.post('/revenuecat', webhookLimiter, async (req: Request, res: Response) => {
  if (!verifyRevenueCatSignature(req)) {
    res.status(401).json({ error: 'Invalid signature' });
    return;
  }

  try {
    const event = req.body?.event;
    if (!event) {
      res.status(400).json({ error: 'Missing event' });
      return;
    }

    const appUserId = event.app_user_id;
    const productId = event.product_id;
    const eventType = event.type;

    if (!appUserId) {
      res.status(400).json({ error: 'Missing app_user_id' });
      return;
    }

    // Map product to entitlement
    const entitlement = PRODUCT_ENTITLEMENTS[productId];

    // Handle subscription events
    if (
      eventType === 'INITIAL_PURCHASE' ||
      eventType === 'RENEWAL' ||
      eventType === 'PRODUCT_CHANGE'
    ) {
      if (entitlement) {
        await db.collection('users').doc(appUserId).update({
          entitlements: [entitlement],
        });
      } else {
        console.warn(`Unknown product ID: ${productId}`);
      }
    } else if (
      eventType === 'CANCELLATION' ||
      eventType === 'EXPIRATION' ||
      eventType === 'BILLING_ISSUE'
    ) {
      await db.collection('users').doc(appUserId).update({
        entitlements: [],
      });
    }

    res.json({ received: true });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('RevenueCat webhook error:', msg);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

// ─── Twilio Webhook ─────────────────────────────────────────────────

webhookRoutes.post('/twilio', webhookLimiter, async (req: Request, res: Response) => {
  if (!verifyTwilioSignature(req)) {
    res.status(401).json({ error: 'Invalid signature' });
    return;
  }

  try {
    const { Body, From } = req.body;

    // Handle STOP/opt-out
    if (Body && Body.trim().toUpperCase() === 'STOP') {
      const contactsSnap = await db
        .collection('contacts')
        .where('phone', '==', From)
        .get();

      for (const doc of contactsSnap.docs) {
        await doc.ref.update({ smsOptedOut: true });
      }
    }

    res.set('Content-Type', 'text/xml').status(200).send('<Response></Response>');
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Twilio webhook error:', msg);
    res.set('Content-Type', 'text/xml').status(200).send('<Response></Response>');
  }
});

// ─── Resend Webhook ─────────────────────────────────────────────────

webhookRoutes.post('/resend', webhookLimiter, async (req: Request, res: Response) => {
  if (!verifyResendSignature(req)) {
    res.status(401).json({ error: 'Invalid signature' });
    return;
  }

  try {
    const { type, data } = req.body;

    if (type === 'email.bounced' || type === 'email.complained') {
      // Find contact by email and opt them out
      const email = data?.to?.[0];
      if (email) {
        const contactsSnap = await db
          .collection('contacts')
          .where('email', '==', email)
          .get();

        for (const doc of contactsSnap.docs) {
          await doc.ref.update({ emailOptedOut: true });
        }
      }
    }

    res.json({ received: true });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('Resend webhook error:', msg);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});
