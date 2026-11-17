/// Build-time configuration. Override with --dart-define, e.g.
///   flutter run --dart-define=API_BASE_URL=https://api.example.com
///
/// Never put secrets here: everything in an APK can be extracted.
class AppConfig {
  AppConfig._();

  /// Display name. "TRON" is a third-party trademark — confirm you may use it
  /// in the app name before publishing, or choose your own brand name.
  static const String appName = 'TRON Wallet';
  static const String appVersion = '0.1.0';

  /// 10.0.2.2 is the host machine as seen from the Android emulator.
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  static const String supportEmail =
      String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'support@example.com');
  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL', defaultValue: 'https://example.com/privacy');
  static const String termsUrl =
      String.fromEnvironment('TERMS_URL', defaultValue: 'https://example.com/terms');

  /// BIP44 path used by TronLink and most TRON wallets.
  static const String derivationPath = "m/44'/195'/0'/0/0";

  static const int pinLength = 6;
}
