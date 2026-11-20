# Apple Pickup Tracker (iOS)

Native SwiftUI app prototype for tracking Apple Store Pickup order emails from Outlook / Microsoft personal accounts. Mail parsing and order persistence run on-device; mailbox access uses OAuth 2.0 (PKCE) against Microsoft Graph with the read-only `Mail.Read` scope. The app does not send email contents or order data to a developer backend.

## Current first-version scope

- Microsoft OAuth authorization using `ASWebAuthenticationSession` + PKCE.
- Read-only Microsoft Graph scan for Apple order/pickup emails (full 365-day scan on first run, incremental afterwards).
- On-device HTML-to-text conversion and heuristic status extraction (Traditional and Simplified Chinese, English).
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
5. Microsoft `Mail.Read` is a delegated permission on a personal-account (`consumers`) app registration. Keep the redirect URI and bundle identifier in sync with the Azure app registration.
6. A free Apple Personal Team provisioning profile generally expires after seven days. Re-sign/reinstall as required by the signing tool. Live Activities and extensions must be included in the signed app.

## Build on macOS

Requires macOS, Xcode 26 or later (iOS 26 SDK), an iOS 17 deployment target, and XcodeGen. Liquid Glass APIs are compiled from the iOS 26 SDK and used at runtime only on iOS 26; earlier systems keep a material fallback.

```bash
brew install xcodegen
cd ApplePickupTracker
xcodegen generate
open ApplePickupTracker.xcodeproj
```

Select the `ApplePickupTracker` scheme, set your Personal Team under Signing & Capabilities, and use a unique bundle identifier for both app and widget extension. The bundle ID must match the redirect URI registered in Azure.

To build an unsigned IPA for AltStore/Sideloadly to sign with your free Personal Team:

```bash
./package-unsigned-ipa.sh
```

The script writes `build/ApplePickupTracker-unsigned.ipa`. It does not sign the app. Free Personal Team installs typically need re-signing/reinstalling when the 7-day provisioning period expires.

## Configure Microsoft OAuth

1. In the Azure portal, register an application that supports personal Microsoft accounts and add a **Mobile and desktop** redirect URI `msauth.<bundle id>://auth`.
2. Add the delegated Microsoft Graph permissions `Mail.Read` and `User.Read`.
3. Put the Application (client) ID into `clientID` in `Outlook/OutlookOAuth.swift`, and make `redirectURI` / `callbackScheme` match your bundle identifier.
4. Make the same scheme (`msauth.<bundle id>`) appear under `CFBundleURLSchemes` in `Resources/Info.plist` and `project.yml`.

No client secret belongs in the iOS app. The OAuth flow uses PKCE.

## First device test

1. Install the app using Xcode or your signing workflow.
2. Connect Outlook and grant read-only access.
3. Run Sync now. Verify the detected order number, product, store, and status against the Apple emails.
4. Open an order and tap **Show on Lock Screen & Dynamic Island**.
5. Verify Live Activities are enabled in iOS Settings for the app.
6. Test Ready for Pickup using a real notification email. Do not rely on synthetic emails for production status validation.

## Privacy

- OAuth tokens are stored in Keychain with `ThisDeviceOnly` accessibility.
- Parsed order data is stored locally in the app container.
- No analytics, advertising SDK, backend, or telemetry is included.
- Disconnect Outlook removes the locally stored OAuth tokens. Use the app's future Clear Data action to remove saved order records.

## GitHub Actions build (Windows-friendly)

The repository includes `.github/workflows/ios-build.yml`. Pushes to `main`, `master`, or `cursor/**`, and pull requests, run an unsigned iOS build on a GitHub-hosted macOS 15 runner with Xcode 26 selected, and upload `ApplePickupTracker-unsigned.ipa` as the `ApplePickupTracker-unsigned-ipa` artifact (14-day retention). See [`GITHUB_SETUP.md`](GITHUB_SETUP.md) for the Windows/GitHub Desktop setup and download steps.
