# Apple Pickup Tracker (iOS)

Native SwiftUI app prototype for tracking Apple Store Pickup order emails from Gmail. Mail parsing and order persistence run on-device; Gmail access uses OAuth 2.0 with the read-only `gmail.readonly` scope. The app does not send email contents or order data to a developer backend.

## Current first-version scope

- Gmail OAuth authorization using `ASWebAuthenticationSession` + PKCE.
- Read-only Gmail API search for Apple order/pickup emails.
- On-device MIME/base64url decoding and basic status extraction.
- Local JSON persistence in Application Support with file protection.
- Order list, detail, status history, manual sync.
- ActivityKit Live Activity and Dynamic Island UI.
- Local notification when a Ready for Pickup message is found.
- Best-effort `BGAppRefreshTask` scheduling.

## Important limitations

1. This is a source project, not a signed IPA. An iOS build and signing require Xcode on macOS and your Apple account/team.
2. Background refresh is opportunistic. iOS decides whether and when to run it; it is not a polling service.
3. Live Activity is started when the app is opened/synced in the foreground. Subsequent updates occur when the app gets execution time. No server/APNs relay is included.
4. Apple email templates vary by storefront and locale. The initial parser is heuristic and needs real, redacted samples from the user's region to validate order-number, product, store, and status extraction.
5. Gmail `gmail.readonly` is a restricted scope. Configure the OAuth consent screen and add your Google account as a test user while developing. Google may require verification for broader distribution. In OAuth testing mode, refresh tokens can expire after seven days.
6. A free Apple Personal Team provisioning profile generally expires after seven days. Re-sign/reinstall as required by the signing tool. Live Activities and extensions must be included in the signed app.

## Build on macOS

Requires macOS, Xcode 16 or later, iOS 17 SDK, and XcodeGen.

```bash
brew install xcodegen
cd ApplePickupTracker
xcodegen generate
open ApplePickupTracker.xcodeproj
```

Select the `ApplePickupTracker` scheme, set your Personal Team under Signing & Capabilities, and use a unique bundle identifier for both app and widget extension. The bundle ID must match the iOS OAuth client configuration in Google Cloud.

To build an unsigned IPA for AltStore/Sideloadly to sign with your free Personal Team:

```bash
./package-unsigned-ipa.sh
```

The script writes `build/ApplePickupTracker-unsigned.ipa`. It does not sign the app. Free Personal Team installs typically need re-signing/reinstalling when the 7-day provisioning period expires.

## Configure Gmail OAuth

1. In Google Cloud Console, create a project and enable Gmail API.
2. Configure OAuth consent screen (External for a personal Gmail account) and add your account as a test user.
3. Create an **iOS OAuth client** for the app's bundle identifier.
4. Replace `YOUR_GOOGLE_IOS_OAUTH_CLIENT_ID` in `Gmail/GmailOAuth.swift` with the client ID.
5. Replace `YOUR_REVERSED_CLIENT_ID` in `Gmail/GmailOAuth.swift` and `Resources/Info.plist` with the reversed client ID (the iOS URL scheme) from Google Cloud.
6. Keep the requested scope to `https://www.googleapis.com/auth/gmail.readonly`.

No client secret belongs in the iOS app. The OAuth flow uses PKCE.

## First device test

1. Install the app using Xcode or your signing workflow.
2. Connect Gmail and grant read-only access.
3. Run Sync now. Verify the detected order number, product, store, and status against the Apple emails.
4. Open an order and tap **Show on Lock Screen & Dynamic Island**.
5. Verify Live Activities are enabled in iOS Settings for the app.
6. Test Ready for Pickup using a real notification email. Do not rely on synthetic emails for production status validation.

## Privacy

- OAuth tokens are stored in Keychain with `ThisDeviceOnly` accessibility.
- Parsed order data is stored locally in the app container.
- No analytics, advertising SDK, backend, or telemetry is included.
- Disconnect Gmail removes the locally stored OAuth tokens. Use the app's future Clear Data action to remove saved order records.

## GitHub Actions build (Windows-friendly)

The repository includes `.github/workflows/ios-build.yml`. Pushes to `main` or `master` run an unsigned iOS build on a GitHub-hosted macOS runner and upload `ApplePickupTracker-unsigned.ipa` as the `ApplePickupTracker-unsigned-ipa` artifact (14-day retention). See [`GITHUB_SETUP.md`](GITHUB_SETUP.md) for the Windows/GitHub Desktop setup and download steps.
