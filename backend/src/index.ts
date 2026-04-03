import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
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

// Trust proxy — required for Cloud Run so rate limiter uses real client IP
app.set('trust proxy', true);

app.use(helmet());

// CORS — restrict to known origins in production
const allowedOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',')
  : ['http://localhost:3000', 'http://localhost:8080'];
app.use(
  cors({
    origin: (origin, callback) => {
      // Allow requests with no origin (mobile apps, curl, Cloud Scheduler)
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    credentials: true,
  })
);

app.use(express.json({ limit: '1mb' }));

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

// Global error handler — catches unhandled async errors
app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error('Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, () => {
  console.log(`IamSafe backend running on port ${PORT}`);
});

// Graceful shutdown for Cloud Run SIGTERM
process.on('SIGTERM', () => {
  console.log('SIGTERM received — shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

export default app;
