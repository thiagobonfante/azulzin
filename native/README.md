# Native shells (.plans/mobile Phase 1)

Thin Hotwire Native wrappers — navigation config only, no business logic. The server
stays the product; path configuration is served by Rails
(`/configurations/{ios,android}_v1.json`) with the bundled copies here as
first-launch/offline fallback (**keep them in sync at release time**).

## Status

- **iOS: builds and launches on the simulator** (Xcode 26, `xcodebuild` green,
  2026-07-19) — the tab bar, nav-bar titles, native variant (no drawer, no Google
  button) all confirmed against a local `bin/rails server`. Still pending: the full
  7-point VERIFY checklist in `.plans/mobile/02` §VERIFY (cookie persistence across
  relaunch, modal recede, external links, error view) on simulator **and** a real
  device.
- **Android: scaffold only** — never compiled (no Android Studio yet). See below.

### iOS (`ios/app/`)

`app.xcodeproj` (project/product name "app", bundle id `br.com.azulzin.app`,
deployment target iOS 15, SPM `hotwire-native-ios` pinned 1.2.2). The `app/` folder is
a synchronized group — files dropped there join the target automatically.

- Debug points at `http://localhost:3000`; the ATS local-networking exception lives in
  `Info-Debug.plist`, wired via `INFOPLIST_FILE` **only in the Debug configuration**
  (merged into the generated Info.plist). Release uses the generated plist alone.
- The scene manifest is generated; `AppDelegate` sets
  `configuration.delegateClass = SceneDelegate.self` in code, so don't add a manifest
  delegate entry by hand.
- Run: `open ios/app/app.xcodeproj`, scheme **app**, any iPhone simulator, with
  `bin/rails server` running. Or headless:
  `xcodebuild -project app.xcodeproj -scheme app -destination 'generic/platform=iOS Simulator' build`.

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
