# IamSafe — Project Plan

## What is it
A mobile safety check-in app for senior citizens living alone. The senior taps one large "I Am Safe" button daily. If they miss their window, their loved ones get alerted automatically. Optional selfie adds emotional connection — key differentiator over competitors like Snug Safety and I Am Fine.

**Market:** USA, consumer-only. 16.2M+ US seniors live alone. Elderly care app market growing 13.92% CAGR to $16.87B by 2033.

---

## Confirmed Stack

| Layer | Choice | Why / Cost |
|-------|--------|------------|
| Mobile | **Flutter** (iOS + Android) | Best elderly UX, native perf, no JS bridge, FlutterFire SDK |
| Subscriptions | **RevenueCat** (`purchases_flutter`) | Industry standard. Free up to $2,500 MRR, then 1% of revenue. Handles App Store + Play Store billing. |
| Backend | **Google Cloud Run** | Auto-scales 0→millions, pay-per-request, same GCP ecosystem as Firebase. Replaces Railway. |
| Scheduler (cron) | **Google Cloud Scheduler** | Enterprise-grade, 99.9% SLA, $0.10/job/month. Replaces Railway cron. |
| Database | **Firebase Firestore** | Free: 1GB, 50K reads/day, 20K writes/day. Region: `us-central1` (USA data residency). |
| Auth | **Firebase Auth** | Free: unlimited email/password, 10K SMS OTP/month (USA) |
| File storage | **Firebase Cloud Storage** | Free: 5GB, 1GB/day. Region: `us-central1`. |
| Push notifications | **FCM** (`firebase_messaging`) | Free, unlimited — reminders to senior only |
| Primary alerts | **Resend** (email) | Free: 3,000 emails/month. Goes to contacts on missed check-in. |
| SMS alerts | **Twilio** | Premium feature only. ~$0.008/SMS USA. $15 trial credit for dev/testing. |
| Auth SMS OTP | Firebase Auth | 10K/month free (USA) |

> **Supabase:** Not used — blocked in India where developer is based.
> **Alert strategy:** Email-first (free tier) → SMS as premium paid feature → Push if contact installs app (free)
> **App Store cuts:** Apple 15–30%, Google 15%. RevenueCat abstracts both. Price accordingly.

---

## Project Structure

```
IamSafe/
├── mobile/                  # Flutter app
│   ├── lib/
│   │   ├── screens/
│   │   │   ├── auth/
│   │   │   ├── senior/
│   │   │   └── caregiver/
│   │   ├── widgets/
│   │   ├── services/
│   │   ├── theme/
│   │   └── main.dart
│   └── pubspec.yaml
└── backend/                 # Node.js + Express + TypeScript
    ├── src/
    │   ├── routes/
    │   ├── services/
    │   ├── jobs/
    │   └── index.ts
    ├── Dockerfile
    └── package.json
```

---

## Data Model (Firestore — region: us-central1)

```
/users/{userId}
  - email, phone, fullName, role ('senior'|'caregiver')
  - fcmToken, timezone, createdAt
  - entitlements: [] | ['premium'] | ['family']   ← set by RevenueCat webhook

/seniorSettings/{seniorId}
  - windowStart (HH:mm), windowEnd (HH:mm)
  - selfieEnabled (bool), reminderMinutes (int)
  - alertSentToday (bool), lastAlertReset (date)

/contacts/{contactId}
  - seniorId, fullName, phone, email
  - relationship, alertOnMissed (bool)
  - emailOptedOut (bool), smsOptedOut (bool)

/checkIns/{checkInId}
  - seniorId, checkInDate (YYYY-MM-DD)   ← unique per senior per day
  - checkedInAt (timestamp|null), status ('on_time'|'late'|'missed')
  - selfiePath (storage path — never a public URL)

/alertLog/{alertId}
  - checkInId, seniorId, contactId
  - sentAt, channel ('email'|'sms'), status, messageId

/seniorCaregiverLinks/{linkId}
  - seniorId, caregiverId, inviteCode
  - inviteExpires, acceptedAt
```

---

## RevenueCat Integration

```
Flutter app
  → purchases_flutter SDK
    → App Store (iOS) / Play Store (Android)
      → RevenueCat dashboard (MRR, churn, cohorts)
        → Webhook → Cloud Run backend
          → Firestore: users/{id}.entitlements updated
            → Flutter app reacts in real time
```

**Products (defined in RevenueCat + both stores):**

| Product | Price | Store net (after 15% cut) |
|---------|-------|--------------------------|
| Premium monthly | $4.99/mo | ~$4.24 |
| Premium annual | $39.99/yr | ~$33.99 |
| Family pack monthly | $9.99/mo | ~$8.49 |
| Family pack annual | $79.99/yr | ~$67.99 |

**Entitlements:**
- `premium` — SMS alerts, unlimited history, selfie history, multiple caregivers
- `family` — all premium + up to 3 seniors per account

**Free tier:** Daily check-in, email alerts, 1 caregiver, 7-day history — no credit card required.

---

## Backend API (Cloud Run)

