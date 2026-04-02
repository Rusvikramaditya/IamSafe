import { db } from '../config/firebase';

export async function dailyResetJob(): Promise<{ reset: number }> {
  const today = new Date().toISOString().split('T')[0];

  // Reset alertSentToday for all seniors whose lastAlertReset is not today
  const settingsSnap = await db
    .collection('seniorSettings')
    .where('alertSentToday', '==', true)
    .get();

  let resetCount = 0;

  for (const doc of settingsSnap.docs) {
    const data = doc.data();

    // Only reset if lastAlertReset is a previous day
    if (data.lastAlertReset !== today) {
      await doc.ref.update({
        alertSentToday: false,
        lastAlertReset: today,
      });
      resetCount++;
    }
  }

  console.log(`dailyResetJob: reset ${resetCount} seniors`);
  return { reset: resetCount };
}
