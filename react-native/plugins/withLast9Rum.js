/**
 * Expo config plugin: withLast9Rum
 *
 * The Last9 RUM React Native SDK (@last9/rum-react-native) wraps native iOS and
 * Android SDKs that are NOT published to the public CocoaPods trunk or Maven
 * Central — they live on Last9's CDN. Expo regenerates the native `android/`
 * and `ios/` projects on every `expo prebuild`, so any manual edit to those
 * folders would be wiped out and is not reproducible.
 *
 * This plugin makes the native dependency wiring reproducible by re-applying it
 * automatically during prebuild:
 *
 *   - Android: adds the Last9 Maven repo to the root `android/build.gradle`
 *     `allprojects { repositories { ... } }` block so Gradle can resolve
 *     `io.last9:rum-android`.
 *   - iOS: inserts `pod 'Last9RUM', :podspec => '<CDN podspec URL>'` into the
 *     main app target in `ios/Podfile` so CocoaPods can resolve the Last9RUM
 *     pod from the numbered CDN podspec.
 *
 * Both edits are idempotent — they check for an existing entry before writing,
 * so running prebuild repeatedly (or `prebuild --clean`) stays correct.
 *
 * Keep the iOS podspec version in sync with the @last9/rum-react-native version
 * pinned in package.json (currently 0.7.1).
 */
const {
  withProjectBuildGradle,
  withDangerousMod,
} = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

const ANDROID_MAVEN_URL = 'https://cdn.last9.io/rum-sdk/android/maven/';
const IOS_PODSPEC_URL =
  'https://cdn.last9.io/rum-sdk/ios/builds/0.7.1/Last9RUM.podspec';

/**
 * Inject the Last9 Maven repo into the root android/build.gradle
 * `allprojects { repositories { ... } }` block (idempotent).
 */
function withLast9AndroidMaven(config) {
  return withProjectBuildGradle(config, (cfg) => {
    let contents = cfg.modResults.contents;

    // Already present — nothing to do.
    if (contents.includes(ANDROID_MAVEN_URL)) {
      return cfg;
    }

    const mavenLine = `        maven { url '${ANDROID_MAVEN_URL}' }`;

    // Insert just inside the `allprojects { repositories {` block.
    const repositoriesAnchor = /allprojects\s*{[\s\S]*?repositories\s*{/;
    const match = contents.match(repositoriesAnchor);

    if (match) {
      const insertPos = match.index + match[0].length;
      contents =
        contents.slice(0, insertPos) +
        `\n${mavenLine}` +
        contents.slice(insertPos);
    } else {
      // Fallback: append a fresh allprojects block if the expected one is
      // missing (defensive — Expo's template always ships one).
      contents += `\nallprojects {\n  repositories {\n${mavenLine}\n  }\n}\n`;
    }

    cfg.modResults.contents = contents;
    return cfg;
  });
}

/**
 * Insert the Last9RUM pod into the main app target in ios/Podfile (idempotent).
 */
function withLast9IosPod(config) {
  return withDangerousMod(config, [
    'ios',
    (cfg) => {
      const podfilePath = path.join(
        cfg.modRequest.platformProjectRoot,
        'Podfile'
      );

      if (!fs.existsSync(podfilePath)) {
        return cfg;
      }

      let contents = fs.readFileSync(podfilePath, 'utf-8');

      // Already present — nothing to do. We check for the explicit CDN
      // podspec URL rather than the bare "Last9RUM" string: the autolinked
      // Last9RumReactNative podspec already *depends on* `Last9RUM`, so that
      // word is in the Podfile regardless. Only our explicit
      // `:podspec => <CDN url>` line tells CocoaPods where to find it.
      if (contents.includes(IOS_PODSPEC_URL)) {
        return cfg;
      }

      const podLine = [
        '',
        "  # Last9RUM is hosted on Last9's CDN, not the public CocoaPods trunk,",
        '  # so CocoaPods must be pointed at the explicit numbered podspec URL.',
        '  # Keep this version in sync with the @last9/rum-react-native version',
        '  # pinned in package.json; bump both together when upgrading.',
        `  pod 'Last9RUM', :podspec => '${IOS_PODSPEC_URL}'`,
      ].join('\n');

      // Insert right after the main app target declaration:
      //   target '<AppName>' do
      const targetAnchor = /target ['"][^'"]+['"] do/;
      const match = contents.match(targetAnchor);

      if (match) {
        const insertPos = match.index + match[0].length;
        contents =
          contents.slice(0, insertPos) +
          `\n${podLine}` +
          contents.slice(insertPos);
        fs.writeFileSync(podfilePath, contents, 'utf-8');
      }

      return cfg;
    },
  ]);
}

/**
 * Combined plugin entry point.
 */
function withLast9Rum(config) {
  config = withLast9AndroidMaven(config);
  config = withLast9IosPod(config);
  return config;
}

module.exports = withLast9Rum;
