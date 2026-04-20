# SuggestMeSome App Store Launch Checklist

This checklist tracks the non-code work required to ship `SuggestMeSome` as a **free iOS app** with a **one-time `Premium Unlock`** in-app purchase.

## Apple Developer Account

- Verify the explicit App ID for `com.alexyao.SuggestMeSome`.
- Enable these App ID capabilities:
  - Push Notifications
  - Sign in with Apple
  - HealthKit
- Create and store APNs auth credentials for the production backend.
- Confirm automatic signing is using the correct team and provisioning profiles.

## Backend and Operations

- Run the production backend at `https://api.suggestmesome.app/v1`.
- Verify:
  - Sign in with Apple token exchange
  - session refresh
  - sync bootstrap / push / pull
  - privacy request submission
  - export generation and download
  - delete-account handling and server-side token revocation
  - APNs device-token registration and delivery
- Monitor and alert on:
  - auth failures
  - sync failures
  - push registration failures
  - privacy request failures
  - deletion failures
- Staff `support@suggestmesome.app` and `privacy@suggestmesome.app`.
- Finalize retention, deletion, and incident-response procedures before public launch.

## Hosted Site

- Deploy the contents of `website/` to `https://www.suggestmesome.app`.
- Confirm these routes are live and public:
  - `/support`
  - `/privacy`
  - `/terms`
  - `/consumer-health`
  - `/privacy-choices`
- Ensure hosted copy stays aligned with the in-app legal documents in `ComplianceConfiguration`.

## App Store Connect

- Create or verify the app record for `SuggestMeSome`.
- Keep the app itself priced as **Free**.
- Create `premium_unlock` as a **Non-Consumable** IAP.
- Complete:
  - Paid Apps Agreement
  - banking
  - U.S. tax setup
- Fill required product metadata:
  - subtitle
  - description
  - keywords
  - screenshots
  - support URL
  - privacy policy URL
  - copyright
  - age rating
- Add the custom U.S. EULA/Terms in App Store Connect.
- Complete App Privacy using the real shipped data flows for:
  - Premium Unlock
  - Sign in with Apple
  - cloud sync
  - coach collaboration
  - private sharing
  - push registration
  - optional Apple Health access
- Add App Review notes that explain:
  - the app is free
  - Premium Unlock is a one-time purchase
  - Apple Health is optional
  - cloud/collaboration are optional
  - `Preview Cloud Features` is available from the signed-out account screen

## Beta / Release Validation

- Before external TestFlight:
  - verify hosted URLs are live
  - verify backend is live
  - verify purchase and restore work
  - verify sign-in, sync, export, delete-data, and delete-account work on device
- Before App Store submission:
  - verify no Apple Health prompt bypasses the in-app preflight flow
  - verify Preview Cloud Features works without backend mutation
  - verify App Privacy answers still match the current build
  - verify screenshots and metadata reflect the free app + Premium Unlock model
- After approval:
  - use manual release for the first launch
  - watch backend/auth/sync/push logs closely
  - use IAP offer codes for friends and testers who should get Premium Unlock without paying