```
POST   /api/v1/auth/register
POST   /api/v1/auth/link-senior            -- caregiver links via invite code

POST   /api/v1/check-ins                   -- submit check-in
POST   /api/v1/check-ins/selfie-url        -- presigned Firebase Storage upload URL
GET    /api/v1/check-ins/today
GET    /api/v1/check-ins/history
GET    /api/v1/check-ins/:id               -- includes signed selfie URL (1hr expiry)

GET/POST/PUT/DELETE  /api/v1/contacts
POST   /api/v1/contacts/:id/test-alert

GET/PUT  /api/v1/settings

GET    /api/v1/dashboard/:seniorId/summary   -- 30-day status array
GET    /api/v1/dashboard/:seniorId/streak
GET    /api/v1/dashboard/:seniorId/alerts

POST   /api/v1/webhooks/twilio             -- SMS delivery + STOP opt-out
POST   /api/v1/webhooks/resend             -- email delivery status
POST   /api/v1/webhooks/revenuecat         -- subscription events → update entitlements
```

---

## Background Jobs (Google Cloud Scheduler → Cloud Run)

1. **`missedCheckInJob`** — every 15 minutes
   - Find seniors: current_time (their timezone) > windowEnd AND no check-in today AND alertSentToday = false
   - Create missed check-in doc → send Resend email → log to alertLog → set alertSentToday = true
   - If user has `premium` entitlement: also send Twilio SMS

2. **`reminderJob`** — every 15 minutes
   - 30 min before windowEnd + not yet checked in → send FCM push to senior

3. **`dailyResetJob`** — midnight UTC (job runs per timezone bucket)
   - Reset `alertSentToday = false` in seniorSettings

---

## Mobile App Screens (Flutter)

**Senior (2 tabs):**
- `HomeScreen` — full-screen, one giant button. 1-tap from app open after login.
- `SeniorSettingsScreen` — check-in window, selfie toggle, contacts list

**Caregiver (3 tabs):**
- `DashboardScreen` — 30-day calendar grid (green/yellow/red/grey dots)
- `CheckInDetailScreen` — timestamp + selfie viewer
- `CaregiverSettingsScreen` — manage senior links, alert preferences, subscription

**Auth:**
- `WelcomeScreen` → `LoginScreen` / `SignupScreen` → `SetupWizardScreen` (4 steps)

**Paywall:**
- `PaywallScreen` — shown when free user hits a premium feature. Built with RevenueCat Paywalls SDK.

---

## Implementation Phases

### Phase 1 — Core check-in + email alert
- Firebase project setup (Firestore + Auth + Storage, region: `us-central1`)
- Cloud Run backend + Firebase Admin SDK + Dockerfile
- Cloud Scheduler jobs setup
- `POST /api/v1/check-ins` + contacts + settings endpoints
- `missedCheckInJob` + Resend email alerts + `dailyResetJob`
- Flutter: Auth screens + Senior HomeScreen with giant button
- **E2E test:** miss window → email received ✓

### Phase 2 — Selfie upload
- Flutter `image_picker` + `image` (compress <1MB)
- Direct-to-Firebase Storage upload via presigned URL
- Selfie confirmation on HomeScreen post-tap
- Selfie viewer in CheckInDetailScreen (signed URL, 1hr expiry)

### Phase 3 — Caregiver dashboard
- Invite-code link flow
- 30-day summary endpoint + CalendarGrid Flutter widget
- FCM push reminders
- Alert history + streak
- RevenueCat SDK integration + PaywallScreen
- `POST /api/v1/webhooks/revenuecat` → update Firestore entitlements
- Premium gate: SMS alerts, history > 7 days, selfie history

### Phase 4 — Store submission
- App Store Connect setup + IAP products configured
- Google Play Console setup + subscriptions configured
- RevenueCat products linked to both stores
- Privacy policy + terms of service (required by both stores)
- App Store review compliance: accessibility, privacy nutrition label
- TestFlight beta + Play internal testing track

**Total estimate: ~20 developer-days**

---

## Monetization

| Tier | Price | Features |
|------|-------|---------|
| Free | $0 | Check-in button, email alerts, 1 caregiver, 7-day history |
| Premium | $4.99/mo or $39.99/yr | + SMS alerts, unlimited history, selfie history, multiple caregivers |
| Family | $9.99/mo or $79.99/yr | + up to 3 seniors per account, all premium features |

Revenue after store cuts (~15%): Premium = ~$4.24/mo, Family = ~$8.49/mo.

---

## Elderly UX Requirements (non-negotiable)

- **Button:** 200×200dp minimum, circular, full-screen centered
- **Fonts:** Body 20sp, headings 28sp, button label 36sp — honor system font scale
- **Contrast:** WCAG AA (4.5:1) minimum, target AAA (7:1)
- **Post-tap feedback:** Triple — visual (color + checkmark) + haptic + audio chime
- **State change:** Icon AND label change together — never color alone
- **Navigation:** 1 tap to button from app open after login
- **Errors:** Never show technical errors to senior — friendly text + large retry button
- **Accessibility:** Full Flutter `Semantics`, VoiceOver/TalkBack, 44pt min tap targets

