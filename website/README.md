# SuggestMeSome Static Site

This directory contains the public static pages that back the URLs configured in the iOS app:

- `https://www.suggestmesome.app/support`
- `https://www.suggestmesome.app/privacy`
- `https://www.suggestmesome.app/terms`
- `https://www.suggestmesome.app/consumer-health`
- `https://www.suggestmesome.app/privacy-choices`

## Deployment

Deploy the contents of this directory to the web root for `suggestmesome.app` on any static host.

Expected route mapping:

- `website/index.html` -> `/`
- `website/support/index.html` -> `/support`
- `website/privacy/index.html` -> `/privacy`
- `website/terms/index.html` -> `/terms`
- `website/consumer-health/index.html` -> `/consumer-health`
- `website/privacy-choices/index.html` -> `/privacy-choices`

## Maintenance

- Keep copy aligned with the in-app legal documents in `SuggestMeSome/Compliance/ComplianceConfiguration.swift`.
- Update both the hosted site and the in-app documents when data practices, support channels, or legal language changes.
- Confirm the App Store Connect Support URL, Privacy Policy URL, and optional Privacy Choices URL match the deployed pages exactly.
