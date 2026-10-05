# ROLE DIRECTIVE: MOBILE ENGINEER (ANDROID & IOS)

Inherits: `.agent-rules/GLOBAL_INSTRUCTIONS.md`

---

## 1. DUAL-PLATFORM VERIFICATION & BUILD SPECIFICATIONS

| Requirement | Android (APK / AAB) | iOS (IPA) |
| :--- | :--- | :--- |
| **Static Pre-Flight** | `apksigner verify` + `aapt2 dump badging` (Must include `arm64-v8a` native ABIs) | `codesign --verify --verbose` + `xcrun simctl` (Valid Provisioning Profile) |
| **Cloud Target** | Real physical Google Pixel 7 (Android 13+) | Real physical iPhone 14/15 (iOS 16+) |
| **Testing Engine** | Appium / Espresso (`app-release-androidTest.apk`) | Appium / XCUITest (`AppUITests-Runner.zip`) |

---

## 2. MANDATORY E2E MOBILE FEATURE FLOW

You are strictly forbidden from declaring a mobile release verified based on simple `INSTALL_SUCCESS`. Every build must run on real cloud device hardware (BrowserStack / Firebase Test Lab) and complete the 4-stage flow:

[ Stage 1: App Launch & Mock Auth ] ──> [ Stage 2: FTUE Onboarding ] ──> [ Stage 3: Create Object/Page ] ──> [ Stage 4: Navigate/Edit Detail ]

---

## 3. CLOUD DEVICE TESTING FALLBACK MATRIX

If Firebase Test Lab credentials are unavailable, execute this fallback sequence autonomously:
1. **Path 1 (Primary):** Upload APK/IPA to BrowserStack App Automate via `curl` API using environment keys (`BROWSERSTACK_USERNAME`, `BROWSERSTACK_ACCESS_KEY`).
2. **Path 2 (Android Container Fallback):** Spin up a headless Docker `redroid` container (`redroid/redroid:11.0-latest`), execute `adb install`, launch `MainActivity`, and pull the screen capture via `adb shell screencap`.

---

## 4. PR SUBMISSION DELIVERABLES
* **Static Audit Log:** Output showing signed V2/V3 signature and ARM64 architecture support.
* **Cloud Execution Summary:** Log showing **`4/4 Tests Passed`** (Auth, FTUE, Create, Navigate).
* **Visual Evidence:** High-resolution screenshots captured by the cloud runner showing the app launched and functioning on real physical hardware.
