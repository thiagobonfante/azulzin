# Native shells (.plans/mobile Phase 1)

Thin Hotwire Native wrappers — navigation config only, no business logic. The server
stays the product; path configuration is served by Rails
(`/configurations/{ios,android}_v1.json`) with the bundled copies here as
first-launch/offline fallback (**keep them in sync at release time**).

## Status: SCAFFOLD — not yet built or run

These sources were written without Xcode/Android Studio available. Nothing below has
compiled, launched, or been device-tested. Before Phase 1 counts as done, run the
7-point VERIFY checklist in `.plans/mobile/02` §VERIFY / `03` §VERIFY on
simulator/emulator **and** one real device each.

### iOS (`ios/`) — needs Xcode to finish

The `.xcodeproj` cannot be hand-authored reliably; create it in Xcode and pull these
sources in:

1. Xcode 15+ → New iOS App project "Azulzin", bundle id `br.com.azulzin.app`,
   UIKit lifecycle (delete the SwiftUI template files), deployment target iOS 15.
2. Delete the generated AppDelegate/SceneDelegate; add the files from `ios/Azulzin/`.
3. Add the SPM package `https://github.com/hotwired/hotwire-native-ios` @ 1.2.2.
4. Add `path-configuration.json` and `Localizable.xcstrings` to the app target.
5. Debug scheme only: add an ATS exception for `http://localhost:3000`
   (`NSAppTransportSecurity → NSAllowsLocalNetworking`) in the Debug Info.plist.
6. Run on simulator against `bin/rails server`.

### Android (`android/`) — needs Android Studio / the Gradle wrapper to finish

The Gradle project files are complete but unverified:

1. Open `native/android` in Android Studio (or `gradle wrapper` then `./gradlew
   assembleDebug`); let it generate the Gradle wrapper (not committed).
2. minSdk 28, `dev.hotwire:core:1.2.5` + `dev.hotwire:navigation-fragments:1.2.5`.
3. Debug build points at `http://10.0.2.2:3000` (emulator loopback; cleartext allowed
   only via the debug-manifest network security config).

## Deferred to later phases (do NOT add here yet)

Biometric lock (Phase 3), push bridge component (Phase 4), share intake (Phase 5),
mic permission grants for chat (Phase 2 shell half): `NSMicrophoneUsageDescription` +
WKUIDelegate media-capture grant on iOS; `RECORD_AUDIO` +
`WebChromeClient.onPermissionRequest` on Android.
