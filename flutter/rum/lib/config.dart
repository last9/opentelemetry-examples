// Last9 RUM SDK configuration.
//
// Secret/config values are injected at build time via
// --dart-define-from-file=last9.env.json (git-ignored). See
// last9.env.example.json for the expected keys.
const String kBaseUrl = String.fromEnvironment('LAST9_BASE_URL');
const String kClientToken = String.fromEnvironment('LAST9_CLIENT_TOKEN');
const String kOrigin = String.fromEnvironment('LAST9_ORIGIN');

// Non-secret config lives in source.
const String kServiceName = 'rum-flutter-example';
const String kServiceVersion = '1.0.0';
const String kAppBuildId = '1.0.0-dev';
const String kDeploymentEnvironment = 'development';
const int kSampleRate = 100;

/// JSONPlaceholder mock API — https://jsonplaceholder.typicode.com/guide/
const String kApiBase = 'https://jsonplaceholder.typicode.com';

/// The Last9 dashboard is a CSR React SPA — its origin
/// (https://app.last9.io) is already in the dev clientToken's whitelist, so
/// the WebView's Browser RUM exports won't 403. Open the WebView tab and the
/// page loads — no local dev server or adb reverse plumbing required.
const String kWebViewTestUrl = 'https://app.last9.io/';
const String kBrowserRumSdkUrl =
    'https://cdn.last9.io/rum-sdk/builds/2.5.0-alpha/l9.umd.js';
