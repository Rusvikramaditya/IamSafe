# App Store Privacy Nutrition Label — IamSafe

Use this when filling out App Store Connect > App Privacy.

## Data Types Collected

### 1. Contact Info
| Field | Used for | Linked to identity? |
|-------|----------|-------------------|
| Name | App Functionality | Yes |
| Email Address | App Functionality | Yes |
| Phone Number | App Functionality (optional, SMS alerts) | Yes |

### 2. User Content
| Field | Used for | Linked to identity? |
|-------|----------|-------------------|
| Photos (selfies) | App Functionality | Yes |

### 3. Identifiers
| Field | Used for | Linked to identity? |
|-------|----------|-------------------|
| User ID (Firebase UID) | App Functionality | Yes |
| Device token (FCM) | App Functionality (push notifications) | No |

### 4. Purchases
| Field | Used for | Linked to identity? |
|-------|----------|-------------------|
| Purchase history | App Functionality (subscription management via RevenueCat) | Yes |

## Data NOT Collected
- Location — No
- Health & Fitness — No
- Browsing History — No
- Search History — No
- Diagnostics — No
- Usage Data / Analytics — No
- Advertising Data — No
- Financial Info (payment details) — No (handled by Apple/Google)
- Sensitive Info — No
- Contacts (phone address book) — No

## Data Use Declarations
- **Tracking:** No. We do not track users across other apps or websites.
- **Third-party advertising:** None.
- **Analytics:** None collected through the app.

## Notes for Reviewer
- Selfies are stored max 30 days, then auto-deleted
- All data stored in US (us-central1) on Google Firebase
- Emergency contact info provided voluntarily by the user (not pulled from device contacts)
- Phone number is optional, only used for premium SMS alerts
