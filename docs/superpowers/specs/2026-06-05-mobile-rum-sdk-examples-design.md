# Mobile RUM SDK Examples — Design

Date: 2026-06-05
Status: Approved (pending user spec review)

## Goal

Add runnable example apps for Last9's four mobile Real User Monitoring (RUM)
SDKs — Android, iOS, Flutter, React Native — to the open-source
`opentelemetry-examples` repository. Each example must run once a developer
supplies a Last9 token in a git-ignored env file, and must demonstrate the
full RUM feature surface. No secrets may ever be committed.

Source of truth for SDK APIs and install steps: the SDK packages and READMEs in
`~/code/browser/main/packages/{android,ios,flutter,react-native}`.

## Scope

In scope: android, ios, flutter, react-native RUM SDKs. The browser/web RUM SDK
is **out of scope**.

SDK version pinned across all examples: **v0.7.1** (current as of 2026-06-04,
distributed from `https://cdn.last9.io/rum-sdk/...`).

## Directory Layout

All four examples live under a consistent `<platform>/rum/` path:

A platform dir gets a `rum/` subdir **only** when it must coexist with sibling
examples; otherwise the example lives directly at the platform dir.

| Path | State | Stack |
|------|-------|-------|
| `android/` | New top-level dir (only example there) | Gradle (Kotlin DSL) + Jetpack Compose + Navigation Compose |
| `ios/` | **Replaces** the existing `ios/` RUM example (old GitHub-distributed SDK) | SwiftUI + NavigationStack, XcodeGen + CocoaPods |
| `flutter/rum/` | New subdir, alongside untouched `flutter/approach-a*` / `flutter/approach-b*` (so it keeps the `rum/` subdir) | Flutter + Navigator routes + `L9NavigationObserver` |
| `react-native/` | New top-level dir (only example there) | React Native + React Navigation (native-stack) + `L9ReactNavigationInstrumentation` |

The existing `ios/` top-level example files (`Sources/`, `Package.swift`,
`README.md`, `.env.example`, `.gitignore`) are removed and replaced by the new
`ios/` runnable demo on the CDN-distributed v0.7.1 SDK.

## Common App Flow

Every example app has **three real screens reached by route navigation** (not
local-state view switching), so automatic view tracking fires on navigation:

1. **Home** — `identify()` a demo user on a button, `clearUser()`, send a
   custom event via `addEvent()`, set global `spanAttributes()`, and buttons to
   navigate to the other screens.
2. **Network** — a GET and a POST to `https://jsonplaceholder.typicode.com`
   (public, HTTPS, no CORS issues, no auth). Generates parent HTTP spans plus
   DNS/TCP/TLS/TTFB phase child spans.
3. **Errors** — a button that triggers a *caught* error routed through
   `captureError()`, and a button that throws an *uncaught* error to exercise
   automatic error instrumentation. Also exposes `getSessionId()` (displayed)
   and `flush()`.

SDK init happens at the app entry point (Application / App / main / index)
exactly as each SDK README prescribes.

### Feature coverage matrix (every example must demonstrate all)

- `initialize` with required + a few optional config fields
- Automatic view tracking via navigation integration
- Automatic network instrumentation (the public-API calls)
- `identify` / `clearUser`
- `captureError` (caught) + uncaught-error path
- `addEvent` custom event
- `spanAttributes` global attributes
- `getSessionId`
- `flush`

## Secret / Token Injection (per platform, all git-ignored)

Secret/environment values held in env files: `clientToken`, `baseUrl` (contains
the org path), `origin`. Non-secret values (`serviceName`, `serviceVersion`,
`deploymentEnvironment`) stay in source code.

| Platform | Mechanism | Committed template |
|----------|-----------|--------------------|
| Android | `local.properties` (git-ignored by Android convention) → read in `build.gradle.kts` → `BuildConfig` fields | `local.properties.example` |
| iOS | `Secrets.xcconfig` → surfaced into `Info.plist` keys → read at runtime via `Bundle.main.object(forInfoDictionaryKey:)` | `Secrets.example.xcconfig` |
| Flutter | `--dart-define-from-file=last9.env.json` → `String.fromEnvironment` | `last9.env.example.json` |
| React Native | `.env` via `react-native-dotenv` babel transform (JS-only; SDK init is JS-side) | `.env.example` |

