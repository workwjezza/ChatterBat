# TestFlight release checklist

The repository now contains a dedicated **ChatterBatIOS** iOS target and
scheme. The app remains bring-your-own-key: API keys are entered on each
device and sent directly to Venice or OpenRouter. No ChatterBat backend or
server-side secret is required.

## One-time Apple setup

These steps require the owner of the Apple Developer and App Store Connect
accounts; they cannot be completed from source control alone.

1. Enroll in the Apple Developer Program and accept the required agreements.
2. In App Store Connect, create an iOS app with bundle ID
   `com.chatterbat.ios`.
3. In Xcode **Settings → Accounts**, sign in to the developer team configured
   in `project.yml`, or change `DEVELOPMENT_TEAM` there to the intended team.
4. Enable automatic signing for the **ChatterBatIOS** target. Xcode will create
   the App ID and distribution provisioning profile if the account permits it.
5. Add the App Store Connect metadata, privacy answers, age rating, support
   URL, and screenshots required for the selected distribution regions.

## Build and upload

From the repository root:

```sh
xcodegen generate
xcodebuild \
  -project ChatterBat.xcodeproj \
  -scheme ChatterBatIOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/ChatterBatIOS.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath /tmp/ChatterBatIOS.xcarchive \
  -exportOptionsPlist /path/to/AppStoreExportOptions.plist \
  -exportPath /tmp/ChatterBatIOS-export
```

Alternatively, open `ChatterBat.xcodeproj`, select the **ChatterBatIOS** scheme,
select **Any iOS Device (arm64)**, then choose **Product → Archive**. Upload
the archive from Xcode Organizer to App Store Connect and add it to an
internal TestFlight group.

## TestFlight smoke test

On a real device, verify first-run onboarding, API-key save/verification,
model catalog loading, streaming send/stop/retry, conversation persistence,
import/export, rotation, background/foreground recovery, and removal of the
app. TestFlight distribution and Apple signing are external release steps;
the local build can validate compilation but cannot create the App Store
Connect record or upload without the account's signing credentials.