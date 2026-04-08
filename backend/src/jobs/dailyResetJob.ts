import { db } from '../config/firebase';
import { todayInTimezone } from '../config/timezone';
import { logger } from '../lib/logger';

export async function dailyResetJob(): Promise<{ reset: number }> {
  // Reset alertSentToday for all seniors whose alertSentToday is true
  const settingsSnap = await db
    .collection('seniorSettings')
    .where('alertSentToday', '==', true)
    .get();

  let resetCount = 0;
  const batch = db.batch();

  for (const doc of settingsSnap.docs) {
    const data = doc.data();
    const seniorId = doc.id;

    // Get the senior's timezone to calculate their "today"
    let timezone = 'America/New_York';
    try {
      const userDoc = await db.collection('users').doc(seniorId).get();
      if (userDoc.exists) {
        timezone = userDoc.data()?.timezone || 'America/New_York';
      }
    } catch {
      // Fall through with default timezone
    }

    const seniorToday = todayInTimezone(timezone);

    // Only reset if lastAlertReset is a previous day in the senior's timezone
    if (data.lastAlertReset !== seniorToday) {
      batch.update(doc.ref, {
        alertSentToday: false,
        reminderSentToday: false,
        lastAlertReset: seniorToday,
      });
      resetCount++;
    }
  }

  if (resetCount > 0) {
    await batch.commit();
  }

  logger.info('dailyResetJob complete', { reset: resetCount });
  return { reset: resetCount };
}
