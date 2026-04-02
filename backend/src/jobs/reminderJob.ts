import { db, messaging } from '../config/firebase';

export async function reminderJob(): Promise<{ sent: number }> {
  const now = new Date();
  let sent = 0;

  const settingsSnap = await db.collection('seniorSettings').get();

  for (const settingsDoc of settingsSnap.docs) {
    const seniorId = settingsDoc.id;
    const settings = settingsDoc.data();

    const userDoc = await db.collection('users').doc(seniorId).get();
    if (!userDoc.exists) continue;

    const userData = userDoc.data()!;
    const timezone = userData.timezone || 'America/New_York';
    const fcmToken = userData.fcmToken;

    if (!fcmToken) continue;

    // Check if reminder window applies
    const nowInTz = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
    const [endH, endM] = settings.windowEnd.split(':').map(Number);
    const endToday = new Date(nowInTz);
    endToday.setHours(endH, endM, 0, 0);

    const reminderTime = new Date(endToday);
    reminderTime.setMinutes(reminderTime.getMinutes() - (settings.reminderMinutes || 30));

    // Send reminder if we're in the reminder window and before window end
    if (nowInTz < reminderTime || nowInTz >= endToday) continue;

    // Check if already checked in today
    const today = nowInTz.toISOString().split('T')[0];
    const checkInSnap = await db
      .collection('checkIns')
      .where('seniorId', '==', seniorId)
      .where('checkInDate', '==', today)
      .limit(1)
      .get();

    if (!checkInSnap.empty) continue;

    // Send FCM push reminder
    try {
      await messaging.send({
        token: fcmToken,
        notification: {
          title: 'Time to check in!',
          body: "Don't forget to tap your safety button today.",
        },
        android: {
          priority: 'high',
          notification: { sound: 'default' },
        },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      });
      sent++;
    } catch (err: any) {
      // Token may be stale — don't crash the job
      if (err.code === 'messaging/registration-token-not-registered') {
        await db.collection('users').doc(seniorId).update({ fcmToken: null });
      }
      console.error(`FCM send failed for ${seniorId}:`, err.message);
    }
  }

  console.log(`reminderJob: sent ${sent} reminders`);
  return { sent };
}
