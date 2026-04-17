# Promo Codes Guide

## Overview
Promo codes are designed for sideload users (APK downloads) in regions where the app isn't available on Play Store. The button to redeem codes is hidden by default and requires **5 taps on the premium icon** in the paywall header to reveal.

## Security Features
1. **Hidden UI**: Button only appears after 5 taps on logo (not obvious to regular users)
2. **Rate limiting**: 3 attempts per user per hour
3. **Single-use tracking**: Codes are marked as used per-user in Firestore
4. **Max uses**: Each code can be set to allow X total redemptions
5. **Expiration dates**: Codes can expire after a set date
6. **Audit logging**: All redemptions are logged to `promo_redemptions` collection

## Creating Promo Codes

### Firestore Structure

**Collection**: `promo_codes`  
**Document ID**: The promo code itself (e.g., `SIDELOAD50`)

**Document Fields**:
```json
{
  "type": "proOffline",           // or "premium"
  "maxUses": 50,                  // Total number of redemptions allowed
  "usedBy": [],                   // Array of UIDs who have used this code
  "expiresAt": <Timestamp>,       // Optional: when the code expires
  "createdAt": <Timestamp>,       // When you created the code
  "createdBy": "admin",           // Who created it
  "description": "Sideload users Q1 2025",  // Optional notes
  "lastUsedAt": <Timestamp>       // Auto-updated when redeemed
}
```

### Example Codes

#### ✅ Recommended: Single-Use Unique Codes (50 different codes)
```
Document ID: A3F7K2P9
{
  "type": "proOffline",
  "maxUses": 1,
  "usedBy": [],
  "expiresAt": <Timestamp for 3 months from now>,
  "createdAt": <now>,
  "createdBy": "admin-script",
  "batchId": "abc123def456",
  "description": "Q1 2025 sideload batch"
}

... plus 49 more unique codes (Q8W4E2R5, M9N2B5V8, etc.)
```

**This is the recommended approach** - generate 50 unique codes, each redeemable once. Use the automated script below.

#### ⚠️ Legacy: Multi-Use Code (one code, 50 uses)
```
Document ID: SIDELOAD50
{
  "type": "proOffline",
  "maxUses": 50,
  "usedBy": [],
  "expiresAt": <Timestamp for 3 months from now>,
  "createdAt": <now>,
  "createdBy": "admin",
  "description": "50 free Pro-Offline for sideload users Q1 2025"
}
```

**Not recommended** - creates one code shared by 50 users (tracking issues, potential abuse).

#### Premium Code (subscription-equivalent)
```
Document ID: TESTPREM
{
  "type": "premium",
  "maxUses": 1,
  "usedBy": [],
  "expiresAt": <Timestamp for 1 month from now>,
  "createdAt": <now>,
  "createdBy": "admin",
  "description": "Premium test code"
}
```

## How to Create Codes

### ⭐ Option 1: Automated Script (Recommended for Batches)

Generate 50 unique, single-use codes automatically:

**Setup:**
1. Get Firebase service account key:
   - Firebase Console → Project Settings → Service Accounts
   - Click "Generate new private key"
   - Save as `functions/service-account.json`
   - **Add to .gitignore** (never commit)

2. Install dependencies:
   ```bash
   cd functions/scripts
   npm install firebase-admin
   ```

**Usage:**
```bash
# Generate 50 unique Pro-Offline codes (expires in 90 days)
cd functions/scripts
node generate-promo-codes.js 50 proOffline 90 "Q1 2025 sideload batch"

# Generate 10 Premium codes (expires in 30 days)
node generate-promo-codes.js 10 premium 30 "Beta tester codes"

# Generate 100 codes (no expiration)
node generate-promo-codes.js 100 proOffline null "No expiration batch"
```

**Output:**
- Creates all codes in Firestore (each with `maxUses: 1`)
- Saves to `functions/scripts/generated-codes/proOffline-codes-2025-12-07-50.txt`
- One code per line for easy distribution

