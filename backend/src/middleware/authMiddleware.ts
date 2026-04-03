import { Request, Response, NextFunction } from 'express';
import { auth, db } from '../config/firebase';

export interface AuthRequest extends Request {
  uid?: string;
  userRole?: 'senior' | 'caregiver';
}

export async function authMiddleware(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid Authorization header' });
    return;
  }

  try {
    const token = header.slice(7); // safer extraction than split()
    const decoded = await auth.verifyIdToken(token);
    req.uid = decoded.uid;

    // Populate role from Firestore so routes don't need to re-fetch
    const userDoc = await db.collection('users').doc(decoded.uid).get();
    if (userDoc.exists) {
      req.userRole = userDoc.data()?.role as 'senior' | 'caregiver' | undefined;
    }

    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}
