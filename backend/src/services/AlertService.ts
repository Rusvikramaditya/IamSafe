import { Resend } from 'resend';
import twilio from 'twilio';

// Lazy-initialized clients to avoid module-level env var issues
let _resend: Resend | null = null;
let _twilioClient: ReturnType<typeof twilio> | null = null;

function getResend(): Resend {
  if (!_resend) {
    _resend = new Resend(process.env.RESEND_API_KEY);
  }
  return _resend;
}

function getTwilioClient(): ReturnType<typeof twilio> | null {
  if (_twilioClient === undefined || _twilioClient === null) {
    _twilioClient = process.env.TWILIO_ACCOUNT_SID
      ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
      : null;
  }
  return _twilioClient;
}

function getFromEmail(): string {
  return process.env.RESEND_FROM_EMAIL || 'alerts@iamsafe.app';
}

function getTwilioFromPhone(): string | undefined {
  return process.env.TWILIO_FROM_PHONE;
}

/** Escape HTML entities to prevent injection in email templates. */
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

export interface AlertContact {
  contactId: string;
  fullName: string;
  email: string;
  phone?: string;
  emailOptedOut: boolean;
  smsOptedOut: boolean;
}

export interface AlertResult {
  contactId: string;
  channel: 'email' | 'sms';
  status: 'sent' | 'failed' | 'skipped';
  messageId?: string;
  error?: string;
}

export class AlertService {
  static async sendMissedCheckInEmail(
    contact: AlertContact,
    seniorName: string
  ): Promise<AlertResult> {
    if (contact.emailOptedOut) {
      return { contactId: contact.contactId, channel: 'email', status: 'skipped' };
    }

    try {
      const safeSeniorName = escapeHtml(seniorName);
      const safeContactId = encodeURIComponent(contact.contactId);
      const backendBase = process.env.PUBLIC_API_URL || 'https://api.iamsafe.app';
      const unsubscribeUrl = `${backendBase}/api/v1/contacts/${safeContactId}/unsubscribe`;

      const { data } = await getResend().emails.send({
        from: `IamSafe Alerts <${getFromEmail()}>`,
        to: contact.email,
        subject: `⚠️ ${safeSeniorName} missed their daily check-in`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #D32F2F;">Missed Check-In Alert</h2>
            <p style="font-size: 18px; color: #333;">
              <strong>${safeSeniorName}</strong> has not completed their daily safety check-in today.
            </p>
            <p style="font-size: 16px; color: #555;">
              This could mean they forgot, or it could indicate they need help.
              Please reach out to them when you can.
            </p>
            <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
            <p style="font-size: 12px; color: #999;">
              You're receiving this because you were added as a contact on IamSafe.
              <a href="${unsubscribeUrl}">Unsubscribe from these alerts</a>
            </p>
          </div>
        `,
      });

      return {
        contactId: contact.contactId,
        channel: 'email',
        status: 'sent',
        messageId: data?.id,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        contactId: contact.contactId,
        channel: 'email',
        status: 'failed',
        error: message,
      };
    }
  }

  static async sendMissedCheckInSMS(
    contact: AlertContact,
    seniorName: string
  ): Promise<AlertResult> {
    if (contact.smsOptedOut || !contact.phone) {
      return { contactId: contact.contactId, channel: 'sms', status: 'skipped' };
    }

    const client = getTwilioClient();
    const fromPhone = getTwilioFromPhone();
    if (!client || !fromPhone) {
      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'failed',
        error: 'Twilio not configured',
      };
    }

    try {
      const message = await client.messages.create({
        body: `IamSafe Alert: ${seniorName} missed their daily check-in today. Please reach out to them. Reply STOP to opt out.`,
        from: fromPhone,
        to: contact.phone,
      });

      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'sent',
        messageId: message.sid,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'failed',
        error: message,
      };
    }
  }
}
