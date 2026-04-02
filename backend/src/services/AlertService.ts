import { Resend } from 'resend';
import twilio from 'twilio';

const resend = new Resend(process.env.RESEND_API_KEY);
const fromEmail = process.env.RESEND_FROM_EMAIL || 'alerts@iamsafe.app';

const twilioClient = process.env.TWILIO_ACCOUNT_SID
  ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
  : null;
const twilioFromPhone = process.env.TWILIO_FROM_PHONE;

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
      const { data } = await resend.emails.send({
        from: `IamSafe Alerts <${fromEmail}>`,
        to: contact.email,
        subject: `⚠️ ${seniorName} missed their daily check-in`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #D32F2F;">Missed Check-In Alert</h2>
            <p style="font-size: 18px; color: #333;">
              <strong>${seniorName}</strong> has not completed their daily safety check-in today.
            </p>
            <p style="font-size: 16px; color: #555;">
              This could mean they forgot, or it could indicate they need help.
              Please reach out to them when you can.
            </p>
            <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
            <p style="font-size: 12px; color: #999;">
              You're receiving this because you were added as a contact on IamSafe.
              <a href="#">Unsubscribe from these alerts</a>
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
    } catch (err: any) {
      return {
        contactId: contact.contactId,
        channel: 'email',
        status: 'failed',
        error: err.message,
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

    if (!twilioClient || !twilioFromPhone) {
      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'failed',
        error: 'Twilio not configured',
      };
    }

    try {
      const message = await twilioClient.messages.create({
        body: `IamSafe Alert: ${seniorName} missed their daily check-in today. Please reach out to them. Reply STOP to opt out.`,
        from: twilioFromPhone,
        to: contact.phone,
      });

      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'sent',
        messageId: message.sid,
      };
    } catch (err: any) {
      return {
        contactId: contact.contactId,
        channel: 'sms',
        status: 'failed',
        error: err.message,
      };
    }
  }
}