Each template uses placeholders only (e.g. `your-client-token`,
`https://otlp-ext-aps1.last9.io/v1/otlp/organizations/<org>`).

## Dependency Sourcing (nothing proprietary committed)

- **Android** — add CDN Maven repo to `settings.gradle.kts`; Gradle resolves
  `io.last9:rum-android:0.7.1`. Nothing vendored.
- **iOS** — `Podfile`: `pod 'Last9RUM', :podspec => 'https://cdn.last9.io/rum-sdk/ios/builds/0.7.1/Last9RUM.podspec'`. No checksum step. `pod install` produces the `.xcworkspace`.
- **Flutter** — README + a helper script download and checksum-verify the SDK
  tarball into git-ignored `vendor/`, then `pubspec.yaml` uses a path
  dependency `last9_rum_flutter: { path: vendor/flutter }`. Native Android pulls
  CDN Maven; native iOS pulls CDN podspec (per Flutter SDK README steps 3 & 4).
- **React Native** — `npm install https://cdn.last9.io/rum-sdk/react-native/builds/0.7.1/last9-rum-react-native-0.7.1.tgz`. Android CDN Maven + iOS CDN podspec wiring per RN SDK README.

## iOS Project Generation

Commit a small `project.yml`; the project is generated with
`brew install xcodegen && xcodegen generate`, then `pod install`, then open the
`.xcworkspace`. The generated `*.xcodeproj` / `*.xcworkspace` and `Pods/` are
git-ignored. Avoids committing a bulky, Xcode-version-bound `pbxproj`.

## Project Scaffolding

Subagents generate **real** native scaffolds using official tooling so the apps
are genuinely runnable:

- Android — full Gradle project including the Gradle wrapper.
- iOS — XcodeGen `project.yml` + SwiftUI sources + `Podfile`.
- Flutter — `flutter create` scaffold, then RUM wiring + screens.
- React Native — React Native community CLI scaffold, then RUM wiring + screens.

## Open-Source Safety (.gitignore + audit)

Every example ships a `.gitignore` covering at minimum: env/secret files
(`.env`, `.env.local`, `local.properties`, `Secrets.xcconfig`,
`last9.env.json`), dependencies (`node_modules/`, `Pods/`, `vendor/`,
`.dart_tool/`, `.gradle/`), build output (`build/`, `dist/`, `DerivedData/`,
`*.app`, `*.apk`, `*.ipa`), and IDE/OS files (`.idea/`, `.vscode/`,
`.DS_Store`), and logs.

For the **XcodeGen-based iOS example only**, the generated `*.xcodeproj` /
`*.xcworkspace` and `xcuserdata/` are git-ignored (they are regenerated by
`xcodegen generate` + `pod install`). The Flutter and React Native examples
keep the `ios/*.xcodeproj` that their official scaffolders (`flutter create` /
RN CLI) commit by convention — those are required for the project to open and
contain no secrets. The RN scaffold's `android/app/debug.keystore` (the
standard public debug-only keystore, password `android`) is likewise kept.

A final **security-review subagent** greps the entire new tree for
token/secret-shaped strings (high-entropy values, `clientToken:` with non-
placeholder values, real org slugs, API keys) before completion. Only
`*.example` templates with placeholders are allowed.

## Documentation

Per the repo's CLAUDE.md rule: **one `README.md` per example**, no extra docs
files. Each README follows the repo structure: brief description, prerequisites
(incl. SDK version + toolchain), quick-start run steps (the exact commands to
build and run with the token env file), a configuration table, and a
verification section ("what you should see in the Last9 dashboard: a session,
views per screen, HTTP spans, an error"). READMEs link to Last9 docs rather than
duplicating SDK internals.

## Verification

Verification tier: **static correctness** against the SDK READMEs, plus every
example carries exact run steps so the user can build/run later with a real
token. Subagents use official CLIs to produce correct boilerplate and may run
non-token build steps (e.g. `flutter pub get`, `xcodegen generate`,
`gradle tasks`) where they do not require a real token or network artifact, but
a full token-authenticated end-to-end run is the user's responsibility.

## Non-Goals

- Browser/web RUM SDK example.
- CI wiring for the examples.
- Committing the SDK artifacts themselves.
- Full token-authenticated end-to-end build verification by the agent.

## Root README Update

Add a "Mobile RUM" section/table to the repo root `README.md` listing the four
new examples and the telemetry they emit, consistent with existing tables.
