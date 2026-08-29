/// Single source of truth for the version string the UI shows.
///
/// Lives in its own library so the rail (in `main.dart`) and the About group
/// (in `ui/settings_page.dart`) read the same constant instead of each holding
/// a literal that can drift. Keep in sync with `version:` in `pubspec.yaml`.
library;

const appVersion = '0.1.0';