---

## Security & Privacy

- Selfies: private bucket, signed URLs only (1hr expiry), deleted after 30 days always
- Auth tokens: `flutter_secure_storage` — never SharedPreferences
- Email/phone: never logged in plaintext
- Opt-out: Resend unsubscribe + Twilio STOP honored immediately
- Data retention: check-ins > 90 days deleted (free), selfies > 30 days always
- RBAC: Firestore security rules enforce caregiver access to linked seniors only
- Rate limiting: auth 5 req/min, check-in 10 req/hr
- US data residency: all Firebase resources in `us-central1`
- Do NOT store: location, API keys in mobile app, behavioral metadata

---

## Key Files

| File | Purpose |
|------|---------|
| `backend/src/jobs/missedCheckInJob.ts` | Core logic — whole product depends on this |
| `backend/src/services/AlertService.ts` | Resend email + Twilio SMS abstraction |
| `backend/src/routes/webhooks.ts` | RevenueCat + Twilio + Resend webhooks |
| `mobile/lib/screens/senior/home_screen.dart` | The big button — primary UX |
| `mobile/lib/theme/typography.dart` | Elderly font sizes — cascades everywhere |
| `mobile/lib/widgets/check_in_button.dart` | Giant reusable button widget |
| `mobile/lib/screens/paywall_screen.dart` | RevenueCat paywall — revenue depends on this |
| `firestore.rules` | Security rules — caregiver access enforcement |

---

## Progress

### Phase 1 — Core check-in + email alert
- [ ] Firebase project setup (Firestore + Auth + Storage, region: `us-central1`)
- [x] Cloud Run backend + Firebase Admin SDK + Dockerfile
- [ ] Google Cloud Scheduler jobs configured
- [x] `POST /api/v1/check-ins` + contacts + settings endpoints
- [x] `missedCheckInJob` + Resend email alerts
- [x] `dailyResetJob`
- [x] Flutter: Auth screens (Welcome, Login, Signup, SetupWizard)
- [x] Flutter: Senior HomeScreen with giant button
- [ ] E2E test: miss window → email received ✓

### Phase 2 — Selfie upload
- [x] Flutter `image_picker` + `image` (compress <1MB)
- [x] Presigned Firebase Storage upload URL endpoint
- [x] Direct-to-storage upload flow in Flutter
- [x] Selfie confirmation on HomeScreen post-tap
- [x] Selfie viewer in CheckInDetailScreen (signed URL, 1hr expiry)

### Phase 3 — Caregiver dashboard
- [x] Invite-code link flow (`seniorCaregiverLinks`)
- [x] 30-day summary endpoint + CalendarGrid Flutter widget
- [x] FCM push reminders to senior (reminderJob)
- [x] Alert history endpoint + streak endpoint
- [x] RevenueCat SDK integration + PaywallScreen
- [x] `POST /api/v1/webhooks/revenuecat` → update Firestore entitlements
- [x] Premium gate: SMS alerts, history > 7 days, selfie history
- [x] Role-based routing (AuthGate: senior → SeniorHomeScreen, caregiver → CaregiverDashboard)
- [x] CaregiverDashboardScreen (calendar, streak, recent activity, link senior flow)
- [x] CheckInDetailScreen with selfie viewer (caregiver view)
- [x] Senior settings: add contact dialog, delete contact
- [x] Auth: forgot password flow on LoginScreen
- [x] FCM messaging service — request permissions, send token to backend
- [x] Google Sign-In across all auth screens
- [x] Firebase Crashlytics for fatal error tracking
- [x] Offline role caching (FlutterSecureStorage) — survives backend outages
- [x] Webhook signature verification (Twilio, Resend, RevenueCat)
- [x] Timezone-aware jobs via dayjs (IANA timezone, not Date.now())
- [x] BYPASS_FIREBASE via --dart-define (defaults false in prod)
- [x] flutter_timezone for IANA timezone detection on device

### Phase 4 — Store submission
- [ ] App Store Connect account + IAP products configured
- [ ] Google Play Console account + subscriptions configured
- [ ] RevenueCat products linked to both stores
- [x] Privacy policy + terms of service pages
- [x] App Store privacy nutrition label
- [ ] TestFlight beta testing
- [ ] Google Play internal testing track
- [ ] App Store submission + review
- [ ] Google Play submission + review

---

## Verification Tests

1. Senior taps before windowEnd → `status=on_time` → no alert
2. Senior misses window → cron fires → `status=missed` → email within 15 min
3. Premium user misses → email + SMS both sent
4. Selfie taken → appears in caregiver CheckInDetailScreen via signed URL
5. Contact unsubscribes → `emailOptedOut=true` → no further email
6. RevenueCat webhook fires → `users.entitlements` updated in Firestore → app unlocks premium
7. Caregiver logs in → 30-day calendar correct → tap day shows detail + selfie
8. Delete account → all Firestore docs + Storage files removed
