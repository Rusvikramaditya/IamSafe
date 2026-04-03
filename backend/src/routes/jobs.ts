import { Router, Request, Response } from 'express';
import { missedCheckInJob } from '../jobs/missedCheckInJob';
import { dailyResetJob } from '../jobs/dailyResetJob';
import { reminderJob } from '../jobs/reminderJob';

export const jobRoutes = Router();

/**
 * Defense-in-depth: Verify Cloud Scheduler requests.
 * Primary auth is Cloud Run IAM, but this header check prevents
 * accidental invocation during dev or from misconfigured deployments.
 */
function verifyJobAuth(req: Request, res: Response): boolean {
  const expectedKey = process.env.JOB_API_KEY;
  if (!expectedKey) {
    // No key set — allow in dev, block in production
    if (process.env.NODE_ENV === 'production') {
      console.error('JOB_API_KEY not set in production — blocking job request');
      res.status(401).json({ error: 'Unauthorized' });
      return false;
    }
    return true;
  }

  const providedKey = req.headers['x-job-api-key'];
  if (providedKey !== expectedKey) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

jobRoutes.post('/missed-checkin', async (req: Request, res: Response) => {
  if (!verifyJobAuth(req, res)) return;

  try {
    const result = await missedCheckInJob();
    res.json({ success: true, ...result });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    console.error('missedCheckInJob failed:', msg);
    res.status(500).json({ error: 'Job failed' });
  }
});

jobRoutes.post('/daily-reset', async (req: Request, res: Response) => {
  if (!verifyJobAuth(req, res)) return;

  try {
    const result = await dailyResetJob();
    res.json({ success: true, ...result });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    console.error('dailyResetJob failed:', msg);
    res.status(500).json({ error: 'Job failed' });
  }
});

jobRoutes.post('/reminders', async (req: Request, res: Response) => {
  if (!verifyJobAuth(req, res)) return;

  try {
    const result = await reminderJob();
    res.json({ success: true, ...result });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : 'Unknown error';
    console.error('reminderJob failed:', msg);
    res.status(500).json({ error: 'Job failed' });
  }
});