### Option 2: Firebase Console (Manual, Testing Only)
1. Go to Firebase Console → Firestore Database
2. Navigate to `promo_codes` collection (create if it doesn't exist)
3. Click "Add document"
4. Set Document ID to your promo code (e.g., `TESTCODE1`)
5. Add fields:
   - `type`: string (`"premium"` or `"proOffline"`)
   - `maxUses`: number (`1` for single-use)
   - `usedBy`: array (empty: `[]`)
   - `createdAt`: timestamp (now)
   - `description`: string
   - `expiresAt`: timestamp (optional, e.g., 30 days from now)
6. Click "Save"

**Note:** Only use for testing or 1-2 codes. For batches, use the automated script.

## Monitoring Usage

### Check Redemptions
Query the `promo_redemptions` collection to see who redeemed what:
```javascript
db.collection('promo_redemptions')
  .orderBy('redeemedAt', 'desc')
  .limit(50)
  .get()
```

### Check Code Status
```javascript
const codeSnap = await db.collection('promo_codes').doc('SIDELOAD50').get();
const data = codeSnap.data();
console.log(`Used: ${data.usedBy.length}/${data.maxUses}`);
```

### View Rate Limit Attempts
Check `promo_attempts/{uid}` to see failed attempts per user.

## Revoking Codes

To disable a code, simply delete the document from `promo_codes` collection, or set `maxUses` to the current `usedBy.length` to prevent new redemptions.

## Best Practices

1. **Use unique codes**: Generate 50 different codes instead of one code with 50 uses
2. **Single-use only**: Set `maxUses: 1` for all codes to prevent sharing abuse
3. **Set reasonable expiration dates**: 90 days for Pro-Offline, 30 days for Premium
4. **Track batches**: Use the `batchId` field to identify which generation batch codes came from
5. **Monitor redemptions**: Check the `promo_redemptions` collection weekly for suspicious patterns
6. **Secure distribution**: Only give codes to verified sideload users via email/support tickets (never post publicly)
7. **Rotate batches**: Generate new batches every quarter and let old codes expire

## Security Notes

- **Unique codes**: Each code is single-use (`maxUses: 1`), preventing sharing or resale
- **Hidden UI**: Redemption button only appears after 5 taps on premium icon (99% of users won't see it)
- **Rate limiting**: Max 3 redemption attempts per user per hour (prevents brute force)
- **Firestore storage**: Codes stored server-side (can't be reverse-engineered from APK)
- **Audit logging**: All attempts and redemptions logged with timestamp, email, UID
- **Tracking**: Each code tracks which UIDs redeemed it via `usedBy` array
- **Expiration**: All codes should have expiration dates to limit exposure window

## Support Workflow

When a user contacts support saying they sideloaded the APK:

1. **Verify**: Confirm they actually sideloaded (not available in their region)
2. **Generate codes**: If you haven't already, run the script to generate 50 codes
3. **Send code**: Email them one code from your batch with instructions:
   - "In the app, go to Settings → Upgrade"
   - "Tap the premium icon in the header 5 times quickly"
   - "Tap 'Redeem promo code' button"
   - "Enter code: `[THEIR-CODE]`"
4. **Track redemption**: Mark which code you sent them in a spreadsheet
5. **Monitor**: Check `promo_redemptions` collection to confirm they redeemed it
6. **Follow up**: If they have issues, check `promo_attempts` for error details

## Distribution Tips

- **Spreadsheet tracking**: Keep a CSV with columns: `code, sentTo (email), sentDate, redeemedDate, redeemedBy (uid)`
- **Email template**: Save a support email template with redemption instructions
- **Batch management**: Generate new batches quarterly, let old ones expire naturally
- **Don't reuse**: Once a code is redeemed, it's done (single-use only)

---

**Created**: 2025-12-07  
**Last Updated**: 2025-12-07
