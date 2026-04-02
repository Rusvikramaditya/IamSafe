import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { authRoutes } from './routes/auth';
import { checkInRoutes } from './routes/checkIns';
import { contactRoutes } from './routes/contacts';
import { settingsRoutes } from './routes/settings';
import { dashboardRoutes } from './routes/dashboard';
import { webhookRoutes } from './routes/webhooks';
import { jobRoutes } from './routes/jobs';

const app = express();
const PORT = parseInt(process.env.PORT || '8080', 10);

app.use(helmet());
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/check-ins', checkInRoutes);
app.use('/api/v1/contacts', contactRoutes);
app.use('/api/v1/settings', settingsRoutes);
app.use('/api/v1/dashboard', dashboardRoutes);
app.use('/api/v1/webhooks', webhookRoutes);
app.use('/api/v1/jobs', jobRoutes);

app.listen(PORT, () => {
  console.log(`IamSafe backend running on port ${PORT}`);
});

export default app;
