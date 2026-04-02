import { db } from '../config/firebase';
import { AlertService, AlertContact } from '../services/AlertService';

export async function missedCheckInJob(): Promise<{ processed: number; alerts: number }> {
  const now = new Date();
  let processed = 0;
  let alertCount = 0;

  // Get all senior settings where alert hasn't been sent today
  const settingsSnap = await db
    .collection('seniorSettings')
    .where('alertSentToday', '==', false)
    .get();

  for (const settingsDoc of settingsSnap.docs) {
    const seniorId = settingsDoc.id;
    const settings = settingsDoc.data();

    // Get senior's timezone
    const userDoc = await db.collection('users').doc(seniorId).get();
    if (!userDoc.exists) continue;

    const userData = userDoc.data()!;
    const timezone = userData.timezone || 'America/New_York';
    const seniorName = userData.fullName || 'Your loved one';

    // Check if current time is past their window end
    const nowInTz = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
    const [endH, endM] = settings.windowEnd.split(':').map(Number);
    const endToday = new Date(nowInTz);
    endToday.setHours(endH, endM, 0, 0);

    if (nowInTz <= endToday) continue; // Still within their window

    // Check for existing check-in today
    const today = nowInTz.toISOString().split('T')[0];
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
      await db.collection('alertLog').add({
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
        await db.collection('alertLog').add({
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

    // Mark alert as sent for today
    await settingsDoc.ref.update({ alertSentToday: true });
  }

  console.log(`missedCheckInJob: processed ${processed} seniors, sent ${alertCount} alerts`);
  return { processed, alerts: alertCount };
}
