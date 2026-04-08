import { db } from '../config/firebase';
import { nowInTimezone, todayInTimezone } from '../config/timezone';
import { AlertService, AlertContact } from '../services/AlertService';
import { logger } from '../lib/logger';

export async function missedCheckInJob(): Promise<{ processed: number; alerts: number }> {
  let processed = 0;
  let alertCount = 0;

  // Get all senior settings where alert hasn't been sent today
  const settingsSnap = await db
    .collection('seniorSettings')
    .where('alertSentToday', '==', false)
    .get();

  for (const settingsDoc of settingsSnap.docs) {
    // Per-senior error boundary — one failure doesn't abort the whole job
    try {
      const seniorId = settingsDoc.id;
      const settings = settingsDoc.data();

      // Get senior's timezone
      const userDoc = await db.collection('users').doc(seniorId).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data()!;
      const timezone = userData.timezone || 'America/New_York';
      const seniorName = userData.fullName || 'Your loved one';

      // Use dayjs for reliable timezone conversion
      const nowTz = nowInTimezone(timezone);
      const [endH, endM] = settings.windowEnd.split(':').map(Number);
      const endToday = nowTz.hour(endH).minute(endM).second(0).millisecond(0);

      if (nowTz.isBefore(endToday) || nowTz.isSame(endToday)) continue; // Still within window

      // Check for existing check-in today (using timezone-correct date)
      const today = todayInTimezone(timezone);
      const checkInSnap = await db
        .collection('checkIns')
        .where('seniorId', '==', seniorId)
        .where('checkInDate', '==', today)
        .limit(1)
        .get();

      if (!checkInSnap.empty) continue; // Already checked in

      processed++;

      // Create a missed check-in record
      const checkInRef = await db.collection('checkIns').add({
        seniorId,
        checkInDate: today,
        checkedInAt: null,
        status: 'missed',
        selfiePath: null,
      });

      // Get contacts to alert
      const contactsSnap = await db
        .collection('contacts')
        .where('seniorId', '==', seniorId)
        .where('alertOnMissed', '==', true)
        .get();

      const isPremium =
        userData.entitlements?.includes('premium') ||
        userData.entitlements?.includes('family');

      // Use batch write for alert logs
      const batch = db.batch();

      for (const contactDoc of contactsSnap.docs) {
        const contact = contactDoc.data();
        const alertContact: AlertContact = {
          contactId: contactDoc.id,
          fullName: contact.fullName,
          email: contact.email,
          phone: contact.phone,
          emailOptedOut: contact.emailOptedOut,
          smsOptedOut: contact.smsOptedOut,
        };

        // Send email alert (free tier)
        const emailResult = await AlertService.sendMissedCheckInEmail(alertContact, seniorName);
        const emailAlertRef = db.collection('alertLog').doc();
        batch.set(emailAlertRef, {
          checkInId: checkInRef.id,
          seniorId,
          contactId: contactDoc.id,
          sentAt: new Date(),
          channel: 'email',
          status: emailResult.status,
          messageId: emailResult.messageId || null,
        });
        if (emailResult.status === 'sent') alertCount++;

        // Send SMS alert (premium only)
        if (isPremium && contact.phone) {
          const smsResult = await AlertService.sendMissedCheckInSMS(alertContact, seniorName);
          const smsAlertRef = db.collection('alertLog').doc();
          batch.set(smsAlertRef, {
            checkInId: checkInRef.id,
            seniorId,
            contactId: contactDoc.id,
            sentAt: new Date(),
            channel: 'sms',
            status: smsResult.status,
            messageId: smsResult.messageId || null,
          });
          if (smsResult.status === 'sent') alertCount++;
        }
      }

      // Mark alert as sent for today + commit all alert logs atomically
      batch.update(settingsDoc.ref, { alertSentToday: true });
      await batch.commit();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('missedCheckInJob: error processing senior', { seniorId: settingsDoc.id, error: msg });
      // Continue processing remaining seniors
    }
  }

  logger.info('missedCheckInJob complete', { processed, alerts: alertCount });
  return { processed, alerts: alertCount };
}
