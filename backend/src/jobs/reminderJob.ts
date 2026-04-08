import { db, messaging } from '../config/firebase';
import { nowInTimezone, todayInTimezone } from '../config/timezone';
import { logger } from '../lib/logger';

export async function reminderJob(): Promise<{ sent: number }> {
  let sent = 0;

  // Only fetch settings where alert and reminder haven't been sent today
  const settingsSnap = await db
    .collection('seniorSettings')
    .where('alertSentToday', '==', false)
    .where('reminderSentToday', '==', false)
    .get();

  for (const settingsDoc of settingsSnap.docs) {
    try {
      const seniorId = settingsDoc.id;
      const settings = settingsDoc.data();

      const userDoc = await db.collection('users').doc(seniorId).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data()!;
      const timezone = userData.timezone || 'America/New_York';
      const fcmToken = userData.fcmToken;

      if (!fcmToken) continue;

      // Use dayjs for reliable timezone conversion
      const nowTz = nowInTimezone(timezone);
      const [endH, endM] = settings.windowEnd.split(':').map(Number);
      const endToday = nowTz.hour(endH).minute(endM).second(0).millisecond(0);
      const reminderMinutes = settings.reminderMinutes || 30;
      const reminderTime = endToday.subtract(reminderMinutes, 'minute');

      // Send reminder only if we're in the reminder window and before window end
      if (nowTz.isBefore(reminderTime) || !nowTz.isBefore(endToday)) continue;

      // Check if already checked in today
      const today = todayInTimezone(timezone);
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

        // Mark reminder as sent to prevent duplicates
        await settingsDoc.ref.update({ reminderSentToday: true });
        sent++;
      } catch (err: unknown) {
        const error = err as { code?: string; message?: string };
        // Token may be stale — clear it
        if (error.code === 'messaging/registration-token-not-registered') {
          await db.collection('users').doc(seniorId).update({ fcmToken: null });
        }
        logger.error('FCM send failed', { seniorId, error: error.message });
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      logger.error('reminderJob: error processing senior', { seniorId: settingsDoc.id, error: msg });
    }
  }

  logger.info('reminderJob complete', { sent });
  return { sent };
}
