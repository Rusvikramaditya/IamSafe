import { Router, Request, Response } from 'express';
import { missedCheckInJob } from '../jobs/missedCheckInJob';
import { dailyResetJob } from '../jobs/dailyResetJob';
import { reminderJob } from '../jobs/reminderJob';

export const jobRoutes = Router();

// Cloud Scheduler calls these endpoints via HTTP
// Auth is handled by Cloud Run's IAM (only Cloud Scheduler service account can invoke)

jobRoutes.post('/missed-check-in', async (_req: Request, res: Response) => {
  try {
    const result = await missedCheckInJob();
    res.json({ success: true, ...result });
  } catch (err: any) {
    console.error('missedCheckInJob failed:', err);
    res.status(500).json({ error: 'Job failed', message: err.message });
  }
});

jobRoutes.post('/daily-reset', async (_req: Request, res: Response) => {
  try {
    const result = await dailyResetJob();
    res.json({ success: true, ...result });
  } catch (err: any) {
    console.error('dailyResetJob failed:', err);
    res.status(500).json({ error: 'Job failed', message: err.message });
  }
});

jobRoutes.post('/reminder', async (_req: Request, res: Response) => {
  try {
    const result = await reminderJob();
    res.json({ success: true, ...result });
  } catch (err: any) {
    console.error('reminderJob failed:', err);
    res.status(500).json({ error: 'Job failed', message: err.message });
  }
});
